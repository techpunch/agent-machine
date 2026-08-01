---
name: make-always-on
summary: Never sleep, wake for network, and come back by itself after a power cut.
requires: [have-server-identity]
root: yes
gates: none
---

The power-management half of an unattended server. It does not touch remote access or login — those
are `make-remote-accessible` and `make-auto-login`.

What it sets:

- `sleep 0 disksleep 0 displaysleep 0` — nothing ever sleeps.
- `womp 1` — wake for network access.
- `autorestart 1` — restart automatically after a power failure.
- `systemsetup -setrestartpowerfailure on` — the same intent through the other API.

Hardware differences are expected, not errors. Apple Silicon Macs don't expose `womp` or
`autorestart` the way Intel ones do, and `systemsetup -setrestartpowerfailure` reports "not
supported" there. Verify prints `n/a` for a key the hardware doesn't have and stays green; it only
goes red for a key that exists and is set wrong.

A Mac mini on Apple Silicon restarts after power loss on its own once it has been shut down
uncleanly, so the missing keys are not a gap in practice.
