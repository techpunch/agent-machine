---
name: anthropic-account
summary: A Claude account with a paid plan
when: during
---
The agent signs in as you, so you need a Claude Pro or Max subscription — the same login you use
anywhere else.

The sign-in happens inside a sandbox with `/login`. No SSH tunnel and no browser on the server —
`sbx` handles the flow.

It is once per sandbox. Sandboxes are long-lived and reattach, so in practice that means once per
project — not per session. Only deleting a sandbox costs you the sign-in again.

Two things worth knowing before you do it. That token is the one genuinely valuable thing inside a
sandbox, and signing out everywhere from your Claude account settings is the kill switch if the
server is ever suspect. And consider using an account separate from your personal one — see
docs/shared-setup.md for why.
