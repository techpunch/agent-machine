#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

if cli=$(ts_cli); then
  ok "tailscale CLI at $cli"
else
  miss "no tailscale CLI found"
fi

if [ -d /Applications/Tailscale.app ]; then
  ok "Tailscale.app installed"

  # A LaunchAgent, not a login item. Login items can only be read through System Events,
  # which triggers a TCC prompt that blocks forever on a server with nobody at the screen.
  plist="$(_admin_home)/Library/LaunchAgents/$TS_AGENT_LABEL.plist"
  watchdog="$STATE_DIR/tailscale-watchdog.sh"
  if [ ! -f "$plist" ]; then
    miss "no relaunch agent at $plist — Tailscale won't come back after a reboot"
  # Checking the contents, not just that the file exists: a server set up before the periodic
  # check was added has a plist that passes a bare -f test while recovering from nothing but a
  # reboot. A verify that cannot see the difference leaves those servers on the old agent for
  # good, because apply never runs again.
  elif ! /usr/bin/plutil -extract StartInterval raw -o - "$plist" >/dev/null 2>&1; then
    miss "relaunch agent at $plist has no StartInterval — it recovers a reboot but not a crash"
  # An unguarded periodic open raises the Tailscale window every tick. That is not a
  # cosmetic complaint on a machine somebody also uses at the screen, and it is the kind of
  # thing people fix by deleting the agent, which costs them the crash recovery too.
  elif ! /usr/bin/grep -q tailscale-watchdog.sh "$plist"; then
    miss "relaunch agent at $plist opens Tailscale every tick instead of only when it has died"
  # An agent pointing at a script that is missing or not executable fails silently every
  # minute: launchd records the error and nothing else says a word.
  elif [ ! -x "$watchdog" ]; then
    miss "watchdog $watchdog is missing or not executable — the agent runs nothing"
  else
    ok "relaunch agent at $plist, running $watchdog"
  fi

  /usr/bin/pgrep -qf 'Tailscale.app' && ok "Tailscale.app is running" \
    || miss "Tailscale.app is not running"
else
  # A formula install is a legitimate way to already have Tailscale, but it comes with no
  # LaunchAgent of ours, so nothing here guarantees it returns after a reboot. Reporting
  # that as n/a would pass a server that silently drops off the tailnet the first time it
  # restarts — the exact failure this recipe exists to prevent. Look for the formula's own
  # service instead, and fail if there is no persistence at all.
  skip "no Tailscale.app — this is a formula install, not the cask"
  if /bin/ls "$(_admin_home)/Library/LaunchAgents"/*tailscale* >/dev/null 2>&1 \
     || /bin/ls /Library/LaunchDaemons/*tailscale* >/dev/null 2>&1; then
    ok "a tailscale launchd service is installed (formula persistence)"
  else
    miss "formula install with no launchd service — Tailscale won't come back after a reboot. Either 'brew services start tailscale', or remove the formula and re-apply to get the cask."
  fi

  /usr/bin/pgrep -qf 'tailscaled' && ok "tailscaled is running" \
    || miss "tailscaled is not running"
fi

verify_result
