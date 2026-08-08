---
name: have-server-identity
summary: Adopt the machine's existing name and admin user, and create the local server state files.
requires: []
root: yes
verify_root: no
gates: none
---

The root of the dependency graph. Every other recipe reads `server.env`, so this one has to run first
on a new server.

The server already has a name and an admin user — this recipe adopts them rather than creating them.
It reads the current `ComputerName`, confirms the three `scutil` names agree with each other,
confirms the invoking user is an admin, and writes both to `~/.agent-machine/server.env`. From then on
every recipe reads `SERVER_NAME` and `ADMIN_USER` from there instead of guessing.

If the three `scutil` names disagree — which is the normal case on a machine named through the GUI,
not the exception — apply fixes them. That needs root, which is why this recipe is `root: yes` even
though most of what it does is write two files in your home directory. The driver handles the sudo;
the state files still end up owned by the admin user, not by root.

A Mac named through the GUI usually has a `ComputerName` with spaces and capitals — "Studio Mac
mini". `LocalHostName`, `HostName`, and Tailscale hostnames cannot hold either, and all three
silently rewrite what you give them, which would leave verify comparing against a name that can
never match. So the recipe derives `SERVER_SLUG` from `SERVER_NAME` once, and every machine-facing
name comes from the slug while the human-facing `ComputerName` keeps whatever the server arrived
with.

## Config it sets

- `SERVER_NAME` — the machine's human name, as shown in System Settings.
- `SERVER_SLUG` — the lowercase hyphenated form, used for `HostName`, `LocalHostName`, and the
  Tailscale node name.
- `ADMIN_USER` — the local admin account the agents and auto-login use.
- `BOX_LOCATION` — free text, whatever you'd have put in the old inventory table. Optional; set it
  yourself in `server.env` if you want it recorded.

## State files it creates

- `~/.agent-machine/server.env` — shell-sourceable config, mode 600. Machine-readable, read by every
  recipe. Never put secrets here that you wouldn't want an agent on this server to read.
- `~/.agent-machine/server.md` — the ledger. One row per recipe that has verified clean, with a
  timestamp. This is what replaced an inventory table: the server carries its own record.

Neither file is in the cookbook, so `git pull` never touches them.
