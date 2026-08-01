#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# The multiplexer belongs to the VM's agent user, and colima is the admin user's.
if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi

colima_bin >/dev/null || die "colima not installed — run have-agent-vm first"
vm_ssh true >/dev/null 2>&1 || die "the agent VM is not reachable — run have-agent-vm first"

session="${VM_TMUX_SESSION:-agents}"

if vm_ssh sh -c 'command -v tmux >/dev/null' >/dev/null 2>&1; then
  ok "tmux already installed in the VM"
else
  note "installing tmux in the VM"
  vm_ssh sudo sh -c 'apt-get update -qq && apt-get install -y -qq tmux' \
    || die "could not install tmux in the VM"
fi

# Defaults chosen for watching agents rather than for editing: a long scrollback because
# an agent can outrun the default 2000 lines in one task, and mouse mode so scrolling a
# pane over SSH does not mean learning copy-mode first.
vm_ssh sh -c 'cat > ~/.tmux.conf' <<'CONF'
# Managed by the agent-machine cookbook (recipes/have-coordination). Edits are overwritten.
set -g history-limit 100000
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g status-left "#[bold] #S "
set -g status-right " %H:%M "
setw -g automatic-rename on
CONF
ok "wrote ~/.tmux.conf in the VM"

# One entry point, so attaching and creating are the same command and you cannot end up
# with a second detached session you forgot about.
vm_ssh sh -c 'mkdir -p ~/.local/bin && cat > ~/.local/bin/agents' <<CONF
#!/bin/sh
# Managed by the agent-machine cookbook (recipes/have-coordination).
# Attach to the agent grid, creating it if it is not running.
exec tmux new-session -A -s "$session" "\$@"
CONF
vm_ssh sh -c 'chmod +x ~/.local/bin/agents'
ok "wrote ~/.local/bin/agents in the VM"

# Debian puts ~/.local/bin on PATH only if it exists at login, which it did not until now.
vm_ssh sh -c 'grep -q "\.local/bin" ~/.profile 2>/dev/null' >/dev/null 2>&1 \
  || vm_ssh sh -c 'printf "\nPATH=\"\$HOME/.local/bin:\$PATH\"\n" >> ~/.profile'

set_server_var VM_TMUX_SESSION "$session"

note "attach with:  colima ssh --profile ${VM_PROFILE:-agent} -- -t agents"
