# Running the cookbook

`/setup` covers the normal path and you do not need this page for it. This is the operator's view:
what the driver guarantees, how to read what it leaves behind, and the handful of things that are
easy to get wrong when you drive it by hand.

## The commands

`/setup` is a wrapper. The driver underneath is a shell script that works with or without Claude in
the room — it resolves prerequisites, skips what is already satisfied, sudos what needs it, and
writes the ledger and the log:

```
./bin/cookbook goals                # the outcomes, and which are already true
./bin/cookbook preflight <goal>...  # what you have to arrange elsewhere first
./bin/cookbook plan <goal>...       # what would run, in order
./bin/cookbook apply <goal>...      # do it
./bin/cookbook status               # what is true right now, recipe by recipe
./bin/cookbook list                 # every recipe, including the ones not written yet
./bin/cookbook stale                # what has gone out of date
./bin/cookbook log                  # every action and result, with timestamps
```

Goals and recipe names are interchangeable as arguments — `apply run-agents` and
`apply have-vm-claude-code` both work. Goals are the human-facing names, and several can be given at
once: they resolve into one correctly-ordered run rather than several overlapping ones.

Three narrower slash commands sit alongside `/setup`: `/cookbook` runs status and explains it,
`/cook <recipe>` applies a single recipe, and `/update` researches what `stale` could not answer and
then patches the machine or the cookbook.

## Keeping it current

`stale` is the counterpart to `status`. Status asks whether this server matches what the cookbook
intends; stale asks whether what the cookbook intends is still a good idea. The second drifts on
other people's release schedules rather than on anything this machine did, which is why it is a
report rather than a recipe — a recipe makes a state true and keeps it true, and "up to date" is
never true for long.

It splits into two halves that want different treatment. Outdated packages, an old container image
and pending macOS updates are patching, and they are fixed on the machine. Whether the base image
codename is still Debian's current stable, or whether a `blocked_by` reason has quietly expired, are
questions about the world — they need a network and judgment, and their fix is a commit that reaches
every server that pulls the repo. Run `/update` periodically and it does both.

## Before you change a recipe

```
./bin/check
```

Syntax, shellcheck, recipe and goal metadata, link integrity, and a dry run of the driver against a
throwaway state dir. It exists because a wrong `apply.sh` runs as root on every server that pulls
this repo, and it catches the mistakes that are invisible on a laptop — a script left
non-executable, which the driver skips in silence; a `needs:` pointing at a prereq that does not
exist; a recipe marked blocked that still ships an `apply.sh`.

What it cannot tell you is whether a recipe actually works. Only a real server does that.

## Safe to stop, safe to repeat

Every recipe checks whether it is already true before it changes anything, so re-running is always
safe and stopping halfway is always fine. There is no half-applied state to unwind — the chain stops
where it stopped, and the next run picks up from there. Anything already satisfied is skipped rather
than redone.

That is also why a second server is the same procedure again rather than a new one. Each machine
adopts its own name, keeps its own state locally, and joins the same tailnet.

## Never prefix the driver with sudo

```
./bin/cookbook apply <goal>          # right
sudo ./bin/cookbook apply <goal>     # wrong
```

The driver elevates the individual recipes that declare `root: yes` and leaves everything else
running as you. Running the whole thing as root breaks that: Homebrew refuses to operate as root at
all, and the state files under `~/.agent-machine` end up owned by root, so every later run as your
own user fails to write them.

If you have already done it, `sudo chown -R $(whoami) ~/.agent-machine` fixes the state files, and
`have-homebrew` will re-verify once its ownership is sane.

## Gates are not failures

Exit 3 means a recipe stopped at something a machine cannot do — approving a TCC prompt, clicking
through OAuth, swapping a cable. The gate text names the exact toggle, dialog or physical action.
Do it, then re-run the same command; everything already applied stays applied.

The exit codes are the whole interface between a recipe and the driver:

| | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| `verify.sh` | satisfied | not satisfied | blocked — needs a human or an external change | — |
| `apply.sh` | applied | failed | — | stopped at a manual gate |

## Two records, and which one to read

Both live in `~/.agent-machine/` on the server, outside this repo, so `git pull` never touches them.

`server.md` is the ledger: one row per recipe that has verified clean, with a timestamp. It records
what is true, not what was attempted — the driver writes a row only after a recipe applies *and*
re-verifies. So the ledger is the answer to "what is this machine".

`run.log` is the history: every run, every recipe attempted, every gate stopped at, every failure,
with timestamps and the full output of each apply. Append-only and never pruned. It is the answer to
"what happened", and it is the one you want when something broke three weeks ago — the ledger cannot
tell you that, because a failure never reaches it.

`./bin/cookbook log` shows the tail. Neither file holds secrets: those are passed in the environment
for a single command and never written down.

`server.env` is the third file, and it is config rather than a record — `SERVER_NAME`, `ADMIN_USER`,
`TS_IP`, the VM sizing, and whatever else recipes discover. Mode 600, shell-sourceable, and never a
place for a secret: anything with read access to the server can read it.

Keep a human copy of all this somewhere off the server. See README.

## What Claude is for, and what it is not

The driver is a shell script and needs no model. It resolves prerequisites, verifies before applying,
applies in order, re-verifies, and writes both records — deterministically, with or without Claude in
the room.

Claude earns its place on the judgment the script cannot exercise: reading a gate and doing the GUI
half over Screen Sharing, working out why a verify failed for an unexpected reason, supplying a
secret for one run, or writing the next recipe. `/setup` wraps the whole flow, `/cookbook` explains
status, `/cook` applies one recipe.

What Claude should never do is re-derive the ordering, run recipe scripts by hand, or edit a recipe
to make a verify pass. See "This project corrects itself" in [`../CLAUDE.md`](../CLAUDE.md) for the
difference between fixing a defect and papering over one.
