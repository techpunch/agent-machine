---
name: make-data-encrypted
summary: Encryption at rest for the sensitive parts, unlocked from the network at boot.
requires: [join-tailnet]
root: yes
status: blocked
blocked_by: deferred — the shape is chosen; needs a real server to build and size against
---

Encryption at rest without giving up unattended reboot, which full-disk FileVault cannot do (see
`make-auto-login`). Keep FileVault off so the server comes back after a power cut with nobody at the
keyboard, and encrypt the data that matters with a key fetched over the network at boot. Steal a
server and you cannot read it, because the key server refuses to hand out the key.

## What it buys, honestly

Protects a server that is powered off or rebooted while stolen, or one you proactively revoke.

Does not protect a server stolen while running — the volume is already mounted and the data is live
until the next reboot — nor against someone pulling cached credentials off the unencrypted boot volume
before you revoke. Keep all secrets and workspaces on the encrypted volume, use a per-server key you
can revoke individually, and keep the boot volume free of long-lived secrets.

With auto-login you cannot gate login itself on the network key without reintroducing the
password-at-boot problem. So login proceeds unencrypted and minimal, and a LaunchDaemon mounts the
encrypted volume afterwards. Agents are gated on that mount.

## Shape

```
power on → auto-login (boot volume, no secrets)
         → LaunchDaemon: fetch key over network (exp backoff, retry forever)
         → unlock/mount encrypted DATA volume  →  /Volumes/agentdata
         → start agents (Claude Code / Codex) — depend on the mount
```

Everything that matters — agent configs (`~/.claude`, `~/.codex`), workspaces, repos — lives on the
encrypted volume, symlinked back into place. The account home stays on the boot volume holding
nothing sensitive. Revocation means making the key fetch fail; at the next reboot the data is
unreadable.

The volume is an encrypted sparsebundle: `hdiutil create -size 100g -encryption AES-256 -type
SPARSEBUNDLE -fs APFS`, attached at boot with the key on stdin via `-stdinpass`. Simple, copyable,
trivial to destroy. A native encrypted APFS volume is the alternative — snapshot-friendly, but a
repartition-ish operation, and rotating the passphrase means re-keying. Start with the sparsebundle.

## The key server, and why Cloudflare

The constraint that decides it: this daemon runs at boot, before any user session exists, so the key
fetch must work with nothing but DHCP, DNS and a route. This is the one place in the cookbook that
deliberately breaks the "everything hangs off the auto-login session" rule in
`docs/host-agent-design.md`, and it breaks it in the direction of needing less.

Chosen — a Cloudflare Worker plus KV. The Worker returns a server's key if its bearer token is valid
and not flagged revoked. Twenty-odd lines, one KV namespace, `wrangler deploy`; the server fetches
with plain `curl`. No maintenance, nothing whose uptime is yours, revocation is deleting one KV entry,
free at this volume. It wins on the combination rather than any single axis.

Rejected, and why:

- A private repo plus a fine-grained per-server PAT is smaller still — one file, `curl`, no code. But
  fine-grained PATs cap at one year, so an expired token means a server that silently fails to unlock
  at a reboot months later. The passphrase also persists in git history after rotation.
- GCP Secret Manager buys per-server IAM and a real audit log, at the cost of a GCP project and an
  SDK install on every server, putting `gcloud` in the boot path. Nothing else here uses GCP. Reach
  for it only if the audit trail becomes a requirement.
- A Tailscale-gated endpoint is appealing — no TLS certs, and revocation is removing the device. It
  fails the boot-path constraint: `have-tailscale` brings the tailnet up via a per-user LaunchAgent at
  login, after this daemon has already started. It also needs a second always-on host to serve from,
  since it cannot be the server being unlocked. It would become right if both of those changed.

One claim not to repeat: an earlier draft argued the Tailscale option put no new credential on the
unencrypted boot volume. Overstated — tailscaled's node key already lives there. It is not an
*additional* credential, which is a much smaller win, and every option here revokes in one action.

## Unlock daemon

`/Library/LaunchDaemons/com.agent-machine.unlock.plist`, `RunAtLoad` and `KeepAlive` so it restarts if
it exits before the mount succeeds.

```bash
#!/bin/bash
set -u
SERVER_SLUG="$(scutil --get LocalHostName)"
backoff=2; max=300

fetch_key() {
  curl -fsSL -H "Authorization: Bearer ${KEY_TOKEN}" "https://<worker>.workers.dev/key/$1"
}
is_mounted() { mount | grep -q '/Volumes/agentdata'; }

while ! is_mounted; do
  if KEY="$(fetch_key "$SERVER_SLUG")" && [ -n "$KEY" ]; then
    printf '%s' "$KEY" | hdiutil attach ~/agentdata.sparsebundle -stdinpass -mountpoint /Volumes/agentdata
    unset KEY
  fi
  is_mounted && break
  sleep "$backoff"
  backoff=$(( backoff * 2 )); [ "$backoff" -gt "$max" ] && backoff="$max"
done

touch /var/run/agentdata.ready   # release the gate so agents may start
```

Never write the key to disk — stdin only, unset after. Add jitter to the backoff so a fleet does not
stampede the key server after a shared outage.

## Revocation

- Delete that server's KV entry, or set `revoked=true`.
- Confirm it can no longer fetch. It spins in backoff and the data stays locked at next reboot.
- Revoke its tailnet node too — a separate action, and both belong in the runbook.
- Rotate the key and reissue the bearer token if the server is recovered.
- Update your off-server record — the copy of this server's details you keep on your laptop or in
  your password manager, not on the box. See README.

## Still open

- Whether to accept the stolen-while-running gap, or auto-eject the volume on idle or locked screen.
- The exact `hdiutil` flags on the target macOS version.
- Rotation cadence for the per-server keys.
