---
name: exit-node-approval
summary: Approval for this server's exit-node route, in the Tailscale console
when: during
---
One click, after the server advertises itself. I will tell you exactly when.

In the Tailscale admin console, open Machines, find this server, and approve its exit-node
route from the row's menu.

To skip this on every future server instead, add an autoApprovers block to the policy file
now and it happens automatically:
    "autoApprovers": { "exitNode": ["tag:host"] }
