---
description: Apply a recipe and everything it depends on
argument-hint: <recipe-name>
---

Apply `$1` on this server.

Show the user `./bin/cookbook plan $1` first, then apply. The script resolves prerequisites, skips
what is already satisfied, applies the rest in order, re-verifies, and writes the ledger. Do not do
any of that by hand.

If the plan needs root, you cannot run the apply. sudo prompts on `/dev/tty`, and Claude Code's
shell has none — a leading `!` does not change that. Give the user `./bin/cookbook apply $1` to run
in a terminal on the server and ask for the output. The driver checks this before starting, so a
plan with no root recipe you can still run yourself.

What you own is everything the script cannot decide:

- Secrets. A recipe that needs `TS_AUTHKEY` or `ADMIN_PASSWORD` gates rather than guessing. Ask the
  user, then pass it inline for that one run — `TS_AUTHKEY='...' ./bin/cookbook apply $1`. Never
  write it to `server.env`, and never echo it back.
- Gates (exit 3). Not a failure: a human step the machine cannot take. Show the gate text verbatim,
  since it names the exact toggle, dialog, or physical action. If it is a GUI step and you can reach
  the screen over Screen Sharing, offer to do it. Then re-run the same command.
- Failures (exit 1). Read the verify output and work out why. Report what actually happened,
  including which recipes did apply before the failure — the chain stops but does not roll back.
- Blocked chains (exit 2). The recipe has no scripts because a design decision is open. Say which
  decision, from the recipe's `blocked_by`, rather than trying to route around it.

A failure here is usually a defect in the cookbook rather than something odd about this machine, and
fixing it properly is the job — see "This project corrects itself" in `CLAUDE.md`. What you must not
do is edit a recipe to make a verify pass without understanding why it failed. Every server pulls
this repo, so a wrong `apply.sh` runs as root everywhere. Diagnose first, fix the cause, re-verify,
and update whatever docs asserted the old behaviour.
