#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

colima_bin >/dev/null || { miss "colima not installed"; verify_result; }
if ! vm_ssh true >/dev/null 2>&1; then
  miss "the agent VM is not reachable"
  verify_result
fi

image="${VM_AGENT_IMAGE:-agent-machine/agent:latest}"

if vm_ssh docker info >/dev/null 2>&1; then
  ok "container runtime responding in the VM"
else
  miss "docker is not responding inside the VM"
  verify_result
fi

# The prerequisite that makes containers safe at all. Checked here as well as in apply,
# because make-vm-network-bounded could be re-applied from an older ruleset later.
if vm_ssh sudo nft list chain inet agentguard forward >/dev/null 2>&1; then
  ok "forward chain present — container traffic is filtered"
else
  miss "no forward chain in agentguard — containers can reach the tailnet and your LAN"
fi

if vm_ssh docker image inspect "$image" >/dev/null 2>&1; then
  ok "agent image $image built"
else
  miss "agent image $image not built"
fi

for tier in trusted untrusted; do
  vm_ssh docker network inspect "agent-$tier" >/dev/null 2>&1 \
    && ok "network agent-$tier exists" \
    || miss "network agent-$tier missing — containers would share the default bridge"
done

for tier in trusted untrusted; do
  vm_ssh docker volume inspect "agent-claude-$tier" >/dev/null 2>&1 \
    && ok "credential volume agent-claude-$tier exists" \
    || miss "credential volume agent-claude-$tier missing — sign-in would not survive a rebuild"
done

if vm_ssh sh -c 'test -x ~/.local/bin/agent-run' >/dev/null 2>&1; then
  ok "agent-run launcher present and executable"

  # The launcher bakes its resource caps in at write time, so resizing the VM leaves them
  # stale and silently wrong. Recompute what they should be and compare.
  want_mem=$(( ${VM_MEMORY:-8} / 2 )); [ "$want_mem" -lt 2 ] && want_mem=2
  want_cpu=$(( ${VM_CPUS:-4} - 1 ));   [ "$want_cpu" -lt 1 ] && want_cpu=1
  launcher=$(vm_ssh sh -c 'cat ~/.local/bin/agent-run' 2>/dev/null | /usr/bin/tr -d '\r')

  printf '%s' "$launcher" | /usr/bin/grep -q -- "--memory ${want_mem}g" \
    && ok "per-container memory cap ${want_mem}g matches VM_MEMORY=${VM_MEMORY:-unset}" \
    || miss "agent-run memory cap is stale for VM_MEMORY=${VM_MEMORY:-unset} (expected ${want_mem}g) — re-apply this recipe"

  printf '%s' "$launcher" | /usr/bin/grep -q -- "--cpus $want_cpu" \
    && ok "per-container CPU cap $want_cpu matches VM_CPUS=${VM_CPUS:-unset}" \
    || miss "agent-run CPU cap is stale for VM_CPUS=${VM_CPUS:-unset} (expected $want_cpu) — re-apply this recipe"
else
  miss "no ~/.local/bin/agent-run launcher in the VM"
fi

# Behaviour, not configuration: confirm the image actually runs non-root and carries the
# agent. An image that builds but comes up as root is not the image this recipe promises.
whoami=$(vm_ssh docker run --rm "$image" whoami 2>/dev/null | /usr/bin/tr -d '\r')
if [ "$whoami" = "agent" ]; then
  ok "image runs as non-root user 'agent'"
elif [ -n "$whoami" ]; then
  miss "image runs as '$whoami' — expected the unprivileged 'agent' user"
else
  miss "could not run the image to check its user"
fi

ver=$(vm_ssh docker run --rm "$image" claude --version 2>/dev/null | /usr/bin/tr -d '\r')
[ -n "$ver" ] && ok "claude in the image: $ver" \
              || miss "claude is not on PATH inside the image"

# The load-bearing check: containers must not bypass the VM's network policy. Their traffic
# is forwarded rather than originated, so it is governed by a different nftables chain, and
# a ruleset covering only the output hook looks correct in any test run over `colima ssh`
# while leaving every container free to reach the tailnet and the LAN.
#
# The probe runs in the agent image using bash's /dev/tcp, so it needs no second image and
# no registry — this is a verify, and a verify that reaches the network is neither cheap
# nor trustworthy when the network is the thing under test.
#
# Three outcomes, not two. A probe that could not run must never be mistaken for a probe
# that was refused, or the firewall reports green on a test that never executed.
cprobe() { # $1 = address, $2 = port -> open | closed | unknown
  vm_ssh docker run --rm --network "agent-trusted" "$image" \
    bash -c "timeout 3 bash -c 'echo > /dev/tcp/$1/$2' 2>/dev/null && echo open || echo closed" \
    2>/dev/null | /usr/bin/tr -d '\r' | /usr/bin/grep -E '^(open|closed)$' || echo unknown
}

for probe in "100.100.100.100 53 the tailnet range" "192.168.1.1 80 your LAN"; do
  set -- $probe
  case "$(cprobe "$1" "$2")" in
    closed) ok "$3 blocked from inside a container" ;;
    open)   miss "a container can reach $3 — the forward hook is not filtering" ;;
    *)      blocked "could not probe $3 from a container — container egress is unverified, not proven good" ;;
  esac
done

verify_result
