---
name: tailnet-key
summary: A Tailscale account, and a reusable auth key for this server
when: before-you-start
---
About five minutes in a browser, on your laptop rather than the server.

1. Sign in at https://login.tailscale.com — any account works, and the free tier is enough.
2. Open Access Controls and give yourself ownership of a `tag:host` tag, by adding this to
   the policy file:
       "tagOwners": { "tag:host": ["your-login@example.com"] }
3. Open Settings, then Keys, and generate an auth key. The form, top to bottom:
       Description   what it provisions and when you minted it, e.g.
                     "agent-machine servers (tag:host) — minted 2026-03-14". You are writing
                     this for whoever later has to decide if revoking it is safe.
       Reusable      ON   — the same key provisions the next server too
       Expiration    90 days, the maximum the form allows
       Ephemeral     OFF  — an ephemeral node is removed when it goes offline
       Tags          ON, set to `tag:host` — this is also what disables node key expiry
       Pre-approved  ON, if you see it. It only appears when the tailnet requires device
                     approval; on most tailnets there is no such field and nothing to do.
   Copy the key — it is shown once.

Have that key ready to paste when I ask. It is a secret: I will put it in the macOS Keychain
so later servers pick it up on their own, and it never gets written into this repo.

The 90 days applies to the key, not to the machines it authenticates. A tagged node's own key
does not expire, so servers already joined stay joined; what dies in 90 days is your ability to
provision the next one with the stored key. Mint a fresh one then, and it is also the moment to
revoke the old one.

While you are in Access Controls, do `tailnet-acl` too — it is the same policy file, and writing
it before the server joins means the server never has a window of full tailnet reach.
