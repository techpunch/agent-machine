---
name: make-headless
summary: Prove the server survives a reboot untouched, then take the monitor, keyboard and mouse off.
requires: [make-always-on, make-remote-accessible, make-auto-login, join-tailnet]
needs: [headless-dongle]
root: no
gates: a reboot you have to trigger, and the physical dongle swap
---

The last host recipe, and the one whose ordering is load-bearing. Everything it depends on is
verified before anything gets unplugged, because the failure mode is a server you cannot reach and
cannot see.

It runs in two passes, which is why applying it once will normally stop at a gate.

Pass one — reboot survival. Apply records the current boot time and stops, asking you to reboot. On
the next run it checks the server has actually rebooted since, then re-verifies that auto-login
happened (the console is owned by `ADMIN_USER`, not the login window), Tailscale came back, and SSH
still answers. Only a server that recovered from a reboot with nobody touching it earns the second
pass.

Pass two — going headless. Apply stops at a gate for the physical work: unplug the monitor, put the
headless display dongle in the same HDMI port, disconnect the keyboard and mouse. The dongle is not
optional decoration — with no display attached the GPU stops driving one, and Screen Sharing gives
you a tiny unusable desktop. Re-run with `HEADLESS_CONFIRMED=1` once you have reconnected over
Screen Sharing and seen a full-resolution desktop through the dongle.

After this the server needs no physical access, and everything in the agent layer is done over SSH.
