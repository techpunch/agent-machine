#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"
need_root
need_var ADMIN_USER

policy="${FILEVAULT_POLICY:-off}"
set_server_var FILEVAULT_POLICY "$policy"

if [ "$policy" = "on" ]; then
  gate "FILEVAULT_POLICY=on, which rules out auto-login — the pre-boot unlock screen comes up
before anything this recipe could configure. Nothing was changed.
Either set FILEVAULT_POLICY=off in $SERVER_ENV and turn FileVault off, or accept that this server
needs a human on every reboot. See recipes/make-auto-login/recipe.md."
fi

if /usr/bin/fdesetup status 2>/dev/null | grep -q "FileVault is On"; then
  gate "FileVault is on and FILEVAULT_POLICY=off. Turn it off before enabling auto-login:
  sudo fdesetup disable
Decryption runs in the background and can take a while on a large disk; re-run this recipe once
'fdesetup status' reports off."
fi

if [ -z "${ADMIN_PASSWORD:-}" ]; then
  gate "Auto-login needs the password for '$ADMIN_USER' to write /etc/kcpassword.

This one is your actual login password, so hand it to sysadminctl directly rather than
through this recipe. Run it yourself — the trailing '-' means it prompts, so the password
never reaches argv, ps, your shell history, or a Claude transcript:

  sudo sysadminctl -autologin set -userName $ADMIN_USER -password -

Then re-run this recipe to verify it took:
  ./bin/cookbook apply make-auto-login

Two alternatives, both worse: set it in System Settings > Users & Groups > Automatically
log in as > $ADMIN_USER; or, for an unattended build, pass ADMIN_PASSWORD in the
environment and accept that it is visible in ps while the command runs."
fi

# Reached only when ADMIN_PASSWORD was supplied deliberately for an unattended run.
note "using ADMIN_PASSWORD from the environment — visible in ps for the life of this command"
/usr/sbin/sysadminctl -autologin set -userName "$ADMIN_USER" -password "$ADMIN_PASSWORD" 2>&1 \
  | grep -v '^$' || true
unset ADMIN_PASSWORD

if /usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null \
   | grep -qx "$ADMIN_USER"; then
  ok "auto-login set for $ADMIN_USER"
else
  die "sysadminctl did not set auto-login — check the password and try again"
fi
