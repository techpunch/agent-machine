---
name: have-agent-vm
summary: A CPU/RAM-capped Colima Linux VM with no host mounts, auto-started at login.
requires: [have-homebrew, make-headless]
root: no
gates: none
---

The isolation boundary. Agents run inside this VM, never natively on macOS — so a compromised agent
gets a disposable Linux box, not your Mac.

Colima over UTM, as the design doc settles: headless, CLI-driven, defined as config rather than
clicked together, and it auto-starts cleanly as a LaunchAgent. UTM stays the deliberate add-on for
the cases that need a graphical desktop or snapshots.

## No host mounts is the load-bearing property

Colima mounts your home directory into the guest by default. That would undo the whole point: an
agent inside the VM could read your SSH keys, your cloud credentials, and every repo on the Mac.
This recipe writes a profile config with `mounts: []` and then `verify.sh` asserts the running VM has
none.

The assertion is deliberately separate from the flag that sets it. Colima's mount configuration has
changed across versions, so the recipe does not assume a particular flag works — it checks the
property that matters and fails loudly if the VM came up with a mount anyway. If verify reports a
mount on a version where the config was ignored, that is real, and the fix belongs here rather than
in a workaround on the server.

## Sizing

The default shape is 6 vCPUs, 10 GB of RAM, and a 100 GB disk, chosen for the reference server: a
base M4 Mac mini with 10 cores, 16 GB, and 256 GB. That leaves macOS 4 cores and 6 GB, which is
comfortable for a headless box running nothing but the VM.

Those are clamped rather than merely defaulted, so a smaller machine gets a workable VM instead of a
config it cannot honour: at least 2 cores and 4 GB are always held back for macOS, and 40 GB of disk.
Applying to a machine with too little RAM or disk fails with the reason rather than building
something broken.

Values are recorded to `server.env` as `VM_CPUS`, `VM_MEMORY`, `VM_DISK` on first apply, so verify
has something to compare against and the next server reproduces the same shape. Override by setting
them in `server.env` before applying; they are only derived when absent, so an existing server keeps
whatever it was built with.

Three details behind the numbers:

- Memory is the one to watch. Colima's `vz` backend reserves the guest's memory outright rather than
  ballooning it, so 10 GB genuinely leaves the host. If macOS starts swapping under Screen Sharing
  plus a couple of containers, drop this before touching anything else.
- Disk is checked against free space rather than total, because on APFS those differ a lot and what
  matters is what the VM can grow into. It is a ceiling, not an upfront cost — Colima allocates
  sparsely.
- Cores are not exclusive. The guest gets 6 vCPUs to schedule on and macOS can still run; this is the
  least risky of the three to set high.

Capping matters beyond tidiness: an agent that runs away — a compile bomb, a crypto miner following
an injected instruction — is bounded by the VM's allocation rather than taking the whole Mac down.
`have-containers` derives a per-container ceiling of half the guest's memory from these values, so
resizing the VM resizes that too.

## A VM that already exists

`colima start` on a VM that is already running does not re-read its profile, so a pre-existing
`agent` VM — made by hand, or built by an earlier run with different numbers — keeps the size it was
created with while `server.env` reports whatever this recipe last wrote. Verify compares the live VM
against the recorded values and fails on a mismatch rather than trusting the file.

Resizing is not free: it means stopping the VM, which kills anything running in it.

```
colima stop --profile agent
./bin/cookbook apply have-agent-vm
```

Host mounts are checked twice for the same reason — once in the profile config and once with
`findmnt` inside the running guest. A VM built before this recipe existed, or by an older Colima with
different mount defaults, can have `$HOME` mounted while the config file says otherwise, and that is
the one misconfiguration that quietly removes the isolation boundary.

## Scope

This recipe gets you a VM. It does not set the network posture, which is `make-vm-network-bounded`
and is not optional — read [`../../docs/secrets-and-egress.md`](../../docs/secrets-and-egress.md)
before putting anything in here.

Claude Code runs directly in this VM rather than in a container. That is a deliberate narrowing for a
single agent on a single project; `have-containers` adds the boundary between projects, and it
becomes worth doing as soon as a second agent's credentials or an untrusted project shows up.
