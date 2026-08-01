#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

policy="${FILEVAULT_POLICY:-off}"
fv=$(/usr/bin/fdesetup status 2>/dev/null || true)

case "$policy" in
  on)
    case "$fv" in
      *"FileVault is On"*) ok "FileVault on, as FILEVAULT_POLICY=on requires" ;;
      *) miss "FILEVAULT_POLICY=on but FileVault is off" ;;
    esac
    blocked "FILEVAULT_POLICY=on rules out auto-login — reboots need a human. See recipe.md."
    verify_result
    ;;
  off)
    case "$fv" in
      *"FileVault is Off"*) ok "FileVault off, as auto-login requires" ;;
      *) miss "FileVault is on — auto-login cannot work; set FILEVAULT_POLICY or turn FileVault off" ;;
    esac
    ;;
  *) die "FILEVAULT_POLICY must be 'on' or 'off', got '$policy'" ;;
esac

who=$(/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true)
if [ -z "$who" ]; then
  miss "no autoLoginUser configured"
elif [ "$who" = "${ADMIN_USER:-}" ]; then
  ok "autoLoginUser=$who"
else
  miss "autoLoginUser=$who, expected ${ADMIN_USER:-<ADMIN_USER unset>}"
fi

[ -f /etc/kcpassword ] && ok "/etc/kcpassword present" \
  || miss "/etc/kcpassword missing — macOS will still stop at the login window"

verify_result
