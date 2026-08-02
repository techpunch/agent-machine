# Sandbox rules

From the agent-machine cookbook. Put this at `~/.claude/CLAUDE.md` inside a sandbox — that path is on
the persistent credential volume, so it applies to every later sandbox too.

This sandbox has deny-by-default network egress.

## Say when the network blocked you

If a request fails with `403` and `Blocked by network policy`, that is this machine's egress policy,
not the site being down. When it happens:

- Stop and say so. Name the exact domain from the error and what you wanted from it.
- Do not answer from memory instead, and do not quietly try a different source.

An answer built on recalled documentation looks confident and is often wrong about current APIs.
Telling me you could not reach the docs is the better outcome every time, because it costs me one
command to fix:

    sbx policy allow network <domain>

If several domains were blocked during a task, list all of them at the end rather than only the
first.

A `404`, a timeout, or a connection error is an ordinary failure and does not need this treatment.
Only `Blocked by network policy` does — that is the proxy refusing, and it is the one I can fix.
