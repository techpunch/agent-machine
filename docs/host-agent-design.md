# Host and agent server design

Why a server is put together this way. The step-by-step lives in the recipes under
[`../recipes/`](../recipes/); this is the reasoning behind them.

The scope is Claude Code and Codex. Earlier versions of this design also covered OpenClaw and Hermes,
and built the agent layer out of a hand-configured Colima VM with its own firewall rules and
container split — both are gone, and several arguments here are simpler for it.

## What this design is for

A single Mac that does two unrelated jobs at once, without letting the second endanger the first:

1. Run things you want reachable from elsewhere — a local server, a GUI app you screen-share into —
   plus Tailscale, so you can log in from anywhere and route traffic through it from a cafe.
2. Lend its spare compute to coding agents running with permissions skipped, where a prompt injection
   or a bad dependency could turn an agent into an attacker.

The shape that satisfies both: a trusted host user owns the native apps and Tailscale, and agents run
in microVMs that own nothing. The microVM is the security boundary.

Two priorities shape the rest, and they are worth stating because they rule things out. The pivot
this design cares about most is the tailnet: the server is itself a node, so an agent that gets
network reach would inherit a path to your laptop and everything else on it, which is why egress
being blocked at the network layer matters more here than on an ordinary dev box. And running on a
Claude subscription rather than an API key is a first-class requirement, not a preference — a setup
that is annoying to sign in to is one you stop using, and the friction would be paid on every
project forever.

## Architecture

The Mac keeps whatever name it already had, adopted by `have-server-identity` and recorded as
`SERVER_NAME` — `<server>` below.

```
Mac (<server>) — macOS, FileVault off, auto-login
│
├─ host  (macOS admin user, the single auto-login GUI session)
│   │
│   ├─ Native apps that want to be network-reachable
│   │     started via Login Items / launchd in this session
│   │
│   ├─ Tailscale — the server's only node, "<server>"
│   │     • exit node: route your phone/laptop traffic through the server
│   │     • remote login: SSH + Screen Sharing over the tailnet
│   │     (GUI app, relaunched by a LaunchAgent — up once this
│   │      session logs in; SSH and Screen Sharing are system-level)
│   │
│   ├─ tmux grid — one pane per project, survives you detaching
│   │
│   └─ sbx (Docker Sandboxes)
│        └─ one long-lived microVM per project
│             • own filesystem, own Docker daemon, own network
│             • all egress through a host-side proxy under policy
│             • --clone: read-only view of the repo, work fetched back out
```

## Components

### The `host` macOS user

`host` is a macOS admin user and the single user macOS auto-logs-in at boot. macOS only grants one
automatic GUI session, so the user that needs a real desktop — for GUI apps and screen sharing — has
to be that user. Its login session is also what brings the whole stack back after a reboot.

`host` is an admin for simplicity: provisioning, system settings, Homebrew and maintenance all want
admin, and this keeps the server to a single account. The accepted tradeoff is that this auto-login,
remotely reachable session runs at admin, so code that manages to run as `host` is one step from
system-wide changes. That is tolerable only because the untrusted workload is not in this user at all
— it is in a sandbox. If a server ever runs higher-risk native software, revisit by demoting `host`
to a standard user and adding a maintenance-only admin account; that costs nothing at restart,
because the admin account runs no always-on workload.

Native apps a server serves from macOS go in this session as a Login Item or LaunchAgent, reachable
over Tailscale. There is no recipe for that and there should not be: what to install is entirely
specific to the server. This layer is independent of the agent layer in both directions — a server
can have one, the other, or both.

### Tailscale on the host

The host runs Tailscale as the server's only node. It does two things: advertises the server as an
exit node so you can route traffic through it from untrusted wifi, and carries SSH and Screen Sharing
so the machine can stay headless.

The remote-login services are system-level and root-owned — SSH via `systemsetup -setremotelogin`,
Screen Sharing via the ARD `kickstart` tool — so they serve the server regardless of who is logged
in, and a non-root process cannot reconfigure them.

Tailscale is not. `have-tailscale` installs the GUI cask and brings it back with a LaunchAgent in the
admin user's `gui/$uid` domain, so the tailnet comes up at login rather than at boot. In practice
that is fine, because auto-login runs immediately and unattended — but it means tailnet reachability
depends on the login session succeeding, which is why `make-auto-login` and the reboot-survival proof
in `make-headless` are load-bearing rather than ceremony. Anything that has to work strictly before
login cannot assume the tailnet, which is the constraint that shapes the key server in
`recipes/make-data-encrypted/recipe.md`.

### The agent sandbox

Agents run in microVMs managed by `sbx`, never on macOS directly. That boundary is what makes "skip
all permission prompts" acceptable, because it gives something the host side cannot:

- A separate kernel and filesystem, so an agent cannot read the host's files, Keychain or credentials.
- A network it does not control: all egress goes through a proxy on the host that enforces a
  deny-by-default policy, and non-HTTP protocols are blocked outright. The host, localhost services
  and private ranges are unreachable — including the tailnet, which is the pivot this design worried
  about most, since the server is itself a tailnet node.
- Disposability. Worst case you delete the sandbox; the host is untouched.

This replaced a hand-built Colima VM, an nftables ruleset and a container launcher. Not because those
could not work, but because they were security-critical code with nobody but us reviewing them, and
three real defects surfaced in a single pass — a firewall that filtered only locally-originated
traffic so every container bypassed it, a verify that tested the wrong network namespace and
therefore always passed, and a container tier that could not authenticate. A maintained tool with a
stricter default posture is the better trade.

The cost, stated rather than buried: the agent layer now depends on a proprietary tool and a Docker
account, free at time of writing. The host layer deliberately does not, so the machine stays useful
if that changes.

### Which `~/.claude` is which

Two of them, and "where is my sign-in" has two answers.

| Where | Path | Signed in |
|---|---|---|
| Host Mac | the admin user's `~/.claude` | for cookbook work only |
| Sandbox | inside the microVM | `/login`, once, from any sandbox |

The host one is the session you run `/setup` from and it never touches the other. That is not just
isolation, it is literal: sandboxes inherit nothing from the host's `~/.claude`, and they share no
home directory with each other either.

The sign-in is the exception, and it goes the other way from what you would expect. `/login` is typed
inside a sandbox, but the resulting session token is stored on the host and injected into outbound
requests by the proxy — it is never written inside the sandbox at all. So the agent can make
authenticated calls and cannot read, log or exfiltrate the credential, and every later sandbox is
authenticated without signing in again.

That is what makes the subscription the recommended path rather than an API key. It is less work and
less exposure at the same time, which is rare enough to say plainly.

It is also why per-sandbox defaults come from a kit rather than a dotfile: a committed `spec.yaml`
travels with the repo, where a host-side config would not reach the sandbox at all.

## Trust boundaries, in order

1. Host vs sandbox (the hypervisor): protects the native apps, host files, Keychain and host
   localhost services from the agents. This is the load-bearing boundary, and the only one this
   design would pay anything to keep.
2. Sandbox vs sandbox: each project gets its own microVM and network, so an untrusted project cannot
   reach another project's files or listening ports. Direct network communication between sandboxes
   is blocked and cannot be re-enabled by policy.

The second one is not a goal here, it is a byproduct, and the distinction matters for what you should
do when it gets in the way. Projects on this machine belong to one person at one trust level, so
separating them was never the point. It is worth keeping only because it costs nothing: the sign-in
is held on the host, so ten sandboxes are no more setup than one. If sharing ever turns out to be
simpler for some piece of work, mounting several directories into one sandbox is supported and is the
right answer — the boundary worth defending is the first one.

## Startup and restart

A reboot has to bring everything back unattended, in one sequence:

1. macOS auto-logs-in `host`.
2. The host session starts the native apps and Tailscale connects, re-advertising the exit node.
3. That is all that needs to happen automatically.

Agent sandboxes are deliberately not restarted. They persist as objects, but bringing them up
automatically would mean auto-starting agent runs. The posture is to bring the machine back
unattended but launch agent work by hand. What has to survive a reboot is the machine and the work —
and the work survives because it is pushed or fetched out of a sandbox, not because the sandbox
persists. See [`pushing-agent-code.md`](pushing-agent-code.md).

The one planned exception is `make-data-encrypted`, whose unlock has to run before the session
exists. That is why it is a LaunchDaemon and why its key fetch is held to needing nothing but DHCP,
DNS and a route.

## What this pulls in, and why each one

Every dependency is something you are trusting on a machine that runs agents with permissions
skipped, so the list is deliberately short and each entry has to beat the simpler alternative.

| | Source | Why not something simpler |
|---|---|---|
| Homebrew | official installer, `Homebrew/install` | The only sane way to get the rest on macOS |
| Tailscale | Homebrew cask, upstream signed app | The cask is what survives a reboot cleanly |
| Docker Sandboxes | Homebrew tap, Docker Inc | Proprietary, but a maintained boundary beats a hand-written one |
| tmux | Homebrew | A multiplexer is the smallest thing that outlives an SSH connection |

Nothing is pinned by digest. Tracking current versions means updates arrive, which matters more on a
long-lived server than byte-identical rebuilds — the reproducibility that is load-bearing here is the
recipes, which are committed. `./bin/cookbook stale` reports what has drifted, and `/update`
researches the questions it cannot answer from the machine.

## Driving the setup

The day-to-day layer: how one person coordinates many in-flight projects without hand-attaching a
terminal to each one.

The decision, and it is not a placeholder: a persistent tmux grid on the server, one pane per
project, plus the native phone bridges. SSH in over Tailscale and attach to that one session; each
pane runs `sbx run --clone <agent>`. On the phone, Claude Code Remote Control drives a specific
session — no new infrastructure, and execution stays on the server.

Why this rather than an orchestrator. The people running this at volume — Steinberger with a 3×3
terminal grid, Willison with a grid of plain terminals across repos — agree the bottleneck is not
spawning or coordinating agents, it is how fast you can review what they produce. Tooling that does
not move that needle gets discarded, and both explicitly rejected the wrapper apps for hiding what
the model is doing. Adopt a worktree board only when reading diffs across many tasks is the thing
that hurts. Not before.

Deliberately absent: a dispatcher that takes a request from a chat app and routes it to an agent
unattended. That is the natural next thing to want, and it is the point at which this stops being a
grid you supervise and becomes a system acting on messages from outside. Adding one means adding a
network-exposed daemon, and the design should be revisited rather than extended.

### Sources

- [Peter Steinberger — Just Talk To It](https://steipete.me/posts/just-talk-to-it)
- [Simon Willison — Embracing the parallel coding agent lifestyle](https://simonwillison.net/tags/parallel-agents/)
- [Claude Code — Remote Control](https://code.claude.com/docs/en/remote-control)
- [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) and its
  [default security posture](https://docs.docker.com/ai/sandboxes/security/defaults/)

## What is left to pin

Settled: the naming scheme, the host layer, the network posture (sbx's policy rather than ours), and
the coordination layer.

Genuinely open:

- How much the `balanced` allowlist has to grow in practice. It covers AI provider APIs, package
  managers, code hosts and registries — the agent works and dependencies install — but not
  documentation sites, so research is denied by default. Whether that settles into a handful of
  added domains, a doc broker, or a wider policy for research sandboxes is a first-run finding. See
  "Research versus containment" in [`secrets-and-egress.md`](secrets-and-egress.md).

Deferred by scope, with a recipe carrying its `blocked_by`: `make-data-encrypted` needs a real server
to build against, and `have-native-apps` is server-specific by nature.
