#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

cli=$(ts_cli) || { miss "tailscale not installed"; verify_result; }

prefs=$("$cli" debug prefs 2>/dev/null || true)
if printf '%s' "$prefs" | grep -q '"AdvertiseRoutes"'; then
  if printf '%s' "$prefs" | grep -qE '0\.0\.0\.0/0|::/0'; then
    ok "advertising exit-node routes"
  else
    miss "not advertising exit-node routes"
    verify_result
  fi
else
  miss "could not read tailscale prefs"
  verify_result
fi

# Advertised but unapproved is a real, common state, and only an admin-console human
# can clear it — report blocked rather than failed so it doesn't look like a bug here.
status=$("$cli" status --json 2>/dev/null || true)
if printf '%s' "$status" | grep -q '"ExitNodeOption" *: *true'; then
  ok "approved as an exit node in the admin console"
else
  blocked "advertised but not approved — approve the route for this node in the Tailscale admin console (or add an autoApprovers entry for tag:host)"
fi

verify_result
