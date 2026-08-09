---
name: make-exit-node
summary: Advertise this server as a Tailscale exit node.
requires: [join-tailnet]
needs: [exit-node-approval]
root: yes
verify_root: no
gates: route approval in the Tailscale admin console
---

Optional. Turns the server into an exit node so other tailnet devices can route their public traffic
through its connection.

Advertising is only half of it: an exit node does nothing until the route is approved for the node
in the admin console. Verify reports `blocked` rather than red when the server is advertising but not
yet approved, because that is a state only a human with admin-console access can move out of.

Approving it once per server is avoidable — an `autoApprovers` entry for `tag:host` in the ACL policy
approves exit-node routes for every host as it joins. That is shared setup, in
`docs/shared-setup.md`. Approval lands in the next netmap rather than in the call that advertised
the route, so apply polls for it before deciding a human is needed.

## Using it, and proving it works

Nothing changes on the server: an exit node is chosen by the client, per device, and stays off
until someone picks it.

- macOS: Tailscale menu bar > Exit Nodes > this server. Tick Allow Local Network Access if you
  still want your printer and other LAN devices.
- iPhone: Tailscale app > Exit Node > this server. `None` turns it back off.

The proof is your public IP, since that is the only thing a user can see change. Check
`curl -s ifconfig.me` — or any "what is my IP" page on a phone — before and after selecting it.
It should become the server's public address, not the client's.

Tailscale's own page is short and covers every platform:
https://tailscale.com/kb/1103/exit-nodes

Worth knowing before relying on it: traffic now leaves from wherever the server sits, so anything
that geolocates you follows the server. That is the point on untrusted wifi and a nuisance
otherwise.
