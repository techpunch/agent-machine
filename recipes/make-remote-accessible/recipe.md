---
name: make-remote-accessible
summary: Enable SSH and Screen Sharing / Remote Management so the server can be driven with no monitor.
requires: [have-server-identity]
needs: [full-disk-access]
root: yes
gates: Full Disk Access for the terminal running the recipe
---

Both remote paths onto the server. SSH is how everything after this gets done; Screen Sharing is the
escape hatch for the GUI-only steps (App Store sign-ins, OAuth browser flows, an installer dialog).

What it enables:

- Remote Login (SSH) via `systemsetup -setremotelogin on`.
- Remote Management via the ARD `kickstart` tool, with full privileges for all users.
- The macOS application firewall. It is on the same recipe because turning on two listeners without
  turning on the firewall is not a state worth being able to reach.

The Full Disk Access gate is the thing that trips people up. On current macOS, `systemsetup
-setremotelogin` fails silently or returns an error unless the process invoking it has Full Disk
Access. If Claude is driving this over an existing SSH session, that means Full Disk Access for
`sshd-keygen-wrapper`; locally in Terminal it means Full Disk Access for Terminal. Verify detects
the failure and apply stops at a gate naming the exact toggle.

Screen Sharing over the public internet is not the plan — `join-tailnet` is what makes these
listeners reachable, and only from the tailnet.

## Proving it

SSH proves itself the first time you use it. Screen Sharing does not, because nothing later in
the cookbook needs it — so it sits untested until the day something does, which is exactly when
you cannot afford to find out. From a Mac on the tailnet:

```
open vnc://<slug>
```

Finder > Go > Connect to Server (Cmd-K) takes the same `vnc://` address. Log in as `ADMIN_USER`
with that account's password — not an Apple Account. You should get the server's desktop.

Before `make-headless`, that desktop is whatever the monitor shows. After it, the resolution
comes from the display dongle, which is the reason the dongle is not optional.
