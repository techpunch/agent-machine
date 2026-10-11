#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

sbx=$(sbx_bin) || { miss "sbx not installed"; verify_result; }

if out=$(with_timeout 30 "$sbx" secret ls -g --service github 2>/dev/null); then
  if printf '%s\n' "$out" | /usr/bin/tail -n +2 | /usr/bin/grep -qw github; then
    ok "GitHub token stored in sbx (global, injected by the proxy)"
  else
    miss "no GitHub token stored in sbx — agents cannot push"
  fi
else
  blocked "could not list sbx secrets; whether agents can push is unverified"
fi

verify_result
