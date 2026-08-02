# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this repo is

A cookbook for provisioning agent servers: Macs that already have a name and an admin user, and are
turned into unattended, headless, Tailscale-reachable hosts running one or more agents (Claude Code,
Codex) inside an isolated Linux VM.

Two ways you will be working in it, and they are different jobs:

- Driving a server. Claude Code runs on the server itself, in yolo mode, in a clone of this repo.
  `bin/cookbook` does the resolving, applying, and recording — always call it rather than running
  recipe scripts by hand or re-deriving the dependency order yourself. `/cookbook` and `/cook` wrap
  it and say what your part is.
- Editing the cookbook. Adding or fixing a recipe, which every server will pull. Higher stakes than
  editing a doc — a wrong `apply.sh` runs as root on every server that pulls it.

The two are not really separate, which is the next section.

## This project corrects itself

When something goes wrong on a server, the default assumption is that the cookbook is wrong — not
that this machine is unusual. A recipe that fails, a verify that lies, a doc that contradicts a
script, a gate whose instructions do not match what the screen actually says: all of those are
defects here, and the run that hit them is the only place they will ever surface. Fix the cookbook,
so the next server and the next person never meet it.

How to work when you hit one:

- Diagnose before you change. Read what actually happened — `./bin/cookbook log`, the verify output,
  the failing command run by hand. An error message is a starting point, not a cause.
- Experiment freely while you are still learning how something behaves. Change a script, run it, read
  the result, change it again. Poking at it is often the only way to find out what macOS or Colima
  really does, and that is fine.
- Then land a real fix. Exploratory edits are not the deliverable. Once you understand the cause,
  make the smallest change that addresses it, re-run verify to prove it, and remove anything you
  added only to learn with.
- Look for the same bug elsewhere. Most defects here are a class, not an instance. An empty-array
  expansion that broke one call site probably broke three; a chain that filtered the wrong netfilter
  hook probably has a verify that tests the wrong path too.
- Fix the docs in the same pass. A fix that leaves `recipe.md`, `README.md` or a doc asserting the
  old behaviour is half a fix, and the half that is left is the half that misleads someone later.
  Search for the claim you just invalidated rather than only editing the file you were in.
- Run `./bin/check` before you finish. It catches the class of mistake that is invisible on a
  laptop — an unexecutable script the driver would skip silently, a `needs:` pointing at nothing, a
  recipe marked blocked that still has an `apply.sh`. It cannot tell you a recipe works; only a real
  server does that, so say which is which.
- Say what you changed and why, plainly, including what you could not verify because you were not on
  a real server.

The one thing that is not self-correction: editing a recipe to make a verify pass without
understanding why it failed. That is papering over, it runs as root on every server that pulls this
repo, and it is how a cookbook stops being trustworthy. If you cannot work out the cause, say so and
leave it failing.

Blocked and deferred work is part of the same loop. A recipe whose `blocked_by` has stopped being
true should be unblocked; one that can never become a real recipe should be deleted rather than
carried. The set of things this repo says are pending should always be things that are actually
pending.

## Yolo mode on the host is for this repo only

Running with permissions skipped on the host Mac is justified for cookbook work and nothing else. If
asked to work on any other project from a host session, say so and move the work into the agent VM
(`colima ssh --profile agent`, throwaway clone) rather than doing it on the host. Do not make an
exception because a change looks small — that exception is how the boundary stops existing.

The full argument, and the rule about what may live in the VM, is in `docs/secrets-and-egress.md`.
That file is the single source for it; do not restate it elsewhere.

## Layout

- `README.md` — the landing page: what this is, what works, where to go.
- `bin/cookbook` — the driver: dependency resolution, verify/apply ordering, sudo, ledger, log.
- `bin/check` — everything checkable without a Mac: syntax, shellcheck, recipe and goal metadata,
  link integrity, and a dry run of the driver against a throwaway state dir. Run it before pushing.
- `recipes/<name>/` — one recipe: `recipe.md` (contract), `verify.sh`, `apply.sh`.
- `goals/<name>.md` — one selectable outcome in human words, naming the recipes that deliver it.
  This is what `/setup` offers; recipe names never reach the user.
- `prereqs/<name>.md` — one thing a human must arrange elsewhere, with how to do it and whether it
  has to happen before the run starts. Recipes point at these with `needs:`.
- `lib/common.sh` — shared helpers, sourced by every script. Output helpers, the server-state accessors,
  and macOS quirk handling (sudo home resolution, pmset keys, finding the Tailscale CLI).
- `.claude/commands/` — `setup` (guided, end to end), `cookbook` (report), `cook` (apply one
  recipe), `update` (what has gone stale, and fix it). Thin wrappers over `bin/cookbook` that say
  what Claude's part of the job is.
- `docs/` — `running-the-cookbook.md` (the driver's guarantees, the two records, what not to do),
  `secrets-and-egress.md` (where agents may run, and with what), `pushing-agent-code.md` (getting
  work out of the VM), `host-agent-design.md` (why the host and VM split), `shared-setup.md` (once,
  before the first server).

Goals, recipes and prereqs share one frontmatter format, so `meta_file()` parses all three.

This list is the only repo map. README points here rather than keeping its own.

Per-server state is not in this repo. It lives on each server at `~/.agent-machine/server.env`
(config), `server.md` (the ledger — what is true now), and `run.log` (the history — every action and
result). There is no central inventory here; a server carries its own record.

## The recipe contract

- `recipe.md` — frontmatter (`name`, `summary`, `requires`, `root`, `status`) and the prose explaining
  what it does, why, and what a human has to do by hand.
- `verify.sh` — is this already true? Read-only, cheap, safe to run any time.
- `apply.sh` — make it true. Idempotent.

Exit codes are the interface between a recipe and the driver, and nothing else is:

| | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| `verify.sh` | satisfied | not satisfied | blocked — needs a human or an external change | — |
| `apply.sh` | applied | failed | — | stopped at a manual gate |

A gate is not a failure. It is a step the machine cannot take — approving a TCC prompt, clicking
through OAuth, swapping a cable — and the gate text names exactly what to do and what to re-run.

## Writing a recipe

- One recipe, one concern. If the name needs "and", it is two recipes.
- `verify.sh` is read-only and cheap — it must not change the system or the server's own record.
  `cookbook status` runs every verify at once, and a verify with side effects is one you stop
  trusting. Recording a discovered value is apply's job.
- Never block waiting for a human. A recipe runs on a server with nobody at the screen, so anything
  that can raise a TCC prompt (`osascript` against System Events is the classic) hangs forever
  instead of failing. Prefer a file you can write and read back.
- `apply.sh` is idempotent. Running it on a server that is already in the target state must be a no-op,
  not an error.
- Print one line per fact checked, via the `ok` / `miss` / `blocked` / `skip` helpers. A verify that
  fails must say which fact failed — "not satisfied" alone is useless over SSH.
- Exit codes are the interface: verify 0/1/2, apply 0/1/3. The driver keys off them.
- Hardware and OS differences are `skip`, not `miss`. Apple Silicon has no `womp` key; a recipe that
  goes red forever on hardware that cannot satisfy it is a broken recipe.
- Anything a human must do by hand is a `gate` in `apply.sh`, with text naming the exact toggle,
  dialog, or physical step. Do not silently skip it, and do not pretend a GUI step was automated.
- Prerequisites go in `requires:`, never as a check inside `apply.sh`. The driver resolves the graph.
- Anything a human must arrange outside this machine — an account, a key, a physical object — goes in
  `needs:`, pointing at a file in `prereqs/`. Never a bare sentence in the recipe prose: preflight
  unions `needs:` across the resolved plan, so a prerequisite recorded anywhere else is one the user
  finds out about too late. Only list what cannot be automated; anything the cookbook installs is a
  recipe, not a prereq.
- A recipe that delivers something a user would ask for by name should be reachable from a goal in
  `goals/`. If no goal names it, it can only be run by someone who already knows the recipe exists.
- A recipe blocked on an unsettled design decision gets a `recipe.md` with `status: blocked` and
  `blocked_by:`, and no scripts. Do not write scripts against a decision that has not been made.

## Secrets

Never write a secret to `server.env` — every agent on the server can read it. Nothing secret belongs
in this repo either; shared credentials live in the team password manager, referenced from
`docs/shared-setup.md`.

Three tiers for getting a secret into a recipe, in the order `secret_get` (in `lib/common.sh`) tries
them. A new recipe that needs a secret should use it rather than reading an env var directly:

1. The Keychain, for anything reusable. Stored once with a prompting `security add-generic-password`,
   fetched silently after. Use `secret_store_hint` in gate text so every recipe says the same thing.
2. An interactive prompt the human runs, for a secret that unlocks the machine itself. `make-auto-login`
   is the example: it gates with a `sysadminctl ... -password -` command rather than accepting the
   password at all.
3. An environment variable, as a documented escape hatch for unattended runs. Say out loud that it is
   visible in `ps`; do not accept it silently.

Two rules that follow from this. Never put a secret in argv — prefer a `file:` argument or a mode-600
temp file, as `join-tailnet` does for `tailscale up`. And never let a secret lookup block: a locked
Keychain raises an invisible GUI prompt that hangs a headless server, which is why `secret_get` is
fenced with a timeout.

Full reasoning, including what this does not protect against, is in `docs/secrets-and-egress.md`.

## Conventions

- Recipe names: `have-*` ensures a dependency exists, `make-*` puts the server into a state, `join-*`
  joins an external system.
- Shared versus per-server is the core split. Anything done once and shared goes in
  `docs/shared-setup.md`; anything done per server is a recipe. Keep procedures in one place and
  cross-link rather than duplicating, so they cannot drift.
- Ordering in `make-headless` is load-bearing: remote access and reboot survival are verified before
  the monitor and keyboard come off. Preserve that if you touch it.
- Placeholders for a human are `<FILL IN>`. Leave them alone unless you have the real value.
- Minimal markdown. No bold or italics unless the emphasis is genuinely load-bearing — a real safety
  warning, not decoration. Headers, lists, tables, and inline `code` are fine.
