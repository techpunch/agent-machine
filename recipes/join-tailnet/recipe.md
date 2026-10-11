---
name: join-tailnet
summary: Join the tailnet as this server, using a tagged pre-auth key.
requires: [have-tailscale, have-server-identity]
needs: [tailnet-key, tailnet-acl]
root: yes
verify_root: no
gates: the auth key, supplied in the environment
---

Puts the host on the tailnet as `SERVER_NAME` with `tag:host`. After this the server is reachable by name
from anywhere on the tailnet, which is what makes every later recipe runnable over SSH.

It joins with a pre-auth key rather than an interactive login, so the server never sees the tailnet
owner's password and the tailnet can live under an account unrelated to the shared
account.

The key is a secret and is never written to `server.env`. Store it once in the Keychain and every
later server picks it up automatically:

```
security add-generic-password -s agent-machine -a TS_AUTHKEY -T /usr/bin/security -U -w
```

No value on that command line — `security` prompts, so the key stays out of your shell history. The
recipe reads it back with `secret_get`, and hands it to `tailscale up` through a mode-600 temp file
rather than `--authkey=<value>`, which would expose it in `ps`. Setting `TS_AUTHKEY` in the
environment still works for unattended runs, with that exposure. Apply records only the resulting
node name and IP.

A tagged node is owned by the tailnet rather than by a user and has key expiry disabled, which is
why the server stays connected across reboots instead of dropping off in 90 days.

The macOS menu bar shows an email address under the device name. That is the tailnet's name — a
personal tailnet is named after the account that created it — not a login on this machine. Check
with `tailscale switch --list`: the Account column is the node's identity, and on a tagged node it
is the machine.

The `tag:host` tag, its owner, and the reusable key are shared setup done once — see
`docs/shared-setup.md`. The host is the only tailnet node on the server: agent sandboxes cannot
reach the tailnet, because `have-agent-sandbox` denies them its `100.64.0.0/10` range.

## The tag is a boundary, not a label

`tag:host` is what the tailnet policy keys off, and the policy is written so that no rule names it
as a source. A tagged node is owned by the tailnet rather than by a user, so it is not part of
`autogroup:member` and matches nothing as a sender. The result is one-way: your devices reach this
server, and this server can open a connection to nothing you own.

That is worth more than it looks, because it is the only control here that the server does not
administer. Tailscale enforces ACLs on the receiving device, so a fully compromised server cannot
disable it, and it holds for the host itself — not just for sandboxes, which is the one place the
sandbox boundary contributes nothing. It also bounds what physical theft gets someone, which
matters on a machine this cookbook deliberately runs with FileVault off and auto-login on.

None of it is verified from here. The policy lives in the admin console, this recipe only joins,
and a server has no way to read the tailnet policy or prove a peer is unreachable without a peer to
try. `prereqs/tailnet-acl.md` is where it gets arranged; Tailscale's own `tests` block is what keeps
it true afterwards.

Verify records `TS_IP` into `server.env` when it finds the server connected, so later recipes and you
have it without a lookup. That IP is what used to live in an inventory table.

## A machine that was already on a tailnet

Common, and it needs handling rather than assuming a clean Mac. Someone signs in to Tailscale with a
personal account months before deciding the box should be a server: the node is untagged, named
whatever macOS called the machine, and carries the 90-day key expiry that tagged nodes do not.

Tailscale reports that as `Running`, so "already connected" is not the same as "connected the way this
needs". Apply compares the actual node name and tag against what it wants, and re-joins with
`--force-reauth --reset` when they differ — plain `up` on a running node keeps the old identity and
ignores the key, which would leave verify failing forever while apply insisted there was nothing to
do. `--reset` also clears leftover flags from the earlier setup, like advertised routes or custom DNS.

The one thing it cannot do for you is delete the old node object in the admin console. That object
keeps the name, which is why a re-join can land as `<name>-1`; apply says so when it re-joins.
