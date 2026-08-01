#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi

colima_bin >/dev/null || die "colima not installed — run have-agent-vm first"
vm_ssh true >/dev/null 2>&1 || die "the agent VM is not reachable — run have-agent-vm first"

# The guest's resolver lives on an RFC1918 address, so the drops below would take DNS with
# them. Find it now and carve out port 53 to that address only — not the gateway host,
# which is also the route to the Mac.
resolvers=$(vm_ssh sh -c "grep '^nameserver' /etc/resolv.conf | awk '{print \$2}'" 2>/dev/null \
            | /usr/bin/tr -d '\r')
[ -n "$resolvers" ] || die "could not read the VM's resolvers from /etc/resolv.conf"
note "carving out DNS for: $(printf '%s' "$resolvers" | /usr/bin/tr '\n' ' ')"

dns_rules=""
for r in $resolvers; do
  case "$r" in
    *:*) continue ;;   # IPv6 resolvers are handled by the v6 chain's accept below
  esac
  dns_rules="$dns_rules
    ip daddr $r udp dport 53 accept
    ip daddr $r tcp dport 53 accept"
done

ruleset=$(cat <<NFT
#!/usr/sbin/nft -f
# Managed by the agent-machine cookbook (recipes/make-vm-network-bounded).
# Full egress to the internet; no path inward to the host, the tailnet, or the LAN.
flush ruleset

table inet agentguard {
  # The denials, once, so the output and forward hooks cannot drift apart.
  chain deny_inward {
    # Tailscale's range first — the inward path specific to this design.
    ip daddr 100.64.0.0/10 reject with icmp type admin-prohibited
    ip daddr 10.0.0.0/8     reject with icmp type admin-prohibited
    ip daddr 172.16.0.0/12  reject with icmp type admin-prohibited
    ip daddr 192.168.0.0/16 reject with icmp type admin-prohibited
    ip daddr 169.254.0.0/16 reject with icmp type admin-prohibited

    ip6 daddr fc00::/7  reject with icmpv6 type admin-prohibited
    ip6 daddr fe80::/10 reject with icmpv6 type admin-prohibited
  }

  # Traffic the VM itself originates.
  chain output {
    type filter hook output priority -10; policy accept;

    ct state established,related accept
    oifname "lo" accept
$dns_rules

    jump deny_inward
  }

  # Traffic the VM routes on behalf of something else — which means containers. Without
  # this hook a container bypasses every denial above, because forwarded packets never
  # touch the output hook. Priority -10 puts this ahead of Docker's own FORWARD rules, so
  # a reject here wins no matter what the daemon installs later.
  chain forward {
    type filter hook forward priority -10; policy accept;

    ct state established,related accept
$dns_rules

    jump deny_inward
  }
}
NFT
)

note "installing nftables ruleset in the VM"
vm_ssh sudo sh -c 'command -v nft >/dev/null || { apt-get update -qq && apt-get install -y -qq nftables; }' \
  || die "could not install nftables in the VM"

printf '%s\n' "$ruleset" | vm_ssh sudo tee /etc/nftables.conf >/dev/null \
  || die "could not write /etc/nftables.conf in the VM"

vm_ssh sudo nft -f /etc/nftables.conf || die "the ruleset was rejected by nft — see the error above"
vm_ssh sudo systemctl enable --now nftables >/dev/null 2>&1 \
  || note "could not enable the nftables service; rules are live but may not survive a VM restart"

ok "ruleset installed and loaded"

# `flush ruleset` above clears every table, including the one Docker manages. Docker only
# rebuilds its rules at startup, so a running daemon would be left with broken container
# networking until something restarted it. Do that here rather than leaving it to be
# discovered later.
if vm_ssh sudo systemctl is-active docker >/dev/null 2>&1; then
  note "restarting docker so it reinstalls its own rules after the flush"
  vm_ssh sudo systemctl restart docker >/dev/null 2>&1 \
    || note "could not restart docker — do it by hand or container networking will be broken"

fi

set_server_var VM_NETWORK_BOUNDED "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
