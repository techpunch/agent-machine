---
name: have-homebrew
summary: Install Homebrew and put brew on the admin user's PATH.
requires: [have-xcode-clt]
root: no
gates: none
---

The package prerequisite under everything installed later — Tailscale, Colima, agent tooling.

Runs the official install script non-interactively (`NONINTERACTIVE=1`, so it doesn't stop to ask
for a keypress on a headless server) and appends the `brew shellenv` line to the admin user's
`.zprofile` so `brew` is on PATH in a fresh login shell, not just this one.

Must not run as root — Homebrew refuses. If you invoked the driver with sudo, this recipe drops back
to `ADMIN_USER`.

Node, cloud SDKs, and the agent tooling are deliberately not installed here. They live in the agent
VM, not on the host — see `docs/host-agent-design.md`.
