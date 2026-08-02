---
name: have-agent-sandbox
summary: Docker Sandboxes installed and signed in, so agents run in microVMs.
requires: [have-homebrew]
needs: [docker-account, anthropic-account]
root: no
gates: the Docker personal access token, and the agent sign-in inside a sandbox
---

Where agent work happens. `sbx` runs each agent in a microVM with its own filesystem, its own Docker
daemon and its own network, and routes all outbound traffic through a proxy on the host that enforces
a deny-by-default policy.

This replaced a hand-built Colima VM, an nftables ruleset and a container launcher. The reason is not
that those could not work — it is that they were security-critical code with nobody but us reviewing
them, and three real defects surfaced in a single pass: a firewall that filtered only locally
originated traffic so every container bypassed it, a verify that tested the wrong network namespace
and therefore always passed, and a container tier that could not authenticate. `sbx` is maintained,
its posture is stricter than what we wrote, and its own security docs are honest about the parts that
remain your problem.

## Day to day

```
sbx run --clone claude            # a sandbox on a read-only clone of the current repo
git fetch sandbox-<name>          # bring the work back, on the host
```

`--clone` matters. The default mounts your working tree read-write, and an agent that can write
`.git/config` in a directory you later run git in has a path to executing commands on your Mac — see
[`../../docs/pushing-agent-code.md`](../../docs/pushing-agent-code.md), which walks the whole attack.
With `--clone` the sandbox gets its own clone and you retrieve work by fetching, which lands objects
in a repository whose config you control.

## The network policy

Set once and recorded as `SBX_POLICY`. `balanced` is the default here.

The posture is stricter than the VM it replaced: outbound HTTP and HTTPS only to allowed domains, and
all non-HTTP protocols — raw TCP, UDP including DNS, ICMP — blocked at the network layer. The host,
localhost services and private ranges are unreachable, which is what the old nftables rules were
hand-written to do.

That costs git over SSH, which is why the workflow above clones over HTTPS. It also means a sandbox
cannot reach your tailnet, which was the pivot this design worried about most and now gets
structurally rather than by rule.

## Two secrets, two different problems

The Docker token authenticates `sbx` itself and belongs in the Keychain, fetched by `secret_get` like
the tailnet key. Read scope is enough. It never reaches `server.env` and never appears in argv.

The agent's own sign-in happens inside a sandbox with `/login`, and persists. On a headless server
with no unlocked login session `sbx` falls back from the Keychain to an encrypted file under
`~/.config/com.docker.sandboxes` and says so — the same failure mode `lib/common.sh` guards against
with its timeout, handled here by the tool.

## What this buys, and what it costs

Bought: microVM isolation, a maintained egress policy, credential injection, and per-project
separation without a launcher of our own.

Cost, stated rather than buried. The agent layer now depends on a proprietary tool and a Docker
account, free today. The host layer deliberately does not, so the machine stays useful if that
changes. And the Mac now holds project source, where before it held none — `--clone` keeps the write
direction safe, but "the host holds nothing an agent wants" is less true than it was.
