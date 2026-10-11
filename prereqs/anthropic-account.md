---
name: anthropic-account
summary: A Claude account with a paid plan, if you want Claude Code on this server
when: during
---
Only if you want Claude Code. This server runs Claude Code, Codex, or both, and neither needs the
other — the Codex side is [`openai-account.md`](openai-account.md). You do need at least one of them,
or the agent sandbox has nothing to run.

The agent signs in as you, so you need a Claude Pro or Max subscription — the same login you use
anywhere else.

The sign-in happens inside the agent sandbox, with `/login` the first time you run `claude` there.
Nothing runs a browser in the sandbox or on the server: `/login` prints a link, you open it on your
laptop or phone, approve, and paste the code it shows back into the terminal.

It cannot reuse a login you already made with Claude Code on the Mac itself. sbx has no way to import
one — sharing a subscription login is an open request,
[docker/sbx-releases#11](https://github.com/docker/sbx-releases/issues/11), and the `setup-token`
workaround in that thread stopped working in v0.43 — so the sandbox gets a sign-in of its own.

It is once, not once per project. The resulting session token is held on the host and injected into
outbound requests by the proxy, so it is never written inside the sandbox, and recreating the
sandbox does not cost you the login. That is also why the subscription is the recommended path here
rather than an API key: it is both less work and less exposure.

Two things worth knowing before you do it. Signing out everywhere from your Claude account settings
is the kill switch if the server is ever suspect, and a `/login` session expires eventually — Claude
Code warns three days out, which is worth catching on a machine you are not sitting at. And consider
using an account separate from your personal one — see docs/shared-setup.md for why.
