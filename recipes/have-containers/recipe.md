---
name: have-containers
summary: The agent container image and the per-trust-tier boundary between projects.
requires: [have-agent-vm, make-vm-network-bounded]
root: no
gates: none
---

The VM separates the agents from the Mac. Containers add the cheaper second boundary, between
projects of different trust — which is what this recipe builds: one image for the interactive agents,
one isolated network per trust tier, a credential volume, and an `agent-run` launcher that puts a
project in a container with the right flags.

Claude Code and Codex share the image. They are the same trust tier — same kind of subscription
credential, same episodic CLI shape — so a boundary between them would separate things that are not
meaningfully different, at the cost of a second image and a second sign-in. The rule that does earn
its keep is one level down: a new container when work crosses a trust boundary.

```
agent-run ~/work/<repo>             # trusted: shares the network and the credential
agent-run ~/work/<repo> untrusted   # untrusted: own network, no credential
```

A container can commit but cannot push: no GitHub credential enters the VM, let alone a container.
Work comes out as a patch you read and apply on the Mac — see "Getting code back out" in
[`../../docs/secrets-and-egress.md`](../../docs/secrets-and-egress.md).

## What the launcher enforces

- Non-root, `--cap-drop ALL`, `no-new-privileges`. An agent that is root in the container is one
  escape away from root in the VM, for no benefit.
- A per-tier network. Docker's default bridge lets every container reach every other one, which would
  put an untrusted project's agent next to your other projects' listening ports. Filesystem isolation
  does not stop that; network policy does.
- CPU, memory and PID caps, derived from the VM's own size rather than hardcoded. They are ceilings,
  not reservations, so two containers can each be allowed half without either being starved unless
  both peak at once. A runaway build then cannot peg the whole VM, which matters most at exactly the
  moment you want to attach and kill it.
- Only the project directory is mounted. Nothing else from the VM, and nothing at all from the Mac.
- A credential volume per tier. An untrusted project never sees the token your other work uses — it
  signs in once against `agent-claude-untrusted`, which you can revoke on its own.

## The network prerequisite is not optional

`make-vm-network-bounded` is a hard requirement, and both apply and verify check for a `forward` chain
specifically rather than just a loaded ruleset.

Container traffic is routed by the VM rather than originated by it, so it is governed by the forward
hook. A ruleset covering only the output hook bounds the VM while leaving every container free to
reach your tailnet and your LAN — and it looks correct in any test run over `colima ssh`, because that
tests the VM's own namespace. Creating containers against an output-only ruleset would quietly undo
the isolation the whole design rests on, so this recipe refuses to run.

Verify goes further than apply and proves it behaviourally: it starts a container on the trusted
network and tries to reach the tailnet and an RFC1918 address, using the agent image and bash's
`/dev/tcp` so no extra image is needed. A probe that could not run reports `BLOCKED` rather than
passing — mistaking "could not test" for "was refused" is how a firewall check comes back green on a
test that never executed.

## Credentials live on a volume, not in the image

The image carries no secret. `~/.claude` is a named volume mounted at run time, so a sign-in survives
image rebuilds and VM restarts, and nothing sensitive can leak through image layers if the image is
ever shared. The first run in each tier needs the OAuth flow — the same SSH-tunnel dance as
`have-vm-claude-code`, run inside the container.

Two volumes, one per tier, and the reasoning is worth being explicit about because the obvious
alternative is wrong. Giving the untrusted tier no credential at all — an empty tmpfs — sounds safer
and is in fact useless: the agent cannot authenticate, so it cannot run, so the tier does nothing.
Giving it the same credential as everything else defeats the point. So it gets its own, which means
an untrusted project can work, cannot read the token your real work uses, and can be cut off by
revoking one session without disturbing anything else.

Within a tier, Claude Code and Codex share the volume, since they share the tier. One container
compromise costs you both, and that trade stops holding the moment an agent arrives with a credential
you would not hand the other.
