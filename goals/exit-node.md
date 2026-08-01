---
name: exit-node
summary: Route your traffic through it
recipes: [make-exit-node]
---

Advertise this server as a Tailscale exit node, so you can send your phone or laptop's
traffic through it when you are on wifi you do not trust.

Optional and independent of everything else. It needs one click in the Tailscale admin
console to approve the route, unless you set up auto-approval.
