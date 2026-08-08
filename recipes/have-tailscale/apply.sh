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
  #
  # RunAtLoad covers a reboot; StartInterval covers the rest. On macOS the app owns the
  # network extension that carries the tunnel, so if Tailscale quits or crashes the server
  # leaves the tailnet — and on a headless box that is a lockout until somebody logs in
  # physically. The tick is guarded by pgrep rather than calling `open` unconditionally:
  # `open -ga` leaves a running app's process and tunnel alone — same pid, same extension —
  # but it still raises the app's window, so an unguarded check puts Tailscale on the screen
  # once a minute forever. Guarded, a healthy tick runs pgrep and stops. The interval is also
  # the worst-case outage after a crash, which is why it is this short.
  #
  # The guard lives in a named script rather than inline after `sh -c`, because macOS labels a
  # background item by the program it runs. Inline, System Settings lists it as "sh — Item from
  # unidentified developer", which is exactly what a careful person switches off — taking the
  # crash recovery with it, discovered after the next reboot with no monitor attached. Named,
  # the entry says what it is and there is a file to go and read.
  agents="$HOME/Library/LaunchAgents"
  plist="$agents/$TS_AGENT_LABEL.plist"
  watchdog="$STATE_DIR/tailscale-watchdog.sh"
  mkdir -p "$agents" "$STATE_DIR"

  cat >"$watchdog" <<'WATCHDOG'
#!/bin/sh
# Started every minute by com.agent-machine.tailscale-relaunch, and by the cookbook recipe
# have-tailscale. On macOS the Tailscale app owns the network extension carrying the tunnel,
# so if the app dies the server leaves the tailnet — headless, that is a lockout until
# somebody logs in at the keyboard. Does nothing at all while the app is alive.
/usr/bin/pgrep -qf Tailscale.app && exit 0
/usr/bin/open -ga /Applications/Tailscale.app
WATCHDOG
  chmod 755 "$watchdog"
  _own_state_dir
  ok "wrote watchdog $watchdog"

  cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$TS_AGENT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$watchdog</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>60</integer>
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
