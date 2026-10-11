#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# The helper belongs to the admin user's session, not root's.
if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi
is_root && die "run this recipe as the admin user, not root"

sbx=$(sbx_bin) || die "sbx not installed — run have-agent-sandbox first"
name="${SBX_SANDBOX:-agents}"
session="${TMUX_SESSION:-agents}"

# tmux and its config are in the shared sandbox already — the kit installs them when it is created —
# so what is left is the way in. One entry point on the Mac, so attaching and creating are the same command and you cannot end up
# with a second grid you forgot about. `sbx exec` starts the sandbox if it is stopped, which is what
# brings it back after a reboot.
mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/agents" <<CONF
#!/bin/sh
# Managed by the agent-machine cookbook (recipes/have-coordination).
# Attach to the agent grid inside sandbox '$name', creating it if it is not running.
exec "$sbx" exec -it "$name" tmux new-session -A -s "$session" "\$@"
CONF
chmod +x "$HOME/.local/bin/agents"
ok "wrote $HOME/.local/bin/agents"

# ~/.zshenv, not ~/.zprofile: `ssh <server> -t agents` runs the command with `zsh -c`, which is not a
# login shell and reads only ~/.zshenv. In ~/.zprofile the helper is "command not found" over SSH.
grep -q '\.local/bin' "$HOME/.zshenv" 2>/dev/null \
  || printf '\nPATH="$HOME/.local/bin:$PATH"\n' >>"$HOME/.zshenv"

set_server_var TMUX_SESSION "$session"

note "attach with:  ssh <server> -t agents"
note "then in a pane:  git clone https://github.com/<you>/<project> ~/<project> && cd ~/<project> && claude"
