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
this design cares about most is the tailnet: the server is itself a node, so anything that gets
network reach on it would otherwise inherit a path to your laptop and everything else you own. And
running on a Claude subscription rather than an API key is a first-class requirement, not a
preference — a setup that is annoying to sign in to is one you stop using, and the friction would be
paid on every project forever.

The tailnet pivot is closed twice over, deliberately, because the two mechanisms fail for unrelated
reasons. Sandbox egress blocks private ranges, so agent code cannot reach the tailnet from inside.
And the tailnet policy names no rule with `tag:host` as a source, so the server cannot open a
connection to any device you own even from the host, even as root, even if every other control here
has failed. Traffic goes one way: you reach the server, the server reaches nothing.

The second one is the stronger control and it is worth being clear why. Tailscale enforces ACLs on
the receiving device, so it is the only protection in this design that the server does not
administer — a fully compromised host cannot switch it off. It also covers the host itself, which is
exactly where the sandbox contributes nothing, and it bounds what someone gets by walking off with a
machine that runs FileVault off and auto-login on.

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

Both are inbound. The server never needs to open a connection to a device you own, and the tailnet
policy in `shared-setup.md` says so explicitly by naming no rule with `tag:host` as a source. That
asymmetry is free — it costs nothing this cookbook does, and ACLs govern traffic between tailnet
devices rather than a machine's ordinary internet access, so the server still reaches the internet
exactly as before.

The exit node is the honest exception, and it does not go away. Routing your traffic through the
server means the server handles your traffic — that is what an exit node is. TLS protects contents;
hostnames, DNS lookups, timing and volume are visible to whoever controls the machine. There is a
real tension between advertising this box as an exit node and treating it as potentially
compromised, and no policy resolves it. Decide which one you mean.

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
  and private ranges are unreachable — including the tailnet and the LAN the server sits on. The
  tailnet policy blocks the same pivot independently, so this is the inner of two layers rather than
  the only one; the LAN is where it is the only one.
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
project. SSH in over Tailscale and attach to that one session; each pane runs
`sbx run --clone <agent>`, which attaches you to the agent directly, so a pane is a session and
there is nothing to connect to per project. From the phone it is the same command from an SSH client.

The agents' own remote-control features sit beside this rather than replacing it, and for the same
reason in both cases: each drives one session, where the grid surveys every project. Claude Code's is
no longer ruled out — sbx v0.39.0 added a `claude.remoteControl` setting that lets
`/remote-control` reach an agent in a sandbox, though its inbound half is still unreliable. Codex
Remote never had the proxy problem and has a worse one: it is set up from the ChatGPT desktop app,
which a headless server cannot present, and it drives Codex on the host rather than in a sandbox. Its
SSH-host mode is the one that matches this design, and it is untried.
[`have-coordination`](../recipes/have-coordination/recipe.md) carries both, with the commands.

Why this rather than an orchestrator. The people running this at volume — Steinberger with a 3×3
terminal grid, Willison with a grid of plain terminals across repos — agree the bottleneck is not
spawning or coordinating agents, it is how fast you can review what they produce. Tooling that does
not move that needle gets discarded, and both explicitly rejected the wrapper apps for hiding what
the model is doing. Adopt a worktree board only when reading diffs across many tasks is the thing
that hurts. Not before.

Why tmux specifically, since this category churns fast and the question keeps coming back. The
alternatives were compared against three requirements this machine actually has, and each fails one
structurally rather than narrowly:

| | Survives disconnect | Headless server | Works with `--clone` |
|---|---|---|---|
| tmux | yes | yes | yes |
| Zellij | yes | yes | Codex scrollback broken over SSH |
| cmux, Zentty | no | no | — |
| claude-squad, workmux, NTM | yes | yes | no — git worktrees |
| Conductor, Nimbalyst, Vibe Kanban | no | no | — |

cmux and Zentty are native macOS apps with no detach or reattach at all; both their own docs say to
keep tmux if sessions must survive an SSH disconnect, and this server has no GUI session to render
into. Zellij is a genuine peer — persistent, SSH-capable, better ergonomics — but has open scrollback
defects with agent TUIs over SSH, including the Termux path, and this repo's scope covers Codex as
well as Claude Code. The agent managers isolate work with a git worktree per agent, and `sbx` rejects
`--clone` from anywhere but the main checkout, so their isolation mechanism and ours cannot both run;
theirs is also the weaker one, since a worktree is not a microVM. The desktop review apps assume a
machine you look at.

So tmux stays, and it stays for a reason that will not move: the requirement doing the eliminating is
headless-plus-SSH-plus-sbx-owns-isolation, which is the shape of this design rather than a taste.

Deliberately absent: a dispatcher that takes a request from a chat app and routes it to an agent
unattended. That is the natural next thing to want, and it is the point at which this stops being a
grid you supervise and becomes a system acting on messages from outside. Adding one means adding a
network-exposed daemon, and the design should be revisited rather than extended.

### Sources

- [Peter Steinberger — Just Talk To It](https://steipete.me/posts/just-talk-to-it)
- [Simon Willison — Embracing the parallel coding agent lifestyle](https://simonwillison.net/tags/parallel-agents/)
- [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) and its
  [default security posture](https://docs.docker.com/ai/sandboxes/security/defaults/)
- [Remote Control inside sandboxes](https://github.com/docker/sbx-releases/issues/8) — why `/rc` did
  not reach a sandboxed agent, and
  [sbx v0.39.0](https://github.com/docker/sbx-releases/releases/tag/v0.39.0), which added the
  setting that lets it
- [Codex Remote connections](https://developers.openai.com/codex/remote-connections) — the desktop
  app requirement, and the SSH-host mode that is the only one shaped like this machine

## What is left to pin

Settled: the naming scheme, the host layer, the network posture (sbx's policy rather than ours), and
the coordination layer.

Genuinely open:

- How much the `balanced` allowlist has to grow in practice. It covers AI provider APIs, package
  managers, code hosts and registries — the agent works and dependencies install — but not
  documentation sites, so research is denied by default. Whether that settles into a handful of
  added domains, a doc broker, or a wider policy for research sandboxes is a first-run finding. See
  "Research versus containment" in [`secrets-and-egress.md`](secrets-and-egress.md).

Three smaller questions are open only because the answers are not published anywhere, rather than
because the design is undecided. Each is one command on a real server:

- Whether a second sandbox re-prompts for `/login` or picks the host-held credential up silently.
  Everything about the design says silently. Docker does not say so outright in the get-started
  guide, the credentials page, the Claude Code or Droid agent pages, the FAQ, or the release notes.
- Whether turning on `claude.remoteControl` costs the credential masking. A stock sandbox holds a
  sentinel in `~/.claude/.credentials.json` while the real token stays on the host, and the
  community workaround for this same problem bought Remote Control by bypassing the intercept, which
  put the real token in the sandbox. Docker's own fix may well not, but neither the release note nor
  the Claude Code agent page says. One `cat` inside a sandbox with the setting on.
- Whether `sbx policy init <preset>` succeeds on a fresh install with no policy to replace. It is
  documented as the non-interactive way to set a preset, and `have-agent-sandbox` treats a failure as
  fatal rather than a warning, because an unset policy means the first `sbx run` prompts and a prompt
  on a headless server hangs.

Deferred by scope, with a recipe carrying its `blocked_by`: `make-data-encrypted` needs a real server
to build against, and `have-native-apps` is server-specific by nature.
