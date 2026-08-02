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

## Your agent cannot read the web, and that will bite

`balanced` allows AI provider APIs, package managers, code hosts, container registries and common
cloud services. That covers the agent working, dependencies installing and git — and nothing else.
Reading a vendor's API reference, a blog post or a Stack Overflow answer is denied.

This is not a bug in the preset, it is the whole point of default-deny, but it is the thing you will
hit first. Two practical consequences:

- Claude Code's `WebFetch` runs on the machine it is on, so inside a sandbox it is subject to the
  same policy and will fail on an arbitrary URL. `WebSearch` goes through the Anthropic API, which is
  allowed, so searching works while fetching the results does not.
- A blocked fetch is often silent from the agent's point of view. It falls back to memory and
  produces confidently outdated code rather than announcing that it could not read the docs.

Widen it deliberately rather than reaching for `allow-all`:

```
sbx policy ls                                  # what is actually allowed right now
sbx policy allow network docs.python.org       # one domain
sbx policy allow network '*.readthedocs.io'    # a wildcard
sbx policy allow network example.com --sandbox <name>   # just this sandbox
```

The rule worth keeping: documentation and package hosts earn a place, telemetry and analytics do
not. If you find yourself adding a dozen domains for one task, that is a signal to scope the rule to
that sandbox rather than loosening the baseline for everything.

## Making a denial loud

A blocked request is not silent at the wire — the proxy returns:

```
HTTP/1.1 403 Forbidden
Blocked by network policy: domain example.com:443
detail: no matching allow rule — blocked by default deny policy
```

That names the domain and is distinguishable from a `404`, which is the origin answering. The problem
is not the error, it is what an agent does with it: routing around it and answering from memory reads
as a confident answer and is often wrong about current APIs.

Two halves, because they have different audiences:

- `sandbox-CLAUDE.md` next to this recipe tells the agent to stop and name the domain rather than
  work around it, and says the fix costs one command. Install it once at `~/.claude/CLAUDE.md`
  inside a sandbox — that path is on the persistent volume, so later sandboxes inherit it.
- `./bin/cookbook denials` asks the proxy instead of the agent. That matters because the failure this
  guards against is an agent that did not mention it, and because a denial hit by a subprocess — a
  build script, a package manager — never surfaces as an agent tool call at all.

There is a better answer than a long allowlist for documentation specifically — a doc broker such as
Context7, or a self-hosted docs instance, puts thousands of libraries behind one allowed host. Worth
reaching for before the allowlist grows past a screenful.

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
