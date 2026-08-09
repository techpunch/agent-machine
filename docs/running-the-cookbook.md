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
./bin/cookbook record               # write the record you keep a copy of elsewhere
```

`record` writes `~/.agent-machine/server-record-<slug>.md` from `server.env` and the ledger — what the
machine is, what is applied, where its secrets live (pointers, never values), and how to revoke
access. It is a snapshot, so re-run it after anything that changes the server. Set
`SERVER_LOCATION` in `server.env` to have it record where the box physically sits.

Keeping it on the server is what lets another machine fetch it over ssh, and the file ends with
the `scp` line for that. Keeping it *only* there is the mistake: every reason to read it is a
reason the server cannot be reached, so the copy that counts lives somewhere else.

That `scp` lands the file in `~/.agent-machine/` on the client — the same directory name a server
uses for its own state, so there is one place to look on any machine you own, and a laptop that
reaches several servers ends up holding one record each rather than scattering them.

Run `apply` from a terminal. sudo prompts on `/dev/tty`, so a plan containing a root recipe needs
a session that has one — Terminal.app on the server, or ssh. Claude Code's shell does not qualify,
and neither does its `!` prefix, so an agent driving this hands the apply to a human and reads the
output. Everything else here is read-only and runs anywhere. `apply` checks for a usable terminal
before it starts, rather than failing at the first root recipe with sudo's own error.

It only asks when a root recipe is actually going to run. One that is already satisfied gets skipped
and never calls sudo, so it does not count — which is why re-running a finished goal, or applying a
non-root recipe that merely depends on a root one, works from a session with no terminal at all.

## Letting an agent run the applies

Optional. sudo needs `/dev/tty` only in order to ask for a password, so anything that answers the
password some other way lets Claude Code drive the whole run — applies, gates, re-runs — instead
of handing a command back at every root recipe. The driver's terminal check keys off
`sudo -n true`, so it stands down by itself once one of these is in place.

By default sudo keeps a separate credential record per terminal, which is why authenticating in
Terminal.app does nothing for an agent's session. `timestamp_type=global` makes one record cover
all of a user's login sessions. The human still types the password; it just counts everywhere.

Install it in a terminal, which also authenticates you:

```
./bin/cookbook sudo-window on
```

It writes the drop-in, validates it, installs it as `/etc/sudoers.d/agent-machine-setup`, and runs
`sudo -v`. Validation happens before installation and the run stops if it fails: a malformed sudoers
file can lock you out of sudo entirely, which on a headless server means a keyboard you no longer
have. A separate file under `sudoers.d` keeps the damage to something you can delete. The timeout is
minutes, 5 by default; 30 covers a working session without leaving the window open all day.

Close it when the run is done, and confirm with `ls /etc/sudoers.d/`:

```
./bin/cookbook sudo-window off
```

That removes the file and runs `sudo -k`, so the cached credential goes with it rather than staying
valid for the rest of the window.

What this costs: for the length of the window, any process running as that user can sudo without
a password, not just the cookbook. What it does not cost is a standing grant — the file alone
authorizes nothing, so forgetting to remove it leaves sudo credentials un-scoped from the terminal
rather than leaving the machine passwordless. That asymmetry is why this is the documented option.

Two alternatives, and why they are not:

- `NOPASSWD` for the admin user. Simpler, and strictly worse: it grants root with no human in the
  loop at all, for as long as the file exists. Scoping it to the recipe scripts rather than `ALL`
  looks tighter but is not, since the scripts live in a repo the same user can write to.
- A `SUDO_ASKPASS` helper that pops a GUI password dialog. Tightest of the three while a screen is
  attached, and a trap afterwards: on a headless server the dialog waits forever with nobody to
  answer it, which is the exact hang recipes are written to avoid.

Goals and recipe names are interchangeable as arguments — `apply run-agents` and
`apply have-agent-sandbox` both work. Goals are the human-facing names, and several can be given at
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
`TS_IP`, `SBX_POLICY`, and whatever else recipes discover. Mode 600, shell-sourceable, and never a
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
