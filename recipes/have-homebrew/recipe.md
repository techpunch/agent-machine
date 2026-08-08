---
name: have-homebrew
summary: Install Homebrew and put brew on the admin user's PATH.
requires: [have-xcode-clt]
root: no
gates: none
---

The package prerequisite under everything installed later — Tailscale, sbx, tmux.

Runs the official install script non-interactively (`NONINTERACTIVE=1`, so it doesn't stop to ask
for a keypress on a headless server) and appends the `brew shellenv` line to the admin user's
`.zprofile` so `brew` is on PATH in a fresh login shell, not just this one.

It also turns Homebrew's analytics off. Homebrew reports to InfluxDB on every command by default;
a server that installs a handful of formulae and then runs untouched for months has no reason to
be telling anyone about it. The state is read through `brew analytics state` rather than a config
file, because that file's location has changed between Homebrew versions and the CLI has not.

Must not run as root — Homebrew refuses. If you invoked the driver with sudo, this recipe drops back
to `ADMIN_USER`.

Node, cloud SDKs, and the agent tooling are deliberately not installed here. They live in the agent
VM, not on the host — see `docs/host-agent-design.md`.
