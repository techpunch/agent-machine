#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

if /usr/bin/xcode-select -p >/dev/null 2>&1 && /usr/bin/xcrun --find git >/dev/null 2>&1; then
  ok "command line tools already installed"
  exit 0
fi

note "triggering the command line tools installer"
/usr/bin/xcode-select --install 2>/dev/null || true

# The installer is a GUI dialog and xcode-select returns immediately, so poll.
for _ in $(seq 1 60); do
  if /usr/bin/xcrun --find git >/dev/null 2>&1; then
    ok "command line tools installed"
    exit 0
  fi
  sleep 10
done

gate "The Command Line Tools installer is waiting for someone to click Install.
Connect over Screen Sharing, approve the dialog, let it finish, then re-run this recipe.
Headless alternative, if you have a session on the server:
  softwareupdate --list | grep 'Command Line Tools'
  softwareupdate --install '<the exact label it printed>'"
