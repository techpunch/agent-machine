---
name: make-exit-node
summary: Advertise this server as a Tailscale exit node.
requires: [join-tailnet]
needs: [exit-node-approval]
root: yes
gates: route approval in the Tailscale admin console
---

Optional. Turns the server into an exit node so other tailnet devices can route their public traffic
through its connection.

Advertising is only half of it: an exit node does nothing until the route is approved for the node
in the admin console. Verify reports `blocked` rather than red when the server is advertising but not
yet approved, because that is a state only a human with admin-console access can move out of.

Approving it once per server is avoidable — an `autoApprovers` entry for `tag:host` in the ACL policy
approves exit-node routes for every host as it joins. That is shared setup, in
`docs/shared-setup.md`.
