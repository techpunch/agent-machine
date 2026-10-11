---
name: make-ssh-keys-only
summary: SSH accepts keys only, so nothing that reaches the server can log in by guessing a password.
requires: [make-remote-accessible]
needs: [client-ssh-key]
root: yes
verify_root: no
gates: a key login proved from each client before passwords are turned off
---

macOS ships SSH accepting the admin password. Anything that can reach port 22 — a device on the
tailnet, or a sandbox if its deny rules ever failed — can then try that password, and the right one
is the whole Mac. With keys only there is nothing to guess.

What apply does:

- Stops at a gate until the admin user's `~/.ssh/authorized_keys` holds a key, and again until you
  say a key login worked from your clients (`KEY_LOGIN_TESTED=yes`). Turning passwords off before
  that is how you lock yourself out.
- Writes `/etc/ssh/sshd_config.d/001-agent-machine.conf` with `PasswordAuthentication no` and
  `KbdInteractiveAuthentication no`, and checks it with `sshd -t` before leaving it in place. sshd
  takes the first value it reads and the main config includes that directory early, so the low
  number is what makes it win over anything macOS adds there.

macOS starts a fresh sshd for each connection, so the change applies to the next login with no
restart, and the session you ran it from stays open. Test from a client in a new terminal before
you close it.

Screen Sharing is not changed. It still takes the admin password, which keeps it the way back in if
every key is lost — so keep that password strong. How to set up each client, for both SSH and
Screen Sharing, is in [`../../prereqs/client-ssh-key.md`](../../prereqs/client-ssh-key.md).

Verify reads the same config files sshd reads, as a plain user, and takes the first value of each
setting the way sshd does. It stops at the first `Match` block rather than interpret it, so a
`Match` that turns passwords back on for some connections would go unseen; this cookbook writes
none.
