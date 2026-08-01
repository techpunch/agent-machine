#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

colima_bin >/dev/null || { miss "colima not installed"; verify_result; }
if ! vm_ssh true >/dev/null 2>&1; then
  miss "the agent VM is not reachable"
  verify_result
fi

if vm_ssh sudo nft list table inet agentguard >/dev/null 2>&1; then
  ok "agentguard ruleset loaded"
else
  miss "agentguard ruleset not loaded in the VM"
  verify_result
fi

vm_ssh sudo systemctl is-enabled nftables >/dev/null 2>&1 \
  && ok "nftables service enabled (rules survive a VM restart)" \
  || miss "nftables service not enabled — rules will vanish on VM restart"

# Behaviour, not configuration. A ruleset that loads but does not block is worse than none,
# because you would trust it.
probe() { # $1 = address, $2 = port
  vm_ssh sh -c "timeout 3 sh -c 'echo > /dev/tcp/$1/$2' 2>/dev/null && echo open || echo closed" \
    2>/dev/null | /usr/bin/tr -d '\r'
}

if vm_ssh sh -c 'timeout 6 getent hosts github.com >/dev/null && echo ok' 2>/dev/null | grep -q ok; then
  ok "DNS resolves in the VM"
else
  miss "DNS does not resolve in the VM — the resolver carve-out is wrong"
fi

if [ "$(probe github.com 443)" = "open" ]; then
  ok "public internet reachable (github.com:443)"
else
  miss "cannot reach the public internet — the rules are too tight"
fi

# 100.100.100.100 is Tailscale's MagicDNS address, inside 100.64.0.0/10.
if [ "$(probe 100.100.100.100 53)" = "closed" ]; then
  ok "tailnet range blocked (100.64.0.0/10)"
else
  miss "the VM can reach the tailnet range — a compromise could pivot to your other machines"
fi

if [ "$(probe 192.168.1.1 80)" = "closed" ]; then
  ok "LAN range blocked (192.168.0.0/16)"
else
  miss "the VM can reach your LAN"
fi

# Everything above tests the VM's own network namespace, which is the output hook. A
# container's traffic is forwarded instead, so it is governed by a different chain and has
# to be probed separately — a ruleset that blocks the VM but not its containers looks
# correct here while leaving the real agent workload unbounded.
if vm_ssh sh -c 'command -v docker >/dev/null' >/dev/null 2>&1 \
   && vm_ssh docker info >/dev/null 2>&1; then

  if vm_ssh sudo nft list chain inet agentguard forward >/dev/null 2>&1; then
    ok "forward chain present (container traffic is filtered)"
  else
    miss "no forward chain — containers bypass every denial above"
  fi

  # A probe that cannot run must never look like a probe that was refused. `nc -z` exits 1
  # for a blocked port, and docker exits non-zero when the image is missing or the daemon
  # is unhappy — collapsing those two into "closed" would report a working firewall on the
  # strength of a test that never executed. So the probe prints its own verdict and
  # anything else is treated as unknown.
  #
  # The image is local: apply pulls it, precisely so verify stays offline and cheap.
  cprobe() { # $1 = address, $2 = port -> open | closed | unknown
    vm_ssh docker run --rm --network bridge "$PROBE_IMAGE" \
      sh -c "nc -z -w 3 $1 $2 && echo open || echo closed" 2>/dev/null \
      | /usr/bin/tr -d '\r' | /usr/bin/grep -E '^(open|closed)$' || echo unknown
  }

  if vm_ssh docker image inspect "$PROBE_IMAGE" >/dev/null 2>&1; then
    for probe in "100.100.100.100 53 the tailnet range" "192.168.1.1 80 your LAN"; do
      set -- $probe
      case "$(cprobe "$1" "$2")" in
        closed)  ok "$3 blocked from inside a container" ;;
        open)    miss "a container can reach $3 — the forward hook is not filtering" ;;
        *)       blocked "could not probe $3 from a container — the firewall is unverified, not proven good" ;;
      esac
    done
  else
    blocked "probe image $PROBE_IMAGE is not present in the VM; re-run apply. Container egress is unverified."
  fi
else
  skip "no container runtime in the VM yet — forward-path checks not applicable"
fi

verify_result
