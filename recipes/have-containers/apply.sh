#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi

colima_bin >/dev/null || die "colima not installed — run have-agent-vm first"
vm_ssh true >/dev/null 2>&1 || die "the agent VM is not reachable — run have-agent-vm first"

image="${VM_AGENT_IMAGE:-agent-machine/agent:latest}"
here="$(cd "$(dirname "$0")" && pwd)"

# A per-container ceiling, derived from the VM rather than hardcoded, so it stays sensible
# if the VM is resized. Half the guest: docker limits are ceilings rather than
# reservations, so two containers can each be allowed half without either being starved
# unless both peak at once — and a limit too low just OOM-kills an ordinary build.
mem_cap=$(( ${VM_MEMORY:-8} / 2 ))
[ "$mem_cap" -lt 2 ] && mem_cap=2

# Same reasoning for CPU: a ceiling, not a reservation. Without it a runaway build pegs
# every core the VM has and the multiplexer stops responding, which is the moment you most
# want to be able to attach and kill it.
cpu_cap=$(( ${VM_CPUS:-4} - 1 ))
[ "$cpu_cap" -lt 1 ] && cpu_cap=1

# A container's traffic is forwarded, not originated by the VM, so it is only bounded if
# the ruleset covers the forward hook. Refuse to create containers before that is true —
# otherwise this recipe silently hands agents a route to the tailnet and the LAN.
if ! vm_ssh sudo nft list chain inet agentguard forward >/dev/null 2>&1; then
  die "the VM's network policy has no forward chain, so containers would bypass it.
       Re-run: ./bin/cookbook apply make-vm-network-bounded"
fi
ok "forward chain present — container traffic is filtered"

if vm_ssh docker info >/dev/null 2>&1; then
  ok "container runtime responding in the VM"
else
  die "docker is not responding inside the VM. Colima provides it; check 'colima status --profile ${VM_PROFILE:-agent}'"
fi

# Build from the committed Dockerfile, piped in as a build context of exactly one file, so
# nothing from the host or the VM's filesystem can leak into the image.
note "building $image in the VM"
/usr/bin/tar -C "$here" -cf - Dockerfile \
  | vm_ssh docker build -t "$image" -f Dockerfile - \
  || die "the image build failed inside the VM"
ok "built $image"

# One isolated network per trust tier. Docker's default bridge lets every container reach
# every other one, which would put an untrusted project's agent next to your other
# projects' listening ports. Each tier gets its own bridge instead.
for tier in trusted untrusted; do
  net="agent-$tier"
  if vm_ssh docker network inspect "$net" >/dev/null 2>&1; then
    ok "network $net exists"
  else
    vm_ssh docker network create "$net" >/dev/null \
      && ok "created network $net" \
      || die "could not create docker network $net"
  fi
done

# One credential volume per trust tier, kept out of the image so a rebuild does not cost a
# re-login. Two volumes rather than one because an untrusted project must not see the token
# you use for everything else — but it still needs *a* token, or the agent cannot run and
# the tier is decorative. So it gets its own, signed in separately and revocable on its own.
for tier in trusted untrusted; do
  vol="agent-claude-$tier"
  vm_ssh docker volume inspect "$vol" >/dev/null 2>&1 \
    || vm_ssh docker volume create "$vol" >/dev/null
  ok "credential volume $vol ready"
done

# The launcher. Everything about the isolation posture lives here rather than in a README,
# so there is one command to get right and no flags to remember at 11pm.
vm_ssh sh -c 'mkdir -p ~/.local/bin && cat > ~/.local/bin/agent-run' <<CONF
#!/bin/sh
# Managed by the agent-machine cookbook (recipes/have-containers).
#
#   agent-run <project-dir> [trusted|untrusted]
#
# Starts a throwaway container for one project. Trusted projects share a network and the
# credential volume; untrusted ones get neither, because the rule is a new boundary
# whenever you cross a trust boundary.
set -eu
dir=\${1:?usage: agent-run <project-dir> [trusted|untrusted]}
tier=\${2:-trusted}
[ -d "\$dir" ] || { echo "no such directory: \$dir" >&2; exit 1; }
name="agent-\$(basename "\$dir")-\$\$"

case "\$tier" in
  trusted|untrusted) ;;
  *) echo "tier must be 'trusted' or 'untrusted', got: \$tier" >&2; exit 1 ;;
esac

# Each tier gets its own network and its own credential volume. An untrusted project never
# sees the token your other work uses — it signs in once against its own, which you can
# revoke alone without touching anything else.
exec docker run --rm -it --name "\$name" \\
  --network "agent-\$tier" \\
  --cap-drop ALL --security-opt no-new-privileges \\
  --pids-limit 512 --memory ${mem_cap}g --cpus $cpu_cap \\
  -v "agent-claude-\$tier:/home/agent/.claude" \\
  -v "\$(cd "\$dir" && pwd):/work" \\
  -w /work \\
  $image "\${3:-bash}" -l
CONF
vm_ssh sh -c 'chmod +x ~/.local/bin/agent-run'
ok "wrote ~/.local/bin/agent-run in the VM"

vm_ssh sh -c 'grep -q "\.local/bin" ~/.profile 2>/dev/null' >/dev/null 2>&1 \
  || vm_ssh sh -c 'printf "\nPATH=\"\$HOME/.local/bin:\$PATH\"\n" >> ~/.profile'

set_server_var VM_AGENT_IMAGE "$image"

note "run a project with:  agent-run ~/work/<repo> [trusted|untrusted]"
note "the first trusted run needs a sign-in: agent-run ~/work/<repo> trusted claude"
