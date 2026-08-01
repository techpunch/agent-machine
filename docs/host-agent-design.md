# Host + Agent-Sandbox Server Design

Status: proposed design / rationale. This document explains how a server is structured and why; the
step-by-step provisioning lives in the recipes under [`../recipes/`](../recipes/) — the host layer is
written, and the agent-VM layer carries contracts that land as scripts as they are built. The design,
the sandbox stack, and the container split are all settled. The scope is Claude Code and Codex; an
earlier version of this design also covered OpenClaw and Hermes, and several arguments here are
simpler for their absence.

## What this design is for

A single Mac mini that does two unrelated jobs at once, without letting the second job endanger the
first:

1. Run native apps that you want reachable from elsewhere (a local server, a GUI app you screen-share
   into), plus Tailscale so you can log in to the server and route traffic through it from a cafe.
2. Lend its spare compute to AI coding agents (Claude Code, Codex) running with permissions skipped,
   where a prompt injection or a bad dependency could turn an agent into an attacker.

The shape that satisfies both: a trusted host user owns the native apps and Tailscale, and an
isolated Linux VM owns the agents. The VM is the security boundary.

## Architecture

Naming: the Mac keeps whatever name it already had, adopted by `have-server-identity` and recorded as
`SERVER_NAME` — `<server>` below. The agents are the VM, so they carry the `agent` name, and the
machine that hosts them is `host`.

```
Mac mini (<server>) — macOS, FileVault off, auto-login
│
├─ host  (macOS admin user, the single auto-login GUI session)
│   │
│   ├─ Native apps that want to be network-reachable
│   │     started via Login Items / launchd in this session
│   │
│   ├─ Tailscale — host node "<server>"
│   │     • exit node: route your phone/laptop traffic through the server
│   │     • remote login: SSH + Screen Sharing over the tailnet
│   │     (GUI app, relaunched by a LaunchAgent — up once this
│   │      session logs in; SSH and Screen Sharing are system-level)
│   │
│   └─ Linux VM  — auto-started as a per-user LaunchAgent
│        │  isolation: no host mounts · fixed CPU/RAM · no inward network path
│        │
│        ├─ user "agent"
│        │
│        │  (not a tailnet node — see "The VM and the tailnet")
│        │
│        └─ Colima container runtime (Docker-compatible, no Docker Desktop)
│             └─ container: claude + codex  interactive CLIs, same trust tier
│                  └─ project workspaces: share a container within one
│                     trust tier; a new container when you cross a
│                     trust boundary (untrusted repo, or secrets to wall off)
```

## Components

### The `host` macOS user

`host` is a macOS admin user and the single user macOS auto-logs-in at boot. macOS only grants one
automatic GUI session, so the user that needs a real desktop (for GUI native apps and screen sharing)
has to be that user. Its login session is also what brings the whole stack back after a reboot.

`host` is an admin for simplicity: provisioning, system settings, Homebrew, and maintenance all want
admin, and this keeps the server to a single account. The accepted tradeoff is that this auto-login,
remotely reachable session runs at admin, so code that manages to run as `host` (via a compromised
native app or dependency) is one step from system-wide changes. That is tolerable here only because
the untrusted workload is not in this user at all — it is in the VM. If a server ever runs higher-risk
native software, revisit this by demoting `host` to a standard user and adding a separate
maintenance-only admin account; that change costs nothing at restart because the admin account runs
no always-on workload.

Native apps a server serves from macOS — a web server, a GUI app, anything that has to live outside
the VM — go in this session as a Login Item or LaunchAgent, reachable over Tailscale. There is no
recipe for that and there should not be: what to install is entirely specific to the server. When one
needs an app, write the recipe for that app. This layer is independent of the agent VM in both
directions — a server can have one, the other, or both.

### Tailscale on the host

The host runs Tailscale as the server's only node, `<server>`. It does two things:

- Exit node: you advertise the server as an exit node and approve it in the admin console, then select
  it from your laptop or phone to route traffic through the server (useful on untrusted cafe wifi).
- Remote login: SSH and Screen Sharing reach the server over the tailnet, so the server stays headless.

The remote-login services are system-level and root-owned — SSH via `systemsetup -setremotelogin`,
Screen Sharing via the ARD `kickstart` tool — so they serve the server regardless of who is logged in,
and a non-root process cannot reconfigure them.

Tailscale is not. `have-tailscale` installs the GUI cask and brings it back with a LaunchAgent in the
admin user's `gui/$uid` domain, so the tailnet comes up at login rather than at boot. In practice that
is fine, because auto-login runs immediately and unattended — but it means tailnet reachability
depends on the login session succeeding, which is why `make-auto-login` and the reboot-survival proof
in `make-headless` are load-bearing rather than ceremony. Anything that has to work strictly before
login cannot assume the tailnet, which is the constraint that shapes the key server in
`recipes/make-data-encrypted/recipe.md`.

### The agent VM (the isolation boundary)

All agents run inside one Linux VM, never directly on macOS. The VM is what makes "skip all
permission prompts" acceptable, because it gives a real boundary the host side does not:

- Separate kernel and filesystem: the agents cannot read the host's files, keychain, or credentials.
- Separate network stack: with NAT/user-mode networking, the agents cannot reach services the host
  has bound to its own localhost.
- A fixed CPU/RAM budget: a runaway or busy agent is bounded by the VM's allocation rather than
  taking the whole Mac down. On the reference server the VM gets 6 vCPUs and 10G of a 10-core, 16G
  Mac mini — most of the machine, with enough held back that macOS keeps working.
- Disposable: worst case, you rebuild the VM; the host is untouched.

The VM carries no mounts from the host, and its network policy allows the public internet while
denying every private range — the host, the LAN, and the tailnet — so a compromised agent can talk
outward but cannot pivot inward. That is `make-vm-network-bounded`, and it is what is actually built;
default-deny egress with an allowlist is a separate, tighter posture for proprietary work, discussed
below and deferred. It auto-starts as a per-user LaunchAgent in the `host` session, which is why it
does not need the host to be admin and why restart stays a single coherent login.

### The VM and the tailnet

The VM is not on the tailnet, and that is the deliberate choice rather than an unfinished one. It
follows directly from the network policy: `make-vm-network-bounded` denies `100.64.0.0/10` from
inside the VM precisely so a compromised agent cannot reach your laptop, the host, or any other
tailnet machine. A VM that both joined the tailnet and denied the tailnet range would be a node that
can reach no peers, so the two are mutually exclusive and the denial is the one that is built.

You therefore reach the agents through the host: SSH to the server over Tailscale, then
`colima ssh --profile agent`. One hop instead of none, and the isolation stays intact.

The alternative — the VM as its own tailnet node with its own tag, so ACLs could treat agent traffic
differently from the host's exit-node traffic — is not a recipe, because it is not a thing to do. It
would be worth revisiting only if something inside the VM had to be reachable from your other devices
directly, and taking it would mean carving specific peers out of the denial rather than dropping it.

### Containers inside the VM

The VM gives host-vs-agent isolation. Inside it, containers add a cheaper second boundary — and with
only Claude Code and Codex to run, the question of how to split them has a short answer: don't.

Claude Code and Codex share one container. Both are episodic Node-based CLIs holding the same kind of
subscription credential, so they are one trust tier and isolating them from each other buys little
while costing a second image to build and sign in to.

What containers are actually for here is the level below: projects. Same-trust projects share a
container; a project gets its own when it crosses a trust boundary — untrusted or third-party code, or
secrets you want walled off from your other work. That is the whole rule, and it is worth stating in
the form that generalises: a new container when you cross a trust boundary, not one container per
object.

This is a change from an earlier version of this design, which split containers by lifecycle to keep a
persistent, network-exposed daemon away from the interactive CLIs. With no such daemon in the stack,
that split has nothing left to separate.

### What sharing one agent container costs

Claude Code and Codex sharing a container is the design, not a compromise, but it is worth being
explicit about what it gives up so the trade is visible rather than assumed.

- No isolation between the two agents. One shared filesystem, environment, and network namespace
  means a prompt-injected or dependency-compromised agent can read and modify the other's config,
  working files, and auth — and with permissions skipped, nothing interrupts it.
- Credential concentration. Both subscription tokens sit together, so one container compromise costs
  you both rather than one.
- Muddier audit. Interleaved logs, processes, and outbound connections make it harder to attribute
  what either agent did.

What makes that acceptable: the two are genuinely one trust tier — same kind of credential, same
episodic CLI shape, same work — so a boundary between them would separate things that are not
meaningfully different, at the cost of a second image and a second sign-in. The VM is still doing the
real isolation, and the boundary that does earn its keep is the one below, between projects of
different trust.

The trade stops holding the moment an agent arrives with a credential you would not hand the other,
or a persistent network-exposed daemon joins the stack. Either is a reason to revisit this.

## Trust boundaries, in order

From outermost to innermost, each layer stops a different thing:

1. Host vs VM (the hypervisor): protects the native apps, host files, keychain, and host localhost
   services from the agents. This is the load-bearing boundary.
2. Trust tier vs trust tier (containers/workspaces): keeps an untrusted or secret-bearing project
   from reaching your other projects and their credentials.

Two boundaries, not three. The agents themselves are not separated from each other, because they are
the same trust tier; if that ever stops being true — a second agent with a credential you would not
hand the first — it becomes a third boundary again.

## Startup and restart

A reboot has to bring everything back unattended, in one sequence:

1. macOS auto-logs-in `host`.
2. The host session starts the native apps (Login Items / launchd) and Tailscale connects as
   `<server>`, re-advertising the exit node.
3. The VM auto-starts as a LaunchAgent in the host session.
4. Inside the VM, the network policy loads and the container runtime is ready. Nothing else starts on
   its own — agent runs are launched deliberately, not resumed.

Because it is all one login session plus per-user LaunchAgents, there is no boot-time
LaunchDaemon-without-a-session path to get wrong. A reasonable posture choice sits on top of this:
auto-start the sandbox, but launch interactive agent runs deliberately rather than firing an
autonomous agent unattended 24/7.

The one planned exception is `make-data-encrypted`, whose unlock has to run before the session exists
— agents cannot start until the data volume is mounted, so it cannot hang off login the way everything
else does. That is why it is a LaunchDaemon, and why its key fetch is held to needing nothing but
DHCP, DNS and a route. See `recipes/make-data-encrypted/recipe.md`.

## Agent authentication

The agents authenticate with subscriptions, not API tokens (a Claude Pro/Max plan and a ChatGPT
plan), so there are no static keys to drop into an env var for Claude Code and Codex. On a headless
VM that has consequences:

- Sign-in is the browser OAuth flow, completed over SSH. You run the login inside the VM
  (`claude /login`, and the equivalent for Codex); the CLI starts a localhost callback server and
  prints a URL. From your laptop you open an SSH tunnel to that port
  (`ssh -L <port>:localhost:<port> <server>` and forward on into the VM), open the printed
  `http://localhost:<port>/…` URL in your laptop browser, finish signing in, and the token is
  delivered back to the VM. No browser is needed on the server.
- You authenticate once, and it persists across restarts. Each agent stores its login as a credential
  file (Claude Code under `~/.claude`, Codex under `~/.codex`). Put that directory on a named volume,
  separate from the container image, and the login survives container restarts, VM reboots, host
  reboots, and image rebuilds. The OAuth refresh token silently renews the short-lived access token in
  the background, so the session stays alive with no interaction. A restart is not a re-auth event.
- Interactive re-auth is only needed when the refresh token itself is invalidated — long inactivity,
  a password change, or a "sign out everywhere." That is occasional and tied to security events, not
  to restarts, and it is the one time you repeat the SSH-tunnel login. A device-code flow that would
  remove the tunnel even then is requested but not yet available.
- Keep the credential on a mounted volume, never baked into the image (image layers can leak if the
  image is shared). In a headless Linux container the token is a plaintext file rather than in an OS
  keychain. Both tokens sit in the same container, since Claude Code and Codex share one — that is
  the accepted consequence of treating them as a single trust tier, and it means a compromise of that
  container costs you both subscriptions rather than one.
- Under the current network policy the sign-in flows just work, since everything outbound is allowed.
  If a workload is ever moved to default-deny egress, the allowlist has to permit the provider
  sign-in and API domains (Anthropic, OpenAI) and Tailscale, or both the login and the agents' own
  calls will be blocked.

This reinforces the startup posture above. Anthropic positions subscriptions for interactive use and
API keys for always-on automation, so holding only subscriptions argues for auto-starting the sandbox
but launching agent runs deliberately rather than running an autonomous agent unattended around the
clock — and for not pointing several servers at one subscription concurrently.

## Sandbox stack

The VM is managed by Colima — a lightweight Lima-based Linux VM with a built-in Docker-compatible
container runtime — so the server gets one capped, disposable VM and a container engine inside it without
Docker Desktop. What makes running with permissions skipped acceptable is the VM boundary plus the
network policy on it: out to the internet, nothing inward. Defining the VM as a committed Colima
profile (CPU/RAM cap, no host mounts) keeps a server reproducible and fits reusing this setup per
client.

Not used, and worth saying plainly because it comes up: Anthropic's reference devcontainer and its
`init-firewall.sh`. The agent image here is a plain `debian:trixie-slim` built from a committed
Dockerfile, and the network policy is nftables in the VM allowing all outbound and denying only the
private ranges. `init-firewall.sh` implements the opposite posture — default-deny with an allowlist —
which is `make-egress-restricted`, deferred. If that recipe ever gets built, the devcontainer's
allowlist is the obvious thing to seed it from. Until then nothing from it is in play.

### What this pulls in, and why each one

Every dependency is a thing you are trusting on a machine that runs agents with permissions skipped,
so the list is deliberately short and each entry has to beat the simpler alternative.

| | Source | Why not something simpler |
|---|---|---|
| Homebrew | official installer, `Homebrew/install` | The only sane way to get the rest on macOS |
| Tailscale | Homebrew cask, upstream signed app | The formula exists but the cask is what survives a reboot cleanly |
| Colima | Homebrew formula, MIT | This *is* the simple option: Docker Desktop is proprietary and licensed, UTM is a GUI pet-VM tool, raw Lima needs a container runtime bolted on |
| Lima's Ubuntu guest image | Canonical cloud image, via Colima | Colima's default; building our own buys nothing |
| Claude Code | `claude.ai/install.sh`, first-party | The native installer keeps Node out of the VM and the image entirely; the npm route would drag a runtime in |
| `debian:trixie-slim` | Docker Official Image | Alpine is smaller but musl, and the Claude Code binary targets glibc |
| apt packages | Debian and Ubuntu archives | — |

Two deliberate non-dependencies. There is no separate probe image: verify tests container egress
using the agent image and bash's `/dev/tcp`, because adding a second image to test the first is a
registry round-trip and a supply-chain entry for something bash already does. And there is no SSH
client in the agent image: clones are throwaway HTTPS and no key ever enters the VM, so it would be
surface without a use.

Nothing is pinned by digest. Tracking `trixie-slim` and current Homebrew formulae means rebuilds
pick up security updates, which matters more on a long-lived server than byte-identical rebuilds —
the reproducibility that is load-bearing here is the Colima profile and the recipes, both of which
are committed.

The cost of that choice is a thing nobody notices until it bites: a codename does not follow Debian
forward. This project was written against `bookworm-slim`, which went oldstable when trixie shipped
in August 2025 and left regular security support on 12 July 2026 — so for a while the agent image
was built on a release that only had LTS coverage. Tracking `stable` instead would have avoided that
and introduced a worse problem, silently jumping a major release mid-rebuild. Keep the codename,
and treat "is this still current stable?" as a real maintenance task rather than an assumption.

### Colima, and when UTM would be the answer instead

Colima is the default because it matches the goals above: headless, CLI-driven, defined as a committed
profile, and purpose-built to run Linux containers on macOS, so it auto-starts cleanly as a LaunchAgent
and rebuilds identically per server.

UTM is a different shape of tool — a GUI virtualization app with first-class snapshots and non-Linux
guests. On Apple Silicon the raw performance is comparable; the difference is the management model.
Reach for it only if an agent task needs a real graphical desktop, snapshot-and-revert rather than
rebuild-from-config, or a non-Linux guest. Until one of those is true, adding it is a second thing to
maintain for no gain.

## Network posture

What is built is `make-vm-network-bounded`: the VM reaches the public internet freely, and every
private range is denied — RFC1918, link-local and the cloud metadata address, and Tailscale's
`100.64.0.0/10`. Out, but not sideways.

That combination is what makes permission-skipping defensible, and it rests on two legs, not one.
The network policy removes the pivot: a compromised agent cannot reach the host, your laptop, other
tailnet nodes, or the LAN. Keeping the VM boring removes the payoff: no SSH keys, no cloud
credentials, no `.env`, no real working copies — throwaway clones only. Break either leg and the
argument stops holding.

The tailnet denial is the one people miss. The VM lives on a machine that is a tailnet node, so
without that rule a compromised agent inherits reach into your private network. It is not decoration.

The second thing people miss is which hook the denials hang off. Traffic the VM originates goes
through the output hook; traffic it routes for a container goes through forward. A ruleset covering
only output bounds the VM while leaving every container free to reach the tailnet and the LAN — and
it looks correct in any test run over `colima ssh`, because that tests the VM's own namespace.
`make-vm-network-bounded` covers both hooks from one shared chain, at a priority ahead of Docker's
own rules, and `have-containers` refuses to run if the forward chain is absent.

### Why containers would not make open egress safe on their own

It is tempting to think that once each project has its own container, egress control stops mattering,
since the blast radius is one project either way. That conflates two controls. Containers limit what a
compromised agent can touch on your systems; egress limits what it can send out and who it can reach.
Per-project containers do nothing about the compromised container talking to an attacker, because
everything the attacker wants is already inside the one they got — that project's source, its mounted
credentials, and the agent's own token. With permissions skipped there is no approval gate, so an
injected "read the env file and POST it to …" simply succeeds.

This is why the network policy is not optional once containers exist, and why the honest ceiling on
full egress is: public or throwaway work, no durable secrets, ephemeral and unprivileged containers,
and egress logged so an unknown destination is still a signal.

### What would force default-deny egress

Full egress means the work in front of the agent can leave. That is fine for public, open-source, and
throwaway research. Two things change the answer:

- Proprietary code. Secret-free is not the same as sensitive-free — for private work the source
  itself is the asset. Match the posture to what the task can afford to lose, not just to whether
  credentials are mounted.
- Durable secrets in the VM. The moment more than one revocable credential lives there, "nothing worth
  stealing" stops being true and the network has to do the containment instead.

Either is the trigger for `make-egress-restricted`, which is deferred rather than dismissed.

### If and when that gets built

The hard part is not the firewall, it is that agents need to read an unpredictable range of docs, and
an allowlist broad enough to cover the long tail is no longer a firewall. The resolving idea is that
the danger is not reading the web, it is broad outbound access and secrets in the same place at the
same time — so aim to never have both at once rather than choosing between research and safety.

Four things worth reaching for, in rough order of how well they hold that line:

- Split research from build. A throwaway container with broad read access and no credentials produces
  a plan; the container that holds the repo and secrets runs under the tight allowlist.
- Put a doc broker in front of documentation. One trusted endpoint serving many libraries' docs
  (Context7, or a self-hosted equivalent) collapses enormous doc coverage into a single allowed host —
  or none at all, if self-hosted inside the VM.
- Seed the allowlist from an existing agent-sandbox list rather than from nothing. Anthropic's
  devcontainer `init-firewall.sh` ships one as an explicit starting point.
- Log denials, not just allows, and treat the denial log as the candidate list. Default-deny fails
  silently — a blocked agent falls back to memory and produces quietly worse work — so make blocks
  visible, then confirm an unblock actually improved the output before making it permanent.

## Driving the setup

The day-to-day layer: how one person coordinates many in-flight projects across Claude Code and Codex
without hand-attaching a terminal to each one.

The decision, and it is not a placeholder: a persistent tmux or Zellij grid inside the agent VM, one
pane per project, plus the native phone bridges. SSH to the server over Tailscale from the Mac,
`colima ssh --profile agent`, and attach to that one session. On the phone, Claude Code Remote Control
and the Codex/ChatGPT app drive a specific session — no new infrastructure, and the code never leaves
the VM.

Why this rather than an orchestrator. The people running this at volume — Steinberger with a 3×3
terminal grid, Willison with a grid of plain terminals across repos — agree on the bottleneck, and it
is not spawning or coordinating agents, it is how fast you can review what they produce. Tooling that
does not move that needle gets discarded, and both of them explicitly rejected the wrapper apps for
hiding what the model is doing. Adopt a worktree board (an OSS one, in the VM) only when reading diffs
across many tasks is the thing that hurts. Not before.

Two other options exist and are deliberately not the default. Cloud delegation — Codex cloud, Claude
Code on web — is the lowest-friction way to fire a task from a phone, at the cost of the code and
context leaving your server; reasonable for well-scoped work you are comfortable running off-server.
And a chat-app dispatcher, of which OpenClaw is the best-known, is the most phone-native option of all;
it is out because it means running a persistent, network-exposed daemon, which is a real component to
secure rather than a convenience. Both are additions to make deliberately, not things to drift into.

On multiplexers specifically: what this server needs is server-side persistence, not client-side
layout. Agent processes have to keep running while you detach, disconnect, or move from Mac to phone.
Ghostty's native splits are ephemeral and do not provide that, so tmux or zellij runs in the VM and
Ghostty is simply a good client to attach with. Ghostty's in-progress tmux control-mode integration and
its remote-session proof-of-concept would change this if they ship; worth tracking, not worth waiting
for.

### How this fits the rest of the design

Everything in this layer runs inside the agent VM, so no matter how the grid is arranged or how many
tasks are in flight, the host, its native apps, and its credentials stay behind the VM boundary. The
coordination layer adds no exposure of its own — a multiplexer and two vendor bridges, none of which
opens a port.

The two surfaces divide the work rather than competing. The grid is where you review and steer: attach,
read diffs, interrupt. The native bridges take direct control of one session from the phone, which is
for nudging something already running rather than surveying everything at once.

Autonomy and the sandbox. The reason you can let an agent run to completion is the boundary work
already in this design: the VM plus the network policy contain an agent acting on a bad instruction,
and per-trust-tier containers keep a compromised project out of the others. The coordination layer is
where you exercise the autonomy dial; the sandbox is what makes exercising it sane.

### Sources

- [Peter Steinberger — Just Talk To It](https://steipete.me/posts/just-talk-to-it)
- [Simon Willison — Embracing the parallel coding agent lifestyle](https://simonwillison.net/tags/parallel-agents/)
  and [Claude Code Remote Control](https://simonwillison.net/2026/Feb/25/claude-code-remote-control/)
- [Claude Code — Remote Control](https://code.claude.com/docs/en/remote-control) and
  [Agent Teams](https://code.claude.com/docs/en/agent-teams)
- [OpenAI Codex — Cloud](https://developers.openai.com/codex/cloud) and
  [using Codex from the ChatGPT app](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan)
- [opencode — server/clients](https://opencode.ai/docs/server/)
- [Mike Mason — Coherence Through Orchestration, Not Autonomy](https://mikemason.ca/writing/ai-coding-agents-jan-2026/)
- Ghostty: [SSH features](https://ghostty.org/docs/features/ssh) and the native-remote-sessions
  proof-of-concept ([discussion #11891](https://github.com/ghostty-org/ghostty/discussions/11891));
  context on splits vs. tmux persistence in [Replacing tmux with Ghostty](https://sterba.dev/posts/replacing-tmux/)

## What is left to pin

Settled and needing no further design work: the naming scheme (a server keeps its own name, and the
host is the only tailnet node, tagged `tag:host`), the container split (one container for Claude Code
and Codex, a new one per trust boundary), the network posture (out but not sideways), and the
coordination layer (tmux grid plus native phone bridges).

Genuinely open, and only these:

- Whether 6 vCPUs, 10G and 100G is the right shape. `have-agent-vm` uses those as defaults, clamped
  so a smaller machine still gets a workable VM, on the assumption that the server is dedicated to
  agents. It has not been watched under a real workload yet, and memory is the one to check first
  since `vz` reserves it rather than ballooning.
- Codex sign-in ergonomics: the SSH-tunnel runbook again, this time inside the container.

Unbuilt, each with a recipe carrying its `blocked_by`: `have-agent-auth` adds Codex alongside Claude
Code; `make-egress-restricted` waits on proprietary code or a durable secret entering the VM;
`make-data-encrypted` needs a real server to build against.
