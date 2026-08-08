#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# Only the volumes holding anything an agent touches. `mdutil -s -a` also lists volumes macOS will
# not let anyone change, and counting those as failures would leave this recipe permanently red —
# which is a broken recipe, not a true one.
SPOTLIGHT_VOLUMES="/ /System/Volumes/Data"

# mdutil exits 0 even for a path it rejects outright, so the exit code says nothing and the output
# is the only signal. A volume it will not answer for is n/a, not a miss.
spotlight_state() {
  /usr/bin/mdutil -s "$1" 2>/dev/null | /usr/bin/grep -o 'Indexing [a-z]*' | /usr/bin/head -1
}

for vol in $SPOTLIGHT_VOLUMES; do
  case "$(spotlight_state "$vol")" in
    "Indexing disabled") ok "spotlight: indexing off on $vol" ;;
    "Indexing enabled")  miss "spotlight: still indexing $vol" ;;
    *)                   skip "spotlight: $vol not a volume mdutil reports on" ;;
  esac
done

# The desktop settings belong to the admin user, not to root. Never plain `sudo` from a verify: a
# verify that can raise a password prompt is one that hangs a headless server forever, so this drops
# privileges with -n (root needs no password to do it) or reads directly when it is already them.
need_var ADMIN_USER
admin_defaults() {
  if is_root; then
    /usr/bin/sudo -n -u "$ADMIN_USER" /usr/bin/defaults "$@" 2>/dev/null
  elif [ "$(id -un)" = "$ADMIN_USER" ]; then
    /usr/bin/defaults "$@" 2>/dev/null
  else
    return 1
  fi
}

if ! is_root && [ "$(id -un)" != "$ADMIN_USER" ]; then
  blocked "cannot read $ADMIN_USER's preferences as $(id -un) — re-run as $ADMIN_USER or with sudo"
else
  # Absent means the system default applies, which is not zero — so unset is a miss, not an n/a.
  idle=$(admin_defaults -currentHost read com.apple.screensaver idleTime) || idle=""
  case "$idle" in
    0)  ok "screen saver: disabled for $ADMIN_USER" ;;
    "") miss "screen saver: idleTime unset for $ADMIN_USER, so the system default still applies" ;;
    *)  miss "screen saver: starts after ${idle}s of idle for $ADMIN_USER" ;;
  esac

  widgets=$(admin_defaults read com.apple.WindowManager StandardHideWidgets) || widgets=""
  case "$widgets" in
    1)  ok "desktop widgets: hidden for $ADMIN_USER" ;;
    "") miss "desktop widgets: StandardHideWidgets unset for $ADMIN_USER, so widgets are on" ;;
    *)  miss "desktop widgets: StandardHideWidgets=$widgets for $ADMIN_USER, want 1" ;;
  esac
fi

verify_result
