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

Hardware differences are expected, not errors. Verify prints `n/a` for a key the hardware doesn't
have and stays green; it only goes red for a key that exists and is set wrong. An M4 Mac mini
exposes `womp` and `autorestart` and accepts `systemsetup -setrestartpowerfailure`, so nothing is
skipped there; the skip path exists for models that differ, and portables in particular.

Both halves have been confirmed on an M4 mini rather than inferred: a remote reboot came back
unattended, and pulling the power brought it up again with nobody pressing the button. So on this
hardware the settings do what they claim, which is not something a `pmset -g` readout can tell you.

## Proving it

Verify reads the settings back. That is not the same as watching the machine come up, and the two
things that can go wrong are tested differently — only one of them is a reboot.

Reboot survival is `make-headless` pass one, and you can have that proof without going headless:
applying the headless goal runs it and then stops at the dongle gate, which is a gate, not a
failure. By hand, run it from a client and never from the server's own keyboard — touching the
keyboard is the thing the test exists to rule out.

```
ssh <slug> uptime
ssh -t <slug> sudo shutdown -r now
until ssh -o ConnectTimeout=5 <slug> uptime; do sleep 10; done
```

`-t` because sudo wants a terminal to prompt on. When that last line finally answers, auto-login
happened, Tailscale's LaunchAgent came back with the GUI session, and sshd is listening again —
the whole unattended chain in one result.

A power cut is the other failure, and a reboot does not test it. `autorestart` only fires when
power is actually lost, so the only honest test is pulling the plug: unplug the machine, wait a
few seconds, plug it back in, and see whether it boots with nobody pressing the power button. Worth
doing while the server is still somewhere you can reach, rather than discovering it after a storm.
