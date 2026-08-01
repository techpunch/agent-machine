#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"
need_root

cli=$(ts_cli) || die "tailscale not installed — run have-tailscale first"
"$cli" set --advertise-exit-node
ok "advertising exit-node routes"

if "$cli" status --json 2>/dev/null | grep -q '"ExitNodeOption" *: *true'; then
  ok "already approved in the admin console"
else
  gate "This server is now advertising exit-node routes, but the route is not approved yet.
In the Tailscale admin console, open ${SERVER_NAME:-this node} > route settings > approve 'Use as exit node'.
To stop doing this per server, add an autoApprovers entry for tag:host (see docs/shared-setup.md).
Then confirm from another tailnet device: select ${SERVER_NAME:-this node} as your exit node and
check that your public IP becomes this server's."
fi
