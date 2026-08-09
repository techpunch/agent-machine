---
name: exit-node-approval
summary: Approval for this server's exit-node route, in the Tailscale console
when: during
---
Probably already done, and worth checking before anything else: the policy in
`docs/shared-setup.md` carries an autoApprovers block, so a tailnet set up from that file
approves this route by itself and there is nothing here to do. Open Access controls in the
Tailscale admin console and look for:
    "autoApprovers": { "exitNode": ["tag:host"] }

If it is there, skip the rest of this. The route is approved the moment the server advertises
it, on this server and every future one.

If it is missing — an older policy, or one written by hand — either add that block now, or
approve this one server by hand: in the admin console open Machines, find this server, and
approve its exit-node route from the row's menu. Adding the block is the better answer if
there will be another server, since the manual click has to be repeated for each.
