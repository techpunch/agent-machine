---
name: make-auto-login
summary: Log the admin user in automatically at boot, so the server recovers unattended.
requires: [have-server-identity]
needs: [filevault-off, admin-password]
root: yes
gates: the admin user's password, or the System Settings toggle
---

The step that makes a reboot survivable with nobody in the room. Agents, LaunchAgents, and the
the tmux grid all run in a logged-in GUI session, so a server sitting at the login window after a power cut
is a server that is down until someone connects to it.

FileVault and auto-login are mutually exclusive, and this recipe treats that as a decision rather
than a note. A FileVault-encrypted disk needs a password at the pre-boot screen, before any
LaunchDaemon or network stack exists, so no amount of configuration gets you both. Set
`FILEVAULT_POLICY` in `server.env`:

- `off` (default) — FileVault off, auto-login on, unattended recovery works. Verify goes red if
  FileVault is on.
- `on` — you have chosen encryption at rest over hands-off reboots. This recipe then reports
  `blocked` rather than half-applying, and every reboot needs a human or a managed
  `fdesetup authrestart`.

If you want encryption at rest without giving up unattended reboot, that is a different design —
an encrypted data volume unlocked from the network at boot. It is drafted in
`recipes/make-data-encrypted/recipe.md`, which is where it will land — not here.

Setting auto-login needs the admin user's password, to write `/etc/kcpassword`. That is your actual
login password, so this recipe does not take it — it gates, and hands you the command to run:

```
sudo sysadminctl -autologin set -userName <admin> -password -
```

The trailing `-` makes `sysadminctl` prompt for the password. Apple's own man page prefers this form,
and it is the only one where the password never reaches argv (`ps`), your shell history, or a Claude
transcript. Re-run the recipe afterwards to verify it took.

That makes this recipe gate-by-default, unlike the rest of the host layer. It is a deliberate
exception for the one secret that unlocks the machine itself. For an unattended build, setting
`ADMIN_PASSWORD` in the environment still works — the recipe uses it and says plainly that it is
visible in `ps` while the command runs.
