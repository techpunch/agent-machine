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
sbx run --clone --kit recipes/have-agent-sandbox/kit --name <project> claude
git fetch sandbox-<project>       # bring the work back, on the host
```

Sandboxes are long-lived and reusable, not per-invocation. Running again in the same workspace — or
with the same `--name` from anywhere — reattaches to the existing one, and installed packages,
config and command history survive stops and restarts. So the shape that works is one sandbox per
project, kept.

`--clone` matters. The default mounts your working tree read-write, and an agent that can write
`.git/config` in a directory you later run git in has a path to executing commands on your Mac — see
[`../../docs/pushing-agent-code.md`](../../docs/pushing-agent-code.md), which walks the whole attack.
With `--clone` the sandbox gets its own clone and you retrieve work by fetching, which lands objects
in a repository whose config you control.

What `--clone` does not do is limit what the sandbox can read. Your host folder is also mounted
read-only at `/run/sandbox/source`, and that is the whole folder, not the tracked files — an
untracked `.env` or `.envrc.private` sitting beside your source goes in with it. This was reported
and closed as intended behaviour, so treat it as permanent. `--clone` protects the write direction
only; keeping secrets out of the directory is still your job.

Sandbox disks default to 20 GB, which a large monorepo plus a dependency tree can reach.
`DOCKER_SANDBOXES_ROOT_SIZE=40g sbx run ...` raises it, and `DOCKER_SANDBOXES_DOCKER_SIZE` covers the
separate Docker data disk.

## The network policy

Set once and recorded as `SBX_POLICY`. `balanced` is the default here.

The posture is stricter than the VM it replaced: outbound HTTP and HTTPS only to allowed domains, and
all non-HTTP protocols — raw TCP, UDP including DNS, ICMP — blocked at the network layer. The host,
localhost services and private ranges are unreachable, which is what the old nftables rules were
hand-written to do.

That costs git over SSH, which is why the workflow above clones over HTTPS. It also means a sandbox
cannot reach your tailnet or the LAN the server sits on.

The tailnet is covered twice — the policy in [`../../docs/shared-setup.md`](../../docs/shared-setup.md)
also denies the server as a source, from the host as well as from here, and Tailscale enforces that
on the receiving device rather than on this machine. The LAN is covered once, here. Worth knowing
which is which before deciding what the Mac is allowed to be plugged into.

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

## The kit

`kit/spec.yaml` beside this recipe carries two things every sandbox should start with: a starter
documentation allowlist, and guidance telling the agent to report a blocked request rather than work
around it.

It is a kit rather than a `~/.claude/CLAUDE.md` because sandboxes inherit nothing from the host —
your Mac's `~/.claude` stays on your Mac — and because a kit is a committed file, so both the
allowlist and the guidance are reviewable in this repo instead of living in one machine's local
policy store. Kits cannot write the memory file directly, since sandboxes seed that path during
setup and would overwrite it, so the guidance goes through `agentContext`, which appends to it.

Loading it from a path in this repo is fine. Remote kit sources are allowlisted to Docker Hub by
default under `kit.allowedSources`, but local directories are governed separately by
`kit.allowLocalKits`, which defaults to true. While editing the kit, `sbx kit add <sandbox> <path>`
applies it to a running sandbox and restarts it without losing state.

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

- The kit's `agentContext` tells the agent to stop and name the domain rather than work around it,
  and says the fix costs one command — which matters, because without that a model reasonably
  concludes that finding another way is the helpful thing to do.
- `./bin/cookbook denials` asks the proxy instead of the agent. That matters because the failure this
  guards against is an agent that did not mention it, and because a denial hit by a subprocess — a
  build script, a package manager — never surfaces as an agent tool call at all.

There is a better answer than a long allowlist for documentation specifically — a doc broker such as
Context7, or a self-hosted docs instance, puts thousands of libraries behind one allowed host. Worth
reaching for before the allowlist grows past a screenful.

## Two secrets, two different problems

The Docker token authenticates `sbx` itself and belongs in the Keychain, fetched by `secret_get` like
the tailnet key. Read scope is enough. It never reaches `server.env` and never appears in argv.

The agent's own sign-in happens inside a sandbox with `/login`, and it is once — not once per
sandbox. The token it produces is stored on the host and injected into outbound requests by the
proxy, so it is never written inside a sandbox, the agent cannot read or exfiltrate it, and later
sandboxes are authenticated without signing in again. Destroying a sandbox does not cost you the
login.

An API key held as an `sbx` secret is the alternative, and there is no reason to reach for it here.
It is injected the same way, so it buys no isolation the subscription does not already have, and it
trades a flat subscription for metered billing. Use it only if you have a reason unrelated to this
machine.

One thing the published docs do not settle: whether a second sandbox re-prompts for `/login` or picks
the credential up silently. Everything about the design says silently — the token is host-side and
`sbx secret ls` lists OAuth entries alongside stored secrets — but Docker does not say so outright in
the get-started guide, the credentials page, the Claude Code or Droid agent pages, the FAQ, or the
release notes. Confirm it with a second sandbox on the first real server and fix this paragraph.

## What this buys, and what it costs

Bought: microVM isolation, a maintained egress policy, credential injection, and per-project
separation without a launcher of our own.

Cost, stated rather than buried. The agent layer now depends on a proprietary tool and a Docker
account, free today. The host layer deliberately does not, so the machine stays useful if that
changes. And the Mac now holds project source, where before it held none — `--clone` keeps the write
direction safe, but "the host holds nothing an agent wants" is less true than it was.
