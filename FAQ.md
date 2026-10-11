# FAQ

## Why sbx rather than Colima?

Both give the agents their own Linux VM with nothing from the Mac mounted. sbx does three things
Colima leaves to us:

- It keeps agents off the Mac from outside the VM. Its proxy runs on the Mac, so an agent with root
  in the VM cannot switch it off. A Colima VM's traffic leaves through a Lima process on the Mac and
  looks local to the Mac's firewall, so blocking it means writing our own firewall — and the last
  Colima setup here had three security defects in that kind of code.
- Sign-ins can be used but not read. The Claude, Codex and GitHub tokens stay on the Mac and are added
  to requests on the way out, so a prompt injection can use them while it runs but cannot copy them.
  In Colima they are files inside the VM.
- Its defaults are safe. Colima's default config mounts your home folder into the VM, writable.

Colima would be simpler in some ways: no Docker account, open source, and signing in is just
logging in. If sbx does not hold up on a real server, the fallback is plain Lima with no mounts,
agents running as a user without sudo behind a firewall inside the VM, and SSH on the Mac set to keys
only.

The full comparison is in [`docs/host-agent-design.md`](docs/host-agent-design.md).
