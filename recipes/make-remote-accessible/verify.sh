#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

rl=$(/usr/sbin/systemsetup -getremotelogin 2>&1 || true)
if systemsetup_needs_root "$rl"; then
  blocked "cannot read remote login state without root — re-run this verify with sudo"
else
  case "$rl" in
    *On*)  ok "remote login (SSH): on" ;;
    *Off*) miss "remote login (SSH): off" ;;
    *)     blocked "cannot read remote login state — the calling process likely lacks Full Disk Access ($rl)" ;;
  esac
fi

# Remote Management writes this plist; the launchd job is the live proof.
if /bin/launchctl print system/com.apple.screensharing >/dev/null 2>&1; then
  ok "screen sharing service loaded"
elif [ -f /Library/Preferences/com.apple.RemoteManagement.plist ]; then
  ok "remote management configured (screensharing job not separately loaded)"
else
  miss "neither screen sharing nor remote management is enabled"
fi

fw=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || true)
case "$fw" in
  *enabled*) ok "application firewall: enabled" ;;
  *)         miss "application firewall: disabled" ;;
esac

verify_result
