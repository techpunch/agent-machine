#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

colima_bin >/dev/null || { miss "colima not installed"; verify_result; }
if ! vm_ssh true >/dev/null 2>&1; then
  miss "the agent VM is not reachable"
  verify_result
fi

session="${VM_TMUX_SESSION:-agents}"

ver=$(vm_ssh sh -c 'tmux -V' 2>/dev/null | /usr/bin/tr -d '\r')
if [ -n "$ver" ]; then
  ok "tmux in the VM: $ver"
else
  miss "tmux is not installed in the VM"
  verify_result
fi

vm_ssh sh -c 'test -f ~/.tmux.conf' >/dev/null 2>&1 \
  && ok "~/.tmux.conf present" \
  || miss "no ~/.tmux.conf in the VM"

vm_ssh sh -c 'test -x ~/.local/bin/agents' >/dev/null 2>&1 \
  && ok "agents helper present and executable" \
  || miss "no ~/.local/bin/agents helper in the VM"

vm_ssh sh -c 'grep -q "\.local/bin" ~/.profile' >/dev/null 2>&1 \
  && ok "~/.local/bin on PATH for a login shell" \
  || miss "~/.local/bin not on PATH — the agents helper won't be found"

# A grid that is not currently running is not a failure: tmux sessions live with the VM,
# and a fresh boot has none until you attach. Report it rather than failing on it.
if vm_ssh sh -c "tmux has-session -t '$session'" >/dev/null 2>&1; then
  panes=$(vm_ssh sh -c "tmux list-panes -s -t '$session' | wc -l" 2>/dev/null | /usr/bin/tr -d '\r ')
  ok "session '$session' is running ($panes pane(s))"
else
  note "session '$session' not running — 'agents' will create it"
fi

verify_result
