---
name: have-agent-auth
summary: Sign each agent in and persist its credentials so they survive a container restart.
requires: [have-containers]
root: no
status: blocked
blocked_by: deferred — have-vm-claude-code covers Claude Code alone; this is Codex alongside it
design: docs/host-agent-design.md — "Agent authentication"
---

Subscription OAuth for Claude Code and Codex, driven over an SSH tunnel from your laptop because the
flows want a browser and the server has no one sitting at it.

Each agent's credential directory goes on a named volume so a container rebuild doesn't cost you
every sign-in.

This recipe will be mostly gates by nature — an OAuth flow is a human clicking approve. What it can
own is the tunnel setup, the volume layout, and verifying afterwards that each agent reports itself
authenticated.

Accounts and subscriptions are shared, not per server: see `docs/shared-setup.md`.
