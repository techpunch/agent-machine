#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

if /usr/bin/xcode-select -p >/dev/null 2>&1; then
  ok "developer dir: $(/usr/bin/xcode-select -p)"
else
  miss "no developer directory selected"
fi

for tool in git clang make; do
  /usr/bin/xcrun --find "$tool" >/dev/null 2>&1 && ok "$tool available" || miss "$tool not available"
done

verify_result
