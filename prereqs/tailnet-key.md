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
3. Open Settings, then Keys, and generate an auth key with Reusable ON, Pre-approved ON,
   and the tag set to `tag:host`. Copy it — it is shown once.

Have that key ready to paste when I ask. It is a secret: I will put it in the macOS Keychain
so later servers pick it up on their own, and it never gets written into this repo.
