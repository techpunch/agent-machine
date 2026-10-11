#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

sbx=$(sbx_bin) || { miss "sbx not installed"; verify_result; }
name="${SBX_SANDBOX:-agents}"

if out=$(with_timeout 30 "$sbx" ls -q 2>/dev/null); then
  if printf '%s\n' "$out" | /usr/bin/grep -qx "$name"; then
    ok "sandbox '$name' exists"
  else
    miss "no sandbox named '$name' — apply creates it"
  fi
else
  miss "could not list sandboxes — signed out, or the daemon is unhappy; 'sbx diagnose' says which"
fi

[ -n "${SBX_SANDBOX:-}" ] && ok "sandbox name recorded in server.env" \
  || miss "SBX_SANDBOX not recorded in server.env — run apply"

# What is inside — tmux, Codex, the bypass-mode aliases — comes from the kit at create, and detached
# mode from apply. Reading any of it means `sbx exec`, which starts a stopped sandbox, and a verify
# must not change the machine, so none of it is re-read here.

verify_result
