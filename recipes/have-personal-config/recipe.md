---
name: have-personal-config
summary: Clone the personal dotfiles and Claude config repos onto this server.
requires: [have-xcode-clt]
root: no
gates: placing the files, which only you know the layout of
---

Optional, and personal. A new server starts with a stock home directory: no shell config, no
aliases, no Claude settings. This clones the repos that carry yours so you are not rebuilding them
by hand on every machine.

Two repos, cloned into `~/src`:

- `bobfejes/homedir` — shell and dotfile setup
- `bobfejes/claude-clojure-plus` — Claude Code configuration

Nothing else in the cookbook depends on this, and nothing breaks if you skip it. It exists because
"set the machine up the way I like it" is a real step that otherwise happens ad hoc and gets
forgotten on the second server.

## Why it clones but does not install

The clone is the tedious part and it is safe to automate. Placing the files is not: each repo knows
its own layout, and this recipe does not. Guessing at it would mean writing over `~/.zprofile` or
`~/.claude/settings.json` with something assembled from an assumption, on a machine you are about to
make headless.

So apply clones, then gates and tells you to run whatever install step each repo defines. If the
repos grow a documented installer, this recipe should call it and the gate should go — that is a
fix worth making, not a limitation to live with.

## It interacts with `have-coordination`

`have-coordination` writes a managed `~/.tmux.conf` and marks it "edits are overwritten". If your
dotfiles repo also carries a `.tmux.conf`, one of them wins depending on which ran last. Same for
anything in the repo that sets `PATH` in `~/.zprofile`, which `have-coordination` appends to.

Run this first, then `have-coordination`, so the cookbook's managed files land on top. If you would
rather keep your own tmux config, the fix is to stop `have-coordination` managing that file rather
than to let the two fight silently.

## Private repos

If either repo is private, the clone needs a credential on the host. That is fine here — this is the
trusted side, and the host already holds a GitHub token for pushing agent work. It is not fine
inside a sandbox: see [`../../docs/pushing-agent-code.md`](../../docs/pushing-agent-code.md) for why
the push credential stays on the Mac.

Apply gates rather than failing if a clone is refused, so an authentication problem tells you what to
do instead of ending the run.
