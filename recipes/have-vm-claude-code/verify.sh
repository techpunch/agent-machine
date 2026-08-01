#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

colima_bin >/dev/null || { miss "colima not installed"; verify_result; }
if ! vm_ssh true >/dev/null 2>&1; then
  miss "the agent VM is not reachable"
  verify_result
fi

ver=$(vm_ssh sh -c '. ~/.bashrc 2>/dev/null; claude --version' 2>/dev/null | /usr/bin/tr -d '\r')
if [ -n "$ver" ]; then
  ok "claude in the VM: $ver"
else
  miss "claude is not installed in the VM"
  verify_result
fi

vm_ssh sh -c 'command -v git >/dev/null' >/dev/null 2>&1 \
  && ok "git available in the VM" || miss "git not installed in the VM"

# Presence of the credential file, not its contents — never read a token to check it exists.
if vm_ssh sh -c 'ls ~/.claude/.credentials.json >/dev/null 2>&1 || ls ~/.claude/credentials.json >/dev/null 2>&1'; then
  ok "signed in (credential present in ~/.claude)"
else
  miss "not signed in yet — apply will print the SSH-tunnel runbook"
fi

verify_result
