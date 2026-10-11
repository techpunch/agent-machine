---
name: openai-account
summary: A ChatGPT account with a paid plan, if you want Codex on this server
when: during
---
Only if you want Codex. This server runs Claude Code, Codex, or both, and neither needs the other —
the Claude side is [`anthropic-account.md`](anthropic-account.md). You do need at least one of them,
or the agent sandbox has nothing to run.

Codex is on every ChatGPT tier including Free, but the Free limits are sized for a few quick tasks
and will not carry an agent working unattended. Go, Plus, Pro or a Business seat is the realistic
floor.

The sign-in happens on the host, not in a sandbox, and it is once rather than once per project:

```
sbx secret set openai --oauth
```

That opens a browser on the server, which a headless machine reaches through screen sharing — so do
it before the monitor comes off, or over the screen-sharing session `make-remote-accessible` sets
up. The sign-in finishes on a `http://localhost:<port>/…` callback on the server, so an SSH tunnel
works instead if you would rather use your laptop's browser: run the command over SSH, note the port
in the link it gives, then `ssh -L <port>:localhost:<port> <server>` from the laptop and open the
link there. That is a workaround reported in
[docker/sbx-releases#208](https://github.com/docker/sbx-releases/issues/208), which asks Docker for
a proper headless sign-in; it has not been tried on this cookbook. Do it before the agent sandbox is created: Codex's setup inside it is fixed then, from whether a
sign-in exists, and `have-shared-sandbox` waits for it. The tokens land in the host keychain and the proxy injects them into outbound requests, so no
sandbox ever holds the credential. `sbx secret set openai` without `--oauth` stores an API key
instead, which buys no isolation the subscription does not already have and swaps a flat plan for
metered billing.

This is the one place Codex differs from Claude Code, where `/login` is typed inside the sandbox and
the OAuth flow still terminates on the host. Same outcome, different starting point.

Consider using an account separate from your personal one — see docs/shared-setup.md for why.
