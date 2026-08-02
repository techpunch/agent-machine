---
name: anthropic-account
summary: A Claude account with a paid plan
when: during
---
The agent signs in as you, so you need a Claude Pro or Max subscription — the same login you use
anywhere else.

The sign-in happens inside a sandbox with `/login`. No SSH tunnel and no browser on the server —
`sbx` handles the flow.

Worth knowing before it surprises you: it is once **per sandbox**, not once. Sandboxes share no home
directory, so a new one means signing in again. If you end up starting sandboxes all day, the
alternative is an API key held as an `sbx` secret and injected by the proxy — every sandbox picks it
up and the agent never sees the raw value — at the cost of metered billing rather than your
subscription.

Two things worth knowing before you do it. That token is the one genuinely valuable thing inside a
sandbox, and signing out everywhere from your Claude account settings is the kill switch if the
server is ever suspect. And consider using an account separate from your personal one — see
docs/shared-setup.md for why.
