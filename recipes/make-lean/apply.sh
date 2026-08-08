#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"
need_root
need_var ADMIN_USER

SPOTLIGHT_VOLUMES="/ /System/Volumes/Data"

# mdutil exits 0 even for a path it rejects, so the output is the only signal worth reading.
spotlight_state() {
  /usr/bin/mdutil -s "$1" 2>/dev/null | /usr/bin/grep -o 'Indexing [a-z]*' | /usr/bin/head -1
}

# Everything here switches off a setting somebody may later want back, and the ledger cannot say
# which — it carries one row per recipe. So each change goes to the run log with the value it
# replaced, and `cookbook log` becomes the answer to "what did the cookbook turn off on this box,
# and what was it before". Only on an actual change: re-applying an already-lean server should
# leave the log alone rather than filling it with lines saying nothing happened.
tuned() {
  log_event tuned "$1" "$2"
  ok "$1: $2"
}

for vol in $SPOTLIGHT_VOLUMES; do
  case "$(spotlight_state "$vol")" in
    "Indexing disabled")
      ok "spotlight: already off on $vol" ;;
    "Indexing enabled")
      /usr/bin/mdutil -i off "$vol" >/dev/null 2>&1 || true
      if [ "$(spotlight_state "$vol")" = "Indexing disabled" ]; then
        tuned "spotlight $vol" "indexing off (was on)"
      else
        die "mdutil would not turn indexing off on $vol"
      fi ;;
    *)
      skip "spotlight: $vol not a volume mdutil reports on" ;;
  esac
done

# The desktop settings belong to the admin user's session, not to root's. Going through `sudo -u`
# puts the write in their preferences and through the cfprefsd their logged-in session is actually
# reading, which a root-owned write would not reach.
admin_defaults() { /usr/bin/sudo -n -u "$ADMIN_USER" /usr/bin/defaults "$@"; }

idle=$(admin_defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null) || idle=""
if [ "$idle" = "0" ]; then
  ok "screen saver: already disabled for $ADMIN_USER"
else
  admin_defaults -currentHost write com.apple.screensaver idleTime -int 0
  tuned "screen saver" "idleTime 0 for $ADMIN_USER (was ${idle:-unset, system default})"
fi

widgets=$(admin_defaults read com.apple.WindowManager StandardHideWidgets 2>/dev/null) || widgets=""
if [ "$widgets" = "1" ]; then
  ok "desktop widgets: already hidden for $ADMIN_USER"
else
  admin_defaults write com.apple.WindowManager StandardHideWidgets -bool true
  tuned "desktop widgets" "hidden for $ADMIN_USER (was ${widgets:-unset, so shown})"
  # The Dock hosts the desktop widget layer and reads the setting at start. Without this the
  # change is real but invisible until the next login, which reads as the recipe not working.
  /usr/bin/sudo -n -u "$ADMIN_USER" /usr/bin/killall Dock 2>/dev/null \
    || note "no Dock running to restart; the setting applies at next login"
fi
