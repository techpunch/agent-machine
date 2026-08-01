---
description: Check what has gone stale on this server and in the cookbook, then fix it
---

Two jobs that look like one and are not. Keep them apart, in this order.

Start with `./bin/cookbook stale`. It takes half a minute and reaches the network. It reports
facts only — what is outdated, what is upgradable, how old the image is — and then lists the
questions it cannot answer from the machine.

## Part one: this server

Everything under `== this server` is patching. Report it plainly, ordered by what actually
carries risk rather than by what has the biggest number.

Then offer to apply, and be specific about consequence, because these are not equal:

- `brew upgrade` — usually safe, occasionally breaks a formula something else depends on.
  Say how many packages. On a server running agents, take it.
- `apt-get upgrade` in the VM — safe, and the VM is disposable, so this is the easiest yes.
- Rebuilding the agent image (`apply have-containers`) — how the base image's security
  updates actually reach the container. An image more than a month old is worth rebuilding
  even with no other reason. Nothing is lost: credentials live on volumes, not in the image.
- macOS updates — these reboot the machine. Fine on a server that has proved it comes back
  unattended, and `make-headless` is exactly that proof. Confirm before triggering, tell the
  user it will drop the connection, and say roughly how long before it is reachable again.
- A VM reboot when `/var/run/reboot-required` exists — kills anything running in the VM, so
  check whether the user has agents mid-task first.

Do not batch these into one silent sweep. Apply, confirm each worked, and say what changed.

## Part two: the cookbook

Everything under `== needs judgment` is a question about the world, so research it. This part
produces a commit, not a patched machine, and the fix reaches every server that pulls the repo.

- The base image codename. Find out whether it is still Debian's current stable and still in
  full security support, not LTS. A codename does not follow Debian forward, so this goes
  stale silently — it already did once, which is why the check exists. If it has moved, edit
  `recipes/have-containers/Dockerfile`, update the dates in the comment beside `FROM`, and
  fix the supply-chain table in `docs/host-agent-design.md`.
- Colima, Tailscale, Claude Code. Look for releases that fix something worth having, and for
  advisories. A newer version for its own sake is not a reason; a fix is.
- The blocked recipes. Read each `blocked_by` and ask whether it is still true. This is the
  one that rots quietest: a recipe deferred because "nothing needs it today" stays deferred
  long after something does. If a reason has expired, say so and propose unblocking.

Anything you change here, run `./bin/check`, and update whatever doc asserted the old fact —
that is the standing rule in `CLAUDE.md`, and version claims are exactly the kind that go
stale in three places at once.

## Both halves

Say what you could not verify. A timed-out check is not a clean one, and `stale` prints when
it gave up rather than pretending.

Nothing here is destructive except the reboots, and both are announced. But this runs against
a machine somebody depends on, so the rule is the same as everywhere else in this repo:
diagnose, act deliberately, and report what actually happened rather than what you intended.
