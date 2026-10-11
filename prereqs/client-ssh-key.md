---
name: client-ssh-key
summary: An SSH key on each laptop or phone you connect from, added to the server
when: during
---
Once SSH stops taking passwords, only a device whose key is on the server can log in. Do this from
each one while passwords still work.

Mac or Linux:

```
ssh-keygen -t ed25519            # only if ~/.ssh/id_ed25519 does not exist yet
ssh-copy-id <admin>@<server>     # asks for the password one last time
ssh <server>                     # should log you in with no password
```

Phone (Termius, Blink): create a key in the app and copy its public key. Then, from a computer that
already gets in, add it as one line:

```
ssh <server> 'cat >> ~/.ssh/authorized_keys'    # paste the key, Enter, then Ctrl-D
```

Screen Sharing does not change. On a Mac, `open vnc://<server>` (or Finder, Go, Connect to Server),
then log in as `<admin>` with its password. On a phone, a VNC app that supports macOS logins, such
as Screens. It is also the way back in if every key is lost, so keep that password strong.
