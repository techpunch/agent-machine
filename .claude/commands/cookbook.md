---
description: Report what is already true on this server, recipe by recipe
---

Run `./bin/cookbook status` and explain the result. Pass any recipe names the user named as
arguments; with none, it checks everything.

The script does the work. Your job is the reading:

- Lead with the answer — which recipes are `ok`, which are `todo`, which are `blocked`.
- `unknown` is the absence of an answer, not a bad one. That verify reads settings only root can
  see, and Claude Code's shell has no `/dev/tty` for sudo to prompt on. Say so, say it does not
  mean the recipe failed or was never applied, and check the ledger (`./bin/cookbook record`, or
  `server.md`) which does know whether it was applied. If they want the live answer, the command
  is theirs to run in a terminal — offer it rather than trying it yourself and hitting the guard.
- For anything not `ok`, the `MISSING` and `BLOCKED` lines are the actionable part. Say what they
  mean in plain terms rather than repeating them verbatim.
- `blocked` has two different causes and they matter: a recipe with `status: blocked` has no scripts
  yet because a design decision is open, while a verify exiting 2 means the server is in a state
  only a human can move it out of (an unapproved route, a policy conflict). Do not conflate them.
- Close with the single recipe you would run next, and the exact command.

It may prompt once for sudo — several verifies read settings only root can read.

Do not apply anything.
