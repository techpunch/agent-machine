#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

home=$(_admin_home)
name="${SBX_SANDBOX:-agents}"

if [ -x "$home/.local/bin/agents" ]; then
  ok "agents helper present and executable"
  /usr/bin/grep -q "exec -it \"$name\" tmux" "$home/.local/bin/agents" \
    && ok "agents helper attaches to the grid inside sandbox '$name'" \
    || miss "agents helper does not point at sandbox '$name' — re-run apply"
else
  miss "no ~/.local/bin/agents helper"
fi

grep -q '\.local/bin' "$home/.zshenv" 2>/dev/null \
  && ok "~/.local/bin on PATH for 'ssh <server> agents', via ~/.zshenv" \
  || miss "~/.local/bin not on PATH — the agents helper won't be found"

# tmux and its config come from the kit when the sandbox is created, and reading them means
# `sbx exec`, which starts a stopped sandbox. A verify must not change the machine, so they are not
# re-read here; have-shared-sandbox's apply checks tmux is there after creating it.

verify_result
