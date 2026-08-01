---
name: have-vm-claude-code
summary: Claude Code installed and signed in inside the agent VM.
requires: [have-agent-vm, make-vm-network-bounded]
needs: [anthropic-account]
root: no
gates: the OAuth sign-in, completed over an SSH tunnel from your laptop
---

Installs Claude Code in the VM with the native installer — no Node on the guest — and then stops for
the one thing that genuinely needs a human: signing in.

This is where project work happens. Yolo mode on the host is for the cookbook only; every other
project runs here, in the VM, against a throwaway clone. That split is the whole reason the VM
exists — see [`../../docs/secrets-and-egress.md`](../../docs/secrets-and-egress.md).

`make-vm-network-bounded` is a hard prerequisite rather than a suggestion. Signing in puts a
long-lived OAuth token in the VM, and that token is the one thing in there worth stealing. Doing it
before the network is bounded means a window where a compromised agent could both take the token and
reach your tailnet. See [`../../docs/secrets-and-egress.md`](../../docs/secrets-and-egress.md).

## The sign-in, and why it is a gate

There is no browser on the server and no one sitting at it. The flow is: run `claude /login` inside
the VM, which starts a callback listener and prints a URL; forward that port to your laptop; open the
URL in your own browser; the token is delivered back into the VM.

Lima forwards a guest's listening ports to the host automatically, so one hop from your laptop to the
server should be enough:

```
ssh -L <port>:localhost:<port> <admin>@<server>
```

If the callback port does not come through, Lima did not pick it up, and the fallback is a second hop
into the guest:

```
colima ssh --profile agent -- -L <port>:localhost:<port>
```

The gate prints both. Confirm which one actually works on your Colima version the first time you run
this, and fix the gate text to lead with that one — a runbook with two options is a runbook you have
to think about at 11pm.

## Sign-in persists

The credential lands in `~/.claude` in the guest and survives VM restarts, host reboots, and image
rebuilds. The refresh token renews the short-lived access token in the background, so a restart is
not a re-auth event. You repeat this only when the refresh token is invalidated — long inactivity, a
password change, or a deliberate sign-out-everywhere.

Which is also the kill switch: if this VM is ever suspect, sign out everywhere from your Anthropic
account and the token in it becomes worthless.
