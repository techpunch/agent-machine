#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi

colima_bin >/dev/null || die "colima not installed — run have-agent-vm first"
vm_ssh true >/dev/null 2>&1 || die "the agent VM is not reachable — run have-agent-vm first"

vm_ssh sh -c 'command -v git >/dev/null' >/dev/null 2>&1 || {
  note "installing git and curl in the VM"
  vm_ssh sudo sh -c 'apt-get update -qq && apt-get install -y -qq git curl ca-certificates' \
    || die "could not install base tools in the VM"
}

if vm_ssh sh -c '. ~/.bashrc 2>/dev/null; command -v claude >/dev/null' >/dev/null 2>&1; then
  ok "claude already installed in the VM"
else
  note "installing Claude Code in the VM (native installer, no Node needed)"
  vm_ssh sh -c 'curl -fsSL https://claude.ai/install.sh | bash' \
    || die "the Claude Code installer failed inside the VM"
fi

ver=$(vm_ssh sh -c '. ~/.bashrc 2>/dev/null; claude --version' 2>/dev/null | /usr/bin/tr -d '\r')
[ -n "$ver" ] || die "claude installed but is not on PATH inside the VM"
ok "claude in the VM: $ver"

if vm_ssh sh -c 'ls ~/.claude/.credentials.json >/dev/null 2>&1 || ls ~/.claude/credentials.json >/dev/null 2>&1'; then
  ok "already signed in"
  exit 0
fi

profile="${VM_PROFILE:-agent}"
gate "Claude Code in the VM needs signing in, and that needs your browser.

In one terminal, get a shell in the VM and start the login:
  colima ssh --profile $profile
  claude /login
It prints a URL containing a localhost port. Note the port.

In a second terminal on your laptop, forward that port:
  ssh -L <port>:localhost:<port> ${ADMIN_USER:-<admin>}@${SERVER_SLUG:-<server>}

Then open the printed http://localhost:<port>/... URL in your laptop browser and finish
signing in. The token is delivered back into the VM.

If the page does not load, Lima did not forward the guest port. Use a second hop instead,
from your laptop, while the login is waiting:
  ssh ${ADMIN_USER:-<admin>}@${SERVER_SLUG:-<server>} -t \\
    colima ssh --profile $profile -- -L <port>:localhost:<port>

The sign-in persists across VM and host reboots. Re-run this recipe afterwards to confirm.

Before you put a project in this VM, read docs/secrets-and-egress.md — the VM has full
outbound internet, so anything you place in it can leave it."
