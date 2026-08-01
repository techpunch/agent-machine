#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# brew must not run as root, and the LaunchAgent belongs to the admin user's GUI session.
if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi
is_root && die "run this recipe as the admin user, not root"

brew=$(brew_bin) || die "Homebrew not installed — run have-homebrew first"

if ! ts_cli >/dev/null; then
  "$brew" install --cask tailscale
fi
cli=$(ts_cli) || die "Tailscale install finished but no CLI on disk"
ok "tailscale CLI at $cli"

if [ -d /Applications/Tailscale.app ]; then
  # A LaunchAgent rather than a login item: it is a file we can write and read back,
  # where login items can only be touched through System Events and its TCC prompt.
  agents="$HOME/Library/LaunchAgents"
  plist="$agents/$TS_AGENT_LABEL.plist"
  mkdir -p "$agents"
  cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$TS_AGENT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-ga</string>
    <string>/Applications/Tailscale.app</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
  ok "wrote relaunch agent $plist"

  uid=$(id -u)
  /bin/launchctl bootout "gui/$uid/$TS_AGENT_LABEL" 2>/dev/null || true
  /bin/launchctl bootstrap "gui/$uid" "$plist" 2>/dev/null \
    || note "could not bootstrap the agent in this session; it will load at next login"
fi

/usr/bin/pgrep -qf 'Tailscale.app' && ok "Tailscale.app is running"
