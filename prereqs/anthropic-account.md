---
name: anthropic-account
summary: A Claude account with a paid plan, and a browser on your laptop
when: during
---
The agent in the VM signs in as you, so you need a Claude Pro or Max subscription — the
same login you use anywhere else.

The sign-in itself needs a browser, and this server has none. When we get there I will
print an SSH command that forwards a port from the VM to your laptop, you open the URL in
your own browser, and the token lands back in the VM. It persists across reboots, so this
happens once.

Two things worth knowing before you do it. That token is the one genuinely valuable thing
inside the VM, and signing out everywhere from your Claude account settings is the kill
switch if the server is ever suspect. And consider using an account separate from your
personal one — see docs/shared-setup.md for why.
