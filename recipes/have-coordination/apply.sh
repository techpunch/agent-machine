#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# The grid belongs to the admin user's session, not root's.
if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi
is_root && die "run this recipe as the admin user, not root"

brew=$(brew_bin) || die "Homebrew not installed — run have-homebrew first"

session="${TMUX_SESSION:-agents}"

if /usr/bin/which tmux >/dev/null 2>&1 || [ -x /opt/homebrew/bin/tmux ] || [ -x /usr/local/bin/tmux ]; then
  ok "tmux already installed"
else
  note "installing tmux"
  "$brew" install tmux || die "could not install tmux"
fi

# Defaults chosen for watching agents rather than for editing: a long scrollback because an
# agent can outrun the default 2000 lines in one task, and mouse mode so scrolling a pane
# over SSH does not mean learning copy-mode first.
#
# The terminal settings are not cosmetic. An SSH session that leaves TERM as xterm makes Claude
# Code's renderer degrade: box-drawing falls back to ASCII, colour drops to 8, and slash-command
# autocomplete renders as plain text above the prompt instead of inline. Since SSH is the only way
# anyone reaches this grid, that is the default experience unless we set it here.
cat >"$HOME/.tmux.conf" <<'CONF'
# Managed by the agent-machine cookbook (recipes/have-coordination). Edits are overwritten.
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",*256col*:Tc"
set -g history-limit 100000
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g status-left "#[bold] #S "
set -g status-right " %H:%M "
setw -g automatic-rename on
CONF
ok "wrote $HOME/.tmux.conf"

# One entry point, so attaching and creating are the same command and you cannot end up with
# a second detached session you forgot about.
mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/agents" <<CONF
#!/bin/sh
# Managed by the agent-machine cookbook (recipes/have-coordination).
# Attach to the agent grid, creating it if it is not running.
exec tmux new-session -A -s "$session" "\$@"
CONF
chmod +x "$HOME/.local/bin/agents"
ok "wrote $HOME/.local/bin/agents"

grep -q '\.local/bin' "$HOME/.zprofile" 2>/dev/null \
  || printf '\nPATH="$HOME/.local/bin:$PATH"\n' >>"$HOME/.zprofile"

set_server_var TMUX_SESSION "$session"

note "attach with:  ssh <server> -t agents"
note "then in a pane:  sbx run --clone claude"
