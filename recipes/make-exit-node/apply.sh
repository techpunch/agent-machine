#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"
need_root

cli=$(ts_cli) || die "tailscale not installed — run have-tailscale first"
"$cli" set --advertise-exit-node
ok "advertising exit-node routes"

# Approval arrives in the next netmap, not in the call that advertised the route. With an
# autoApprovers entry the whole thing is automatic, but the control plane still has to approve
# and push — checked in the same instant, a tailnet that needed no human at all stopped here
# and told its owner to go and click something that had already happened. Poll instead, and
# only call it manual once the round trip has had time to land.
approved=false
for _ in $(seq 1 10); do
  if "$cli" status --json 2>/dev/null | grep -q '"ExitNodeOption" *: *true'; then
    approved=true
    break
  fi
  sleep 2
done

if $approved; then
  ok "approved as an exit node"
else
  gate "This server is now advertising exit-node routes, but the route was still unapproved
20 seconds later, so it is waiting on a human.
In the Tailscale admin console, open ${SERVER_NAME:-this node} > route settings > approve 'Use as exit node'.
To stop doing this per server, add an autoApprovers entry for tag:host (see docs/shared-setup.md).
Then confirm from another tailnet device: select ${SERVER_NAME:-this node} as your exit node and
check that your public IP becomes this server's."
fi
