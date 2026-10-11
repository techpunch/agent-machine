---
name: have-agent-sandbox
summary: Docker Sandboxes installed and signed in, so agents run in a microVM and never on macOS.
requires: [have-homebrew]
needs: [docker-account, anthropic-account, openai-account]
root: no
gates: the Docker personal access token
---

The layer agents run on. `sbx` runs an agent in a microVM with its own kernel, filesystem, Docker
daemon and network, and routes its outbound traffic through a proxy on the Mac — which is also what
injects the agents' sign-ins, so a sandbox can use them without ever holding them.

This recipe installs `sbx`, signs it in to Docker, sets its network policy once, and turns off one
default that would undo the rest. The sandbox the agents actually run in is
[`have-shared-sandbox`](../have-shared-sandbox/recipe.md); the GitHub token they push with is
[`join-github`](../join-github/recipe.md).

This replaced a hand-built Colima VM, an nftables ruleset and a container launcher. The reason is not
that those could not work — it is that they were security-critical code with nobody but us reviewing
them, and three real defects surfaced in a single pass: a firewall that filtered only locally
originated traffic so every container bypassed it, a verify that tested the wrong network namespace
and therefore always passed, and a container tier that could not authenticate. `sbx` is maintained,
and it does one thing Colima cannot do at all: keep a credential usable but unreadable. The full
comparison is in [`../../docs/host-agent-design.md`](../../docs/host-agent-design.md).

## What apply sets

- `sbx`, from Docker's Homebrew tap.
- The Docker sign-in, from a personal access token in the Keychain. sbx has no command that reports
  who is signed in, so apply signs in every run — `--password-stdin` is idempotent — and verify
  proves it by creating and removing a throwaway sandbox.
- The network policy preset, once. `policy init` is one-time by design; `sbx policy reset` starts
  over and stops running sandboxes.
- SSH agent forwarding off. sbx forwards the host's SSH agent into every sandbox unless
  `ssh.agentForwardingEnabled` is `false`, and on this machine that agent is whatever you brought with
  `ssh -A` — so any process in the sandbox could ask your laptop's keys to sign. Apply turns it off
  and restarts the daemon; verify checks it stays off.

## The network policy

Set once and recorded as `SBX_POLICY`. `allow-all` is the default here, and that is a decision rather
than a shortcut: what this machine protects is the Mac, not the network, and agents have to be able to
read any documentation site. Under a deny-by-default preset they cannot, and a blocked agent falls
back to memory and writes confidently outdated code. The reasoning is in
[`../../docs/secrets-and-egress.md`](../../docs/secrets-and-egress.md).

What `allow-all` gives up is control over where data goes. Anything in the sandbox — the source of
every project in it — can be sent anywhere. That is accepted, and it is why nothing that would hurt to
leak belongs in the sandbox at all.

What it must not give up is the wall around the Mac, and `allow-all` alone does give it up. The
preset is the rule `sbx policy allow network "**"`. Docker's docs used to say private ranges,
loopback and the host network were blocked whatever the policy; a docs change in August 2026
(docker/docs#25819) took that out, and the list of things blocked regardless of policy is now the
host filesystem, the host Docker daemon, sandbox-to-sandbox traffic and external UDP and ICMP. A
sandbox reaches services on the Mac through `host.docker.internal`, which the proxy turns into
`localhost` and governs like any other destination — Docker's own Ollama kit opens it with an allow
rule. And the Mac's LAN and tailnet addresses are private addresses like any other. This Mac's sshd
answers on all three.

So apply adds deny rules, which outrank every allow, `**` included: `localhost`, `127.0.0.0/8`,
`host.docker.internal`, the three RFC 1918 ranges, link-local `169.254.0.0/16`, the tailnet's
`100.64.0.0/10`, and IPv6 loopback, unique-local and link-local. The internet stays open; the Mac and
the LAN do not. Docker's rule syntax takes IPv4 and IPv6 ranges alike. It refuses a deny that repeats
an allow for the very same resource ([#610](https://github.com/docker/sbx-releases/issues/610)), which
these are not.

Verify does not trust `sbx policy check` for this — it has reported a host deny rule the proxy then
did not enforce ([docker/sbx-releases#546](https://github.com/docker/sbx-releases/issues/546)) — so it
tries the Mac's SSH from inside the probe sandbox by `host.docker.internal`, the LAN address, the
tailnet address, and `<lan-address>.sslip.io`, a public name that resolves to the LAN address. That
last one is there because nothing Docker publishes says a range rule applies to a hostname that
resolves into it, and one user had to allow an address as a range, a bare address and an
address-with-port before it matched ([#59](https://github.com/docker/sbx-releases/issues/59)). If it
answers, the deny rules do not cover names, and there is no fix in this recipe to reach for — say so.

Denying `localhost` does not stop an agent testing its own dev server. The sandbox sets
`no_proxy=localhost,127.0.0.1,::1` (visible in #59), so loopback traffic inside the sandbox never
reaches the proxy whose rules these are. Not yet seen on a real server: that the rules hold, and that
denying `localhost` breaks nothing sbx itself needs.

`SBX_POLICY=balanced` on a first run picks the stricter preset instead: AI providers, package
managers, code hosts and registries only. Under it, a destination no rule covers is held for
approval — `sbx policy approval ls`, then `sbx policy approval respond <id> --option allow` — and
`./bin/cookbook denials` shows both what was blocked and what is waiting. Worth it for work whose
source is itself the thing to protect; not the default here.

## Codex as well as Claude Code

Both run in the same sandbox. Three differences worth knowing:

- The sign-in starts on the host rather than inside the sandbox. `sbx secret set openai --oauth`
  opens a browser on the machine you run it on, which on a headless server means screen sharing or
  an SSH tunnel — see [`../../prereqs/openai-account.md`](../../prereqs/openai-account.md). Claude Code's `/login` is
  typed inside the sandbox and reaches the host from there. Both end the same way: tokens in the host
  keychain, injected by the proxy, never written inside a sandbox.
- Bypass mode is a flag you type, or an alias. `sbx run codex` adds
  `--dangerously-bypass-approvals-and-sandbox` for you, but agents here are started from a shell in a
  tmux pane, which adds nothing — so the kit aliases `codex` and `claude` to include their flags.
- `~/.codex` does not follow it in, exactly as `~/.claude` does not.

There is one sandbox and every agent runs in it, but `sbx create` still takes an agent name. The name
picks a kit — the image, the default command, where guidance goes, and which sign-ins the proxy
handles — and the sandbox is created as `claude`, which brings Claude Code and its `/login` and
nothing for Codex. It has to be `claude`: a kit under any other name that declares the same
Anthropic sign-in does not get it injected, and a Docker maintainer said that may stay so "due to
legal reasons around their subscription model"
([docker/sbx-releases#270](https://github.com/docker/sbx-releases/issues/270)). So the kit below adds
Codex: it installs it, and declares the OpenAI sign-in the same way Docker's codex kit does. sbx has
supported several OAuth-signed-in agents in one sandbox since v0.45.0, and a mixin declaring a
credential no longer knocks Claude Code's subscription sign-in into API-key mode since the release
after v0.43 ([#344](https://github.com/docker/sbx-releases/issues/344)).

## The kit

`kit/spec.yaml` beside this recipe is a schema-v2 mixin layered on the built-in `claude` agent. It
carries:

- Codex: installed with the line from Docker's codex Dockerfile, its OpenAI sign-in declared with the
  `credentials` block from Docker's codex kit, and its config seeded the way that kit seeds it. The
  OAuth block is what keeps the real token on the Mac — the sandbox only ever sees sentinels.
- tmux and its config (`kit/files/home/.tmux.conf`) for the grid, and `claude` and `codex` aliased
  to start in bypass mode from a shell.
- An update at every sandbox start, in the background: `claude update`, and Codex's installer run
  again — which is what `codex update` does, called directly so the flags are explicit. The image
  was current only on the day it was pulled, and the sandbox lives for months.
- `GIT_TERMINAL_PROMPT=0`, from Docker's codex kit, so a push GitHub refuses fails and says so
  instead of git waiting at a username prompt nobody will answer.
- What every agent here should be told, in `kit/files/home/.codex/AGENTS.md`: clone into the home
  directory, push branches, never `main`, leave the Mac and private ranges alone, and — for a preset
  stricter than `allow-all` — report a blocked request rather than work around it. Codex reads that
  file as its global instructions, and `kit/files/home/.claude/CLAUDE.md` imports it for Claude Code,
  so there is one copy and both agents get it.
- A starter documentation allowlist, which only matters under a stricter preset.

The Codex parts are copied rather than written, from
[docker/sbx-kits-contrib](https://github.com/docker/sbx-kits-contrib) `codex/spec.yaml` and
`codex/Dockerfile`. When that kit changes, compare against it.

Because the kit is not built into sbx, sbx uses a credential it declares only with an approved
binding in `~/.config/sbx/credentials.yaml`, and with nobody at the screen it withholds the
credential silently rather than ask. `have-shared-sandbox` writes that binding before it creates the
sandbox, which is what Docker documents for unattended runs.

It is a kit rather than your Mac's own `~/.claude/CLAUDE.md` because sandboxes inherit nothing from
the host, and because a kit is a committed file, so it is reviewable in this repo instead of living in
one machine's local state. The guidance is plain files rather than the kit's `agentInstructions`
field because that field writes beside the profile sbx generates next to a mounted workspace, and this
sandbox mounts none; and Codex does not read that profile at all
([docker/sbx-releases#567](https://github.com/docker/sbx-releases/issues/567)).

Loading it from a path in this repo is fine. Remote kit sources are allowlisted to Docker Hub by
default under `kit.allowedSources`, but local directories are governed separately by
`kit.allowLocalKits`, which defaults to true. A relative kit path has to start with `./` or `../` — a
bare one is read as an agent or kit name. `sbx kit add` cannot apply this kit to an existing sandbox:
it takes only environment variables, install steps and network allows, and this kit has a
credential and a startup step. A changed kit means recreating the sandbox.

## Making a denial loud

Only matters under a preset other than `allow-all`. A blocked request is not silent at the wire.
Refused outright, the proxy returns:

```
HTTP/1.1 403 Forbidden
Blocked by network policy: domain example.com:443
detail: no matching allow rule — blocked by default deny policy
```

and held for approval, the sandbox gets:

```
Approval required for example.com.

Review and respond with:
  sbx policy approval ls
```

Both name the domain and neither looks like a `404`. The problem is what an agent does with it:
routing around it and answering from memory reads as a confident answer and is often wrong. The kit
tells the agent to stop and name the domain, and `./bin/cookbook denials` asks the proxy instead of
the agent, which also catches denials from build scripts and package managers that never surface as
an agent tool call.

## The secrets, and where each lives

- The Docker token authenticates `sbx` itself and belongs in the Keychain, fetched by `secret_get`
  like the tailnet key. Read scope is enough. It never reaches `server.env` and never appears in argv.
- The agents' sign-ins are once, not once per sandbox. Claude Code does it inside the sandbox with
  `/login`; Codex does it on the host with `sbx secret set openai --oauth`. The token is stored on the
  host and injected into outbound requests by the proxy, so it is never written inside a sandbox and
  the agent cannot read or exfiltrate it. Destroying the sandbox does not cost you the login.
- The GitHub token is the same mechanism, stored with `sbx secret set github` — see
  [`join-github`](../join-github/recipe.md).

An API key held as an `sbx` secret is the alternative to a subscription, and there is no reason to
reach for it here. It is injected the same way, so it buys no isolation the subscription does not
already have, and it trades a flat subscription for metered billing.

Sandbox disks default to 20 GB, `DOCKER_SANDBOXES_DOCKER_SIZE` covers the separate Docker data disk,
which defaults to 10 GB since v0.42, and both are read when a sandbox is created. `have-shared-sandbox`
creates its one sandbox larger, because it holds every project.

## What this buys, and what it costs

Bought: a microVM between every agent and the Mac, sign-ins that are usable but never readable, and no
security code of our own to maintain.

Cost, stated rather than buried. The agent layer depends on a proprietary tool and a Docker account,
free today. The host layer deliberately does not, so the machine stays useful if that changes. And
`sbx` moves fast — several releases between v0.42 and v0.47 changed commands this recipe used — so
`/update` checks it. This file was last checked against v0.47.0.
