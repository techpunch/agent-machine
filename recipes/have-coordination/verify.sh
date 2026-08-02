#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

home=$(_admin_home)
session="${TMUX_SESSION:-agents}"

tmux=""
for c in /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux; do
  [ -x "$c" ] && { tmux="$c"; break; }
done
if [ -n "$tmux" ]; then
  ok "tmux at $tmux ($("$tmux" -V 2>/dev/null))"
else
  miss "tmux not installed"
  verify_result
fi

[ -f "$home/.tmux.conf" ] && ok "~/.tmux.conf present" \
                          || miss "no ~/.tmux.conf"

[ -x "$home/.local/bin/agents" ] && ok "agents helper present and executable" \
                                 || miss "no ~/.local/bin/agents helper"

grep -q '\.local/bin' "$home/.zprofile" 2>/dev/null \
  && ok "~/.local/bin on PATH for a login shell" \
  || miss "~/.local/bin not on PATH — the agents helper won't be found"

# A grid that is not currently running is not a failure: tmux sessions live with the login
# session, and a fresh boot has none until you attach. Report it rather than failing on it.
if "$tmux" has-session -t "$session" 2>/dev/null; then
  panes=$("$tmux" list-panes -s -t "$session" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
  ok "session '$session' is running ($panes pane(s))"
else
  note "session '$session' not running — 'agents' will create it"
fi

verify_result
