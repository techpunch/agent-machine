---
name: anthropic-account
summary: A Claude account with a paid plan
when: during
---
The agent signs in as you, so you need a Claude Pro or Max subscription — the same login you use
anywhere else.

The sign-in happens inside a sandbox with `/login`, once, and persists. No SSH tunnel and no browser
on the server: `sbx` handles the flow, and on a headless machine with no unlocked login session it
stores the result in an encrypted file rather than the macOS Keychain, telling you when it does.

Two things worth knowing before you do it. That token is the one genuinely valuable thing inside a
sandbox, and signing out everywhere from your Claude account settings is the kill switch if the
server is ever suspect. And consider using an account separate from your personal one — see
docs/shared-setup.md for why.
