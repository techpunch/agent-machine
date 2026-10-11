# Host and agent server design

Why a server is put together this way. The step-by-step lives in the recipes under
[`../recipes/`](../recipes/); this is the reasoning behind them.

## What this machine is for

1. Protect the Mac — its files, its Keychain, its services, and the Claude Code session that runs
   this cookbook on it. The LAN is out of scope: nothing on it trusts this machine.
2. One sandbox runs every coding agent, with permission prompts skipped.
3. tmux runs inside that sandbox. One `agents` command on the Mac attaches to it.
4. The sandbox keeps its own clone of every repo it works on. Nothing from the Mac is mounted.
5. Open internet, so agents can read any documentation site.
6. Claude, Codex and GitHub are signed in once on the Mac and injected into the sandbox, so agents
   can use them but never read them.
7. Agents push branches to GitHub. A protected `main` and a token limited to the relevant repos cap
   what that can cost.
8. Simple over layered: one blast radius for every project is accepted.

Everything below is the reasoning for those, and for the host layer they sit on.

## The decisions, and why

### sbx rather than Colima

Both put agents in a Linux VM, so both keep an agent off the Mac's files and Keychain — as long as
nothing is mounted. What separates them is what each needs from us to get there:

- Credentials. sbx stores the agents' sign-ins and the GitHub token on the Mac and adds them to
  requests on the way out; an agent can use them and cannot read them, so it cannot carry them away.
  Colima has no equivalent. A token used in a Colima VM is a file in that VM, readable by every agent
  and by anything that hijacks one. Building the sbx behaviour ourselves means a credential-injecting
  proxy, which is exactly the kind of security code this cookbook stopped maintaining.
- Sharing the Mac's own sessions does not work in Colima anyway. On macOS, Claude Code and `gh` keep
  their logins in the Keychain, so mounting `~/.claude` or `~/.config/gh` into a VM does not bring the
  login with it.
- Mounting `~/.claude` would also be an attack on the Mac. An agent that can write
  `~/.claude/settings.json` can add a hook, and the Claude Code session on the Mac — which runs this
  cookbook with permissions skipped — would then run it. It is the `.git/config` attack in
  [`pushing-agent-code.md`](pushing-agent-code.md), pointed at the most privileged process on the
  machine.
- Colima's defaults point the wrong way. Lima's default mounts the home directory, and the Colima
  config left on the first server mounted it writable — `~/.ssh`, `~/.claude` and this repo, all
  reachable from the VM. Every protection has to be configured in, where sbx starts with nothing
  mounted.
- The earlier Colima setup needed a hand-written firewall, and three real defects surfaced in it in a
  single review: a firewall that filtered only locally originated traffic so every container bypassed
  it, a verify that tested the wrong network namespace and so always passed, and a container tier
  that could not authenticate.

What sbx costs: it is proprietary, it needs a Docker account (free today), and it moves fast —
several releases between v0.42 and v0.47 changed commands the cookbook used. `/update` exists to
absorb that. The host layer deliberately does not depend on sbx, so the machine stays useful if that
ever changes.

### One sandbox, not one per project

Per-project sandboxes keep one project's compromise out of another's files. That is real, and it is
not what this machine is for: every project here belongs to one person at one trust level, and the
boundary worth paying for is the one around the Mac. One sandbox is one thing to create, size, keep
running and attach to, with one set of installed tools. The cost is accepted rather than overlooked:
a prompt injection in one project's dependencies can reach every other project in the sandbox, and
push branches anywhere the GitHub token reaches.

### tmux inside the sandbox

With one sandbox there is a single guest to put the grid in, so every pane starts inside it and an
agent is just `claude`. Nothing per pane crosses the boundary, and there is no way to start an agent
on the Mac by accident from a pane. The grid lives and dies with the sandbox, which also holds every
agent, so nothing extra is lost when it stops.

### Open internet

The goal is protecting the Mac, not controlling where data goes, and agents that cannot read current
documentation write confidently outdated code. A deny-by-default allowlist cannot cover the long tail
of documentation without stopping being a firewall. So the preset is `allow-all`, and the
consequence is stated: anything in the sandbox, including every project's source, can be sent
anywhere. That is why nothing that would hurt to leak belongs in it.

### Agents push their own branches

This cookbook used to forbid any credential that could push to a real repo inside a sandbox, because
a token there could be read and stolen. Injection removed that: the token is never in the sandbox. What
is left is use — while an agent runs it can push any branch and open any PR the token allows. Two
GitHub settings bound that: a fine-grained token limited to the repos agents work on, and a ruleset
that keeps everything off `main` without a pull request. In return nobody has to fetch work out of a
sandbox and push it by hand, and review happens where it already happens, on GitHub.

## The host and the network

A single Mac that does two unrelated jobs at once, without letting the second endanger the first:

1. Run things you want reachable from elsewhere — a local server, a GUI app you screen-share into —
   plus Tailscale, so you can log in from anywhere and route traffic through it from a cafe.
2. Lend its spare compute to coding agents running with permissions skipped, where a prompt injection
   or a bad dependency could turn an agent into an attacker.

The shape that satisfies both: a trusted host user owns the native apps and Tailscale, and agents run
in a microVM that owns nothing. The microVM is the security boundary.

The tailnet is closed independently of the sandbox. The tailnet policy names no rule with `tag:host`
as a source, so the server cannot open a connection to any device you own — from the sandbox, from
the host, even as root, even if every other control here has failed. Tailscale enforces ACLs on the
receiving device, so it is the one protection in this design the server does not administer: a fully
compromised host cannot switch it off. Traffic goes one way: you reach the server, the server reaches
nothing of yours.

Running on a Claude subscription rather than an API key is a requirement, not a preference — a setup
that is annoying to sign in to is one you stop using.

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
│   │       (SSH keys only, optionally; Screen Sharing keeps the password)
│   │     (GUI app, relaunched by a LaunchAgent — up once this
│   │      session logs in; SSH and Screen Sharing are system-level)
│   │
│   ├─ `agents` — attaches you to the grid inside the sandbox
│   │
│   └─ sbx (Docker Sandboxes) — holds the Claude, Codex and GitHub tokens
│        └─ one long-lived microVM, "agents", nothing from the Mac mounted
│             • tmux grid, one pane per project
│             • ~/<project> clones, pushed to GitHub as branches
│             • all egress through a host-side proxy, which injects the tokens
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

Agents run in one microVM managed by `sbx`, never on macOS directly. That boundary is what makes "skip
all permission prompts" acceptable, because it gives something the host side cannot:

- A separate kernel and filesystem with nothing from the Mac mounted, so an agent cannot read or
  write the host's files, Keychain or credentials.
- Sign-ins that are used without being held. The Claude, Codex and GitHub tokens stay on the Mac and
  the proxy adds them to outbound requests; inside the sandbox there is nothing to steal.
- A network the agent does not control: all egress goes through that proxy. Under `allow-all` it
  reaches the internet freely. `allow-all` alone would also reach the Mac's own services and
  private ranges, so explicit deny rules close those — see
  [`have-agent-sandbox`](../recipes/have-agent-sandbox/recipe.md).
- Disposability. Worst case you delete the sandbox; the host is untouched, and the work that matters
  is already on GitHub as branches.

[`have-agent-sandbox`](../recipes/have-agent-sandbox/recipe.md) installs and configures `sbx`;
[`have-shared-sandbox`](../recipes/have-shared-sandbox/recipe.md) creates the one sandbox;
[`join-github`](../recipes/join-github/recipe.md) stores the token agents push with.

### Which `~/.claude` is which

Two of them, and "where is my sign-in" has two answers.

| Where | Path | Signed in |
|---|---|---|
| Host Mac | the admin user's `~/.claude` | for cookbook work only |
| Sandbox | inside the microVM | `/login`, once |

The host one is the session you run `/setup` from and it never touches the other. The sandbox
inherits nothing from the host's `~/.claude`, and nothing of the host's is mounted into it — which is
also what keeps an agent from planting a hook the host session would run.

The sign-in goes the other way from what you would expect. `/login` is typed inside the sandbox, but
the resulting session token is stored on the host and injected into outbound requests by the proxy —
it is never written inside the sandbox at all. So the agent can make authenticated calls and cannot
read, log or exfiltrate the credential, and recreating the sandbox does not cost you the login.

That is what makes the subscription the recommended path rather than an API key. It is less work and
less exposure at the same time, which is rare enough to say plainly.

It is also why the sandbox's defaults come from a kit rather than a dotfile: a committed `spec.yaml`
travels with the repo, where a host-side config would not reach the sandbox at all.

## Trust boundaries

1. Host vs sandbox (the hypervisor): protects the native apps, host files, Keychain, host localhost
   services and the host's own Claude Code session from the agents. This is the load-bearing
   boundary, and the only one this design pays anything to keep.
2. The tailnet policy: the server, host or sandbox, cannot open a connection to any device you own.
   Enforced by Tailscale on the receiving end, independently of anything on this machine.
3. GitHub's own settings: a token limited to some repos and a ruleset on `main` bound what an agent
   can do with the push access it is given.

What is deliberately not a boundary: one project from another. They share the sandbox, its network
policy and its home directory. If one project ever needs to be kept from the rest, a second sandbox
created the same way is one command, and the sign-ins are already on the host.

## Startup and restart

A reboot has to bring everything back unattended, in one sequence:

1. macOS auto-logs-in `host`.
2. The host session starts the native apps and Tailscale connects, re-advertising the exit node.
3. That is all that needs to happen automatically.

The agent sandbox is deliberately not restarted. It persists as an object, with every checkout in
it, but bringing it up automatically would mean auto-starting agent runs. The posture is to bring the
machine back unattended but launch agent work by hand: the first `agents` after a reboot starts the
sandbox and creates a fresh grid. What has to survive a reboot is the machine and the work — and the
work survives because it is pushed to GitHub, not because the sandbox persists.

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
| tmux | apt, inside the sandbox, from the kit | A multiplexer is the smallest thing that outlives an SSH connection |

Nothing is pinned by digest. Tracking current versions means updates arrive, which matters more on a
long-lived server than byte-identical rebuilds — the reproducibility that is load-bearing here is the
recipes, which are committed. `./bin/cookbook stale` reports what has drifted, and `/update`
researches the questions it cannot answer from the machine.

## Driving the setup

The day-to-day layer: how one person coordinates many in-flight projects without hand-attaching a
terminal to each one.

The decision, and it is not a placeholder: a persistent tmux grid inside the agent sandbox, one pane
per project. `ssh <server> -t agents` attaches to it from anywhere on the tailnet; every pane is
already inside the sandbox, so starting an agent is `claude` or `codex` in a project's clone, and
there is nothing to connect to per project. From the phone it is the same command from an SSH client.

The agents' own remote-control features sit beside this rather than replacing it, and for the same
reason in both cases: each drives one session, where the grid surveys every project. Claude Code's is
not ruled out — sbx v0.39.0 added a `claude.remoteControl` setting for it — but it does not work on
current stable: it regressed in v0.43, and the fix lands in v0.48.0. Codex
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
alternatives were compared against three requirements this machine actually has. The table was drawn
up when the grid ran on the Mac and each pane launched its own `--clone` sandbox; the last column is
what that shape demanded, and the notes below say what changed when the grid moved inside one
sandbox.

| | Survives disconnect | Headless server | Works with `--clone` |
|---|---|---|---|
| tmux | yes | yes | yes |
| Zellij | yes | yes | Codex scrollback broken over SSH |
| herdr | documented; untested inside the sandbox | yes | yes, with `HERDR_AGENT` on the `sbx` command |
| cmux, Zentty | no | no | — |
| claude-squad, workmux, NTM | yes | yes | no — git worktrees |
| Conductor, Nimbalyst, Vibe Kanban | no | no | — |

cmux and Zentty are native macOS apps with no detach or reattach at all; both their own docs say to
keep tmux if sessions must survive an SSH disconnect, and this server has no GUI session to render
into. Zellij is a genuine peer — persistent, SSH-capable, better ergonomics — but has open scrollback
defects with agent TUIs over SSH, including the Termux path, and this repo's scope covers Codex as
well as Claude Code. The agent managers isolate work with a git worktree per agent, and `sbx` rejects
`--clone` from anywhere but the main checkout, so with per-project sandboxes their isolation mechanism
and ours could not both run. With the repos cloned inside one sandbox that conflict is gone — a
worktree manager could run inside the sandbox like tmux does — so what rules them out now is only the
review-bottleneck argument above. The desktop review apps still assume a machine you look at.

So tmux stays, for reasons that will not move for anything above except herdr, which gets its own
section. Moving inside the sandbox did not change the choice of tmux, only where it runs.

### herdr, the one that passes on paper

[herdr](https://github.com/herdrdev/herdr) is an agent multiplexer: a single Rust binary, Apache-2.0,
at 0.9.3 as of October 2026 and releasing every week or two, with prebuilt Linux aarch64 binaries. It
is a background server plus a TUI client, so it needs no GUI session, and it replaces tmux rather
than sitting on it — its own panes, prefix key (`ctrl+b`), copy mode and named sessions. Detach is
`ctrl+b q`, reattach is running `herdr` again, and its docs say panes keep running when you close the
client or lose the SSH connection.

What it adds over tmux, in the shape this machine now has — one sandbox, the grid inside it:

- Each pane carries a state — blocked, working, done, idle — rolled up into a sidebar, with a picker
  that jumps to whatever is blocked and notifications that work over SSH. On a grid of agents that
  is the difference between scanning every pane and being told which one wants you. Detection reads
  the screen, so it is heuristic: an unrecognised prompt reads as idle, not blocked.
- Agents come back after a restart. When the server restarts — after a reboot, here — it restores
  the layout and, once a client attaches, resumes each Claude Code and Codex pane with its own resume
  command (`claude --resume <id>`, `codex resume <id>`). With tmux a reboot means relaunching every
  agent by hand. It waits for you to attach, so it keeps the posture of launching agent work by hand,
  and the resumed agents are still in bypass mode because that comes from their config, not a flag.
- Inside the sandbox it sees `claude` and `codex` as ordinary processes. On the Mac it saw only
  `sbx`, which needed a `HERDR_AGENT` hint on every command, and the maintainers closed the request
  to look inside sandboxes as working as designed
  ([herdr#2181](https://github.com/herdrdev/herdr/issues/2181)). That objection is gone, and its
  integration hooks would install into the sandbox's `~/.claude` and `~/.codex`, not the Mac's.

Two objections from the earlier evaluation no longer apply:

- The server-lifetime bug, [herdr#4920](https://github.com/herdrdev/herdr/issues/4920), is still open
  and now reads "Server shuts down ~1s after last client detaches, killing all pane processes". But a
  commenter traced the signal to macOS: `loginwindow` force-quits everything a terminal app started
  when that app quits, even a server that has properly detached. Nothing like that runs inside a
  Linux sandbox.
- Upgrading stops the server, which kills the panes. In a kit that installs herdr at create and
  updates it at sandbox start, as it does the agents, that happens when no panes exist.

What still stands against making it the default:

- Stability on the one requirement the grid exists for. 0.9.0 shipped a Linux server crash that
  killed every pane ([herdr#4174](https://github.com/herdrdev/herdr/issues/4174), fixed in 0.9.1),
  and restore after a restart has had bugs since
  ([herdr#5104](https://github.com/herdrdev/herdr/issues/5104), with zsh, which the sandbox does not
  use). A 0.x tool with over 300 open issues and pull requests, releasing weekly, against tmux,
  which does not change.
- Whether its server outlives the `sbx exec` session that started it is the same open question tmux
  has, and nobody has tried it.
- Its remote-machines feature — a herdr client on your laptop showing several servers' agents in one
  window — needs an SSH target that lands inside the sandbox, and this design reaches the sandbox
  through `sbx exec` on the Mac. Not a path this cookbook has.
- It fetches detection-manifest updates from herdr.dev. `[update] manifest_check = false` turns that
  off; decide rather than discover it.

The options, then:

- Instead of tmux. The right end state if it proves out: the state sidebar and resume after reboot
  are real gains, and nothing else in the table passes all three columns. Not before the test below.
- Inside tmux. tmux keeps owning survival while herdr adds the sidebar, at the cost of two prefix
  layers that both default to `ctrl+b`. A reasonable way to trial it. The reverse, tmux inside
  herdr, is pointless: herdr then sees `tmux` as the pane process and loses detection.
- tmux only. What `have-coordination` installs today, and nothing above makes it wrong.

The test that decides it, on a real server: install herdr inside the sandbox
(`curl -fsSL https://herdr.dev/install.sh | sh`, the documented installer), start it from
`sbx exec -it agents bash`, run `claude` in a pane, drop the SSH connection without detaching,
reconnect, and confirm the agent is still running and its state is right. Then restart the sandbox,
attach, and check the agent resumed its conversation in bypass mode. Then repeat from a phone with
Codex, since scrollback over SSH is what ruled out Zellij. If all three pass, the change is small: an
install step and a start-time update in the kit, and the `agents` command running `herdr` instead of
`tmux new-session -A`.

Deliberately absent: a dispatcher that takes a request from a chat app and routes it to an agent
unattended. That is the natural next thing to want, and it is the point at which this stops being a
grid you supervise and becomes a system acting on messages from outside. Adding one means adding a
network-exposed daemon, and the design should be revisited rather than extended.

### Sources

- [herdr](https://github.com/herdrdev/herdr) and [its docs](https://herdr.dev/docs/), including
  [#2181](https://github.com/herdrdev/herdr/issues/2181) (running under `sbx`) and
  [#4920](https://github.com/herdrdev/herdr/issues/4920) (server lifetime on macOS)
- [Peter Steinberger — Just Talk To It](https://steipete.me/posts/just-talk-to-it)
- [Simon Willison — Embracing the parallel coding agent lifestyle](https://simonwillison.net/tags/parallel-agents/)
- [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) and its
  [default security posture](https://docs.docker.com/ai/sandboxes/security/defaults/)
- [Remote Control inside sandboxes](https://github.com/docker/sbx-releases/issues/8) — why `/rc` did
  not reach a sandboxed agent, and
  [sbx v0.39.0](https://github.com/docker/sbx-releases/releases/tag/v0.39.0), which added the
  setting that lets it; [#664](https://github.com/docker/sbx-releases/issues/664) for the v0.43
  regression, fixed for v0.48.0
- [Docker Sandboxes release notes](https://docs.docker.com/ai/sandboxes/release-notes/) — the design
  was last checked against v0.47.0
- [Codex Remote connections](https://developers.openai.com/codex/remote-connections) — the desktop
  app requirement, and the SSH-host mode that is the only one shaped like this machine

## What is left to pin

Settled: the goals at the top, the naming scheme, the host layer, one shared sandbox with the grid
inside it, `allow-all`, and agents pushing their own branches.

Open only because the answers are not published anywhere, and each is a few commands on the first
real server. Every one is also written into the recipe it affects:

- Whether an agent started from a shell — `sbx exec`, then `claude` — gets the injected sign-in the
  way one started with `sbx run` does. The proxy injects per sandbox, which says yes; Docker documents
  `exec` for shells and commands, not for a second agent. The whole grid depends on it. If it fails,
  the fallback is still one sandbox: Claude Code's agents view,
  `sbx run --name agents -- --dangerously-skip-permissions agents`, runs several sessions from one
  `sbx run`. See [`have-shared-sandbox`](../recipes/have-shared-sandbox/recipe.md).
- Whether the grid survives the `agents` connection ending. tmux forks its server away from the
  client, but whether `sbx exec` reaps what it started is not documented. See
  [`have-coordination`](../recipes/have-coordination/recipe.md).
- Whether the deny rules that keep sandboxes off the Mac hold — `allow-all` does not do it alone,
  so `have-agent-sandbox` denies `localhost`, `host.docker.internal` and the private ranges, IPv6
  included, and its verify tries the Mac's SSH from inside a sandbox — by address, and by a public
  hostname that resolves to the LAN address, since nothing published says a range rule catches
  that. See
  [`have-agent-sandbox`](../recipes/have-agent-sandbox/recipe.md).
- Whether a sandbox created as `claude` gets the GitHub token. A Docker engineer has written that
  the built-in GitHub credential covers git over HTTPS as well as the API, and the token is stored
  before the sandbox is created so `gh` gets its placeholder; what is unproven is only that the
  claude kit, which does not declare `github`, still gets it. See
  [`join-github`](../recipes/join-github/recipe.md).
- Whether Codex works in the one sandbox. It is created as `claude`, so the kit installs Codex and
  declares its sign-in, copied from Docker's codex kit; none of that has run yet. See
  [`have-shared-sandbox`](../recipes/have-shared-sandbox/recipe.md).
- Whether turning on `claude.remoteControl` costs the credential masking. A stock sandbox holds a
  sentinel in `~/.claude/.credentials.json` while the real token stays on the host, and the
  community workaround for this same problem bought Remote Control by bypassing the intercept, which
  put the real token in the sandbox. One `cat` inside the sandbox with the setting on, once v0.48.0
  makes the setting work again.

Deferred by scope, with a recipe carrying its `blocked_by`: `make-data-encrypted` needs a real server
to build against, and `have-native-apps` is server-specific by nature.
