---
name: tailnet-acl
summary: A tailnet policy that lets you reach the server but never the reverse
when: before-you-start
---
Ten minutes in the Tailscale admin console, on your laptop. Do it before the server joins, so
there is never a window where it has full reach.

Tailscale's default policy is allow-all. Left alone, this server can open a connection to every
other device on your tailnet — your laptop, your phone, anything else you have added. Nothing in
the design needs that. You connect to the server; it never connects to you.

Writing that asymmetry down is the single cheapest security control in this cookbook, and the only
one the server cannot switch off, because Tailscale enforces it on the receiving device rather
than on the sender.

The policy, and the reasoning for each line, is in `docs/shared-setup.md` under "Tailnet policy".
Paste it into Access Controls, fill in the one host entry, and save. Tailscale validates it on
save and rejects it if the test fails, so a mistake here fails loudly rather than silently
leaving you open.

What it costs you: nothing this cookbook does. The server accepts SSH and Screen Sharing, serves
as an exit node, and reaches the internet exactly as before — ACLs govern traffic between tailnet
devices, not a machine's ordinary internet access.
