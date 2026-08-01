#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# Auto-login actually happening is the thing that matters, and the console owner is the
# only honest proof: at the login window it is _windowserver or root, never a real user.
console=$(/usr/bin/stat -f%Su /dev/console 2>/dev/null || true)
if [ -z "${ADMIN_USER:-}" ]; then
  miss "ADMIN_USER not set — run have-server-identity first"
elif [ "$console" = "$ADMIN_USER" ]; then
  ok "console owned by $console — a GUI session is logged in"
else
  miss "console owned by '${console:-unknown}', expected $ADMIN_USER — the server is at the login window, or logged in as the wrong user"
fi

res=$(/usr/sbin/system_profiler SPDisplaysDataType 2>/dev/null | /usr/bin/awk -F': ' '/Resolution/ {print $2; exit}')
if [ -z "$res" ]; then
  miss "no display attached — Screen Sharing will be unusable; the headless dongle is missing or in the wrong port"
else
  ok "display resolution: $res"
fi

if [ -n "${REBOOT_SURVIVED_AT:-}" ]; then
  ok "reboot survival confirmed $REBOOT_SURVIVED_AT"
else
  miss "reboot survival not confirmed yet"
fi

if [ -n "${HEADLESS_AT:-}" ]; then
  ok "went headless $HEADLESS_AT"
else
  miss "peripherals not confirmed removed"
fi

verify_result
