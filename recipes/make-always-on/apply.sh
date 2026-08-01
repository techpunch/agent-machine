#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"
need_root

# Set each key on its own so one unsupported key doesn't abort the rest of the line.
for kv in "sleep 0" "disksleep 0" "displaysleep 0" "womp 1" "autorestart 1"; do
  # shellcheck disable=SC2086
  if /usr/bin/pmset -a $kv 2>/dev/null; then
    ok "pmset -a $kv"
  else
    skip "pmset -a $kv not supported on this hardware"
  fi
done

out=$(/usr/sbin/systemsetup -setrestartpowerfailure on 2>&1 || true)
case "$out" in
  *not\ supported*) skip "restart-on-power-failure not supported on this hardware" ;;
  *)                ok "restart on power failure: on" ;;
esac
