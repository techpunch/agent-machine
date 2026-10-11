---
name: ssh-keys-only
summary: Log in with keys, not passwords
order: 5
recipes: [make-ssh-keys-only]
---

SSH stops accepting the admin password, so nothing that can reach the server can get in by guessing
it. Each laptop or phone you connect from needs its key added first; the run walks you through it and
will not switch passwords off until a key login has worked.

Screen Sharing still uses the password, which keeps it as the way back in if a key is lost.
