---
name: have-tailscale
summary: Install the Tailscale app and make sure it relaunches at login.
requires: [have-homebrew]
root: no
gates: none
---

Installs the cask only. Joining the tailnet is `join-tailnet`, kept separate because installing is
idempotent and unauthenticated while joining consumes an auth key.

The cask is the GUI app, whose CLI lives inside the bundle at
`/Applications/Tailscale.app/Contents/MacOS/Tailscale`. Recipes never hardcode that path — they call
`ts_cli` from `lib/common.sh`, which also finds a formula install if that is what the server has.

The app has to come back after a reboot or the server drops off the tailnet and is unreachable. This
recipe handles that with a LaunchAgent in the admin user's `~/Library/LaunchAgents` rather than a
login item. Login items can only be read or written through System Events, which raises an
automation TCC prompt — and a prompt with nobody at the screen blocks forever, which is the one
thing a recipe on a headless server must never do. A LaunchAgent is a file we can write and read back.
