#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# A key the hardware doesn't expose is n/a, not a failure — Apple Silicon has no womp
# or autorestart, and going red on that would make the recipe permanently unsatisfiable.
check_key() {
  local key="$1" want="$2" got
  got=$(pmset_val "$key")
  if [ -z "$got" ]; then
    skip "$key not supported on this hardware"
  elif [ "$got" = "$want" ]; then
    ok "$key=$got"
  else
    miss "$key=$got, want $want"
  fi
}

check_key sleep 0
check_key disksleep 0
check_key displaysleep 0
check_key womp 1
check_key autorestart 1

rpf=$(/usr/sbin/systemsetup -getrestartpowerfailure 2>&1 || true)
if systemsetup_needs_root "$rpf"; then
  blocked "cannot read restart-on-power-failure without root — re-run this verify with sudo"
else
  case "$rpf" in
    *On*)                ok "restart on power failure: on" ;;
    *not\ supported*|"") skip "restart-on-power-failure not supported on this hardware" ;;
    *)                   miss "restart on power failure: ${rpf#*: }" ;;
  esac
fi

verify_result
