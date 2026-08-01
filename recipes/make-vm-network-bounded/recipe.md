---
name: make-vm-network-bounded
summary: Full internet from the VM, but no path inward to the host, the tailnet, or your LAN.
requires: [have-agent-vm]
root: no
gates: none
---

What makes full egress defensible. The agent gets the open internet — package registries, docs,
GitHub, the Anthropic API, no allowlist to maintain — and cannot reach anything private.

Denied from inside the VM:

- `100.64.0.0/10` — the Tailscale range. This is the one that surprises people: the VM lives on a
  machine that is a tailnet node, so without this rule a compromised agent inherits reach to your
  laptop, the host, and every other machine on your tailnet.
- `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` — your LAN and the host.
- `169.254.0.0/16` and the IPv6 equivalents — link-local, and the cloud metadata endpoint.

"Full egress" here means open to the internet, not open to your estate. Read
[`../../docs/secrets-and-egress.md`](../../docs/secrets-and-egress.md) for what that does and does
not buy you — it is not a substitute for keeping secrets out of the VM.

## The DNS carve-out

Colima's VM uses user-mode networking, and its DNS resolver sits on an RFC1918 address inside that
private range. Dropping the whole range naively takes name resolution down with it, and the failure
looks like "the internet is broken" rather than "your firewall is working."

So the ruleset accepts the guest's own resolver on port 53 specifically, before the drops. Only port
53, and only that address — not the gateway host in general, because the gateway is also the path to
the host Mac, and opening it would reintroduce exactly the inward route this recipe exists to close.

Internet traffic itself needs no exception: the gateway is the next hop, but the packets are
addressed to public IPs, and nftables filters on destination.

## Two hooks, because containers do not use the first one

The denials are applied at both the output and the forward hook, from one shared chain so they cannot
drift apart.

Output covers traffic the VM itself originates. Forward covers traffic it routes for something else,
which in practice means containers. This distinction is easy to get wrong and expensive when you do:
a ruleset with only the output hook blocks the VM while leaving every container free to reach your
tailnet and your LAN, and it looks correct in any test run over `colima ssh`.

Both chains sit at priority -10, ahead of the rules Docker installs for itself, so a reject here wins
regardless of what the daemon does afterwards. The flip side is that loading this ruleset flushes
Docker's tables too, and Docker only rebuilds them at startup — so apply restarts the daemon if it is
running.

## Verifying rather than trusting

`verify.sh` does not just check that the rules are loaded — it tests the behaviour from inside the
VM: a public host resolves and connects, while a `100.64.0.0/10` and an RFC1918 address both fail.
A firewall you have not watched fail closed is a firewall you are guessing about.

When a container runtime is present it repeats the two denial probes from inside a container, since
that is the path the agents actually use. Without a runtime those checks report `n/a` rather than
passing silently.

The container probe distinguishes three outcomes, not two. A refused connection is a pass; a
successful one is a failure; a probe that could not run at all — image missing, daemon unhappy —
reports `BLOCKED`, which exits 2. Collapsing "could not test" into "closed" is how a firewall check
comes back green on the strength of a test that never executed, and this is a control whose entire
job is to not be trusted. Apply pulls the probe image for the same reason: a verify must be cheap and
offline, so it can never depend on reaching a registry.
