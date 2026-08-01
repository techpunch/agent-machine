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
  [ -f "$plist" ] && ok "relaunch agent at $plist" \
    || miss "no relaunch agent at $plist — Tailscale won't come back after a reboot"

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
