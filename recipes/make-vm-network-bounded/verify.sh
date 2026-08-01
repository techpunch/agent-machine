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
# container's traffic is forwarded instead, so it is governed by a different chain. The
# chain's existence is checked here; the behavioural probe from inside a real container
# lives in have-containers, which is the recipe that has an image to run it in.
if vm_ssh sh -c 'command -v docker >/dev/null' >/dev/null 2>&1 \
   && vm_ssh docker info >/dev/null 2>&1; then
  if vm_ssh sudo nft list chain inet agentguard forward >/dev/null 2>&1; then
    ok "forward chain present (container traffic is filtered)"
  else
    miss "no forward chain — containers would bypass every denial above"
  fi
else
  skip "no container runtime in the VM yet — forward-path checks not applicable"
fi

verify_result
