#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"
need_var ADMIN_USER

boot_epoch=$(/usr/sbin/sysctl -n kern.boottime | /usr/bin/sed -n 's/.*sec = \([0-9]*\).*/\1/p')

# Pass one: the server has to come back from a reboot with nobody touching it before any
# cable comes out. Compare boot time against when we asked, so a stale marker can't pass.
if [ -z "${REBOOT_TEST_ASKED_AT:-}" ] || [ "$boot_epoch" -lt "${REBOOT_TEST_ASKED_AT:-0}" ]; then
  set_server_var REBOOT_TEST_ASKED_AT "$(date +%s)"
  gate "Reboot survival test. Nothing has been unplugged.
Reboot the server now:
  sudo reboot
Wait for it to come back, reconnect over Tailscale, and re-run:
  ./bin/cookbook apply headless
It will check that auto-login happened, Tailscale reconnected, and SSH still answers."
fi

console=$(/usr/bin/stat -f%Su /dev/console 2>/dev/null || true)
[ "$console" = "$ADMIN_USER" ] \
  || die "the server rebooted but the console is owned by '${console:-unknown}' — auto-login did not happen. Re-run make-auto-login before going headless."
ok "auto-login survived the reboot (console owned by $console)"

cli=$(ts_cli) || die "tailscale is gone after the reboot"
"$cli" status --json 2>/dev/null | grep -q '"BackendState" *: *"Running"' \
  || die "Tailscale did not reconnect after the reboot — check that it is a login item (have-tailscale)"
ok "Tailscale reconnected as $("$cli" ip -4 2>/dev/null | head -1)"

/usr/sbin/systemsetup -getremotelogin 2>/dev/null | grep -q On \
  || die "SSH is not enabled after the reboot — re-run make-remote-accessible"
ok "SSH still enabled"

[ -n "${REBOOT_SURVIVED_AT:-}" ] || set_server_var REBOOT_SURVIVED_AT "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Pass two: the physical work. Nothing here is scriptable.
if [ -z "${HEADLESS_CONFIRMED:-}" ]; then
  gate "The server is verified reachable and self-recovering. Now the physical part:
  1. Unplug the monitor.
  2. Plug the headless display dongle into the same HDMI port.
  3. Disconnect the USB keyboard and mouse.
  4. Reconnect over Screen Sharing and confirm a full-resolution desktop through the dongle.
     From another Mac on the tailnet that is:  open vnc://${SERVER_SLUG:-<slug>}
Then re-run with:
  HEADLESS_CONFIRMED=1 ./bin/cookbook apply headless"
fi

res=$(/usr/sbin/system_profiler SPDisplaysDataType 2>/dev/null | /usr/bin/awk -F': ' '/Resolution/ {print $2; exit}')
[ -n "$res" ] || die "no display detected — the dongle is not seated, or it is in a different port than the monitor was"
ok "display through the dongle: $res"

set_server_var HEADLESS_AT "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ok "server is headless"
