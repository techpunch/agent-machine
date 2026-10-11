---
name: have-shared-sandbox
summary: One long-lived sandbox that every agent on this server runs in.
requires: [have-agent-sandbox, join-github]
root: no
gates: none
---

The sandbox the agents actually live in. One of them, not one per project: every agent on this
server runs inside it, in bypass mode, and every repo it works on is cloned inside it. Why one rather
than many is argued in [`../../docs/host-agent-design.md`](../../docs/host-agent-design.md); the short
version is that it is simpler, and the thing worth isolating is the Mac, not one project from another.

What apply does:

- Creates a sandbox named `agents` (`SBX_SANDBOX` to change it) with no path, so nothing from the Mac
  is mounted into it. The repos live inside, cloned over HTTPS.
- Switches it to detached mode with `sbx run -d`, so it keeps running with nobody attached. The
  terminal grid lives inside it, and a sandbox that stopped when you disconnected would take the grid
  with it.
- Loads the kit from [`../have-agent-sandbox/kit/`](../have-agent-sandbox/kit/), which installs Codex
  and tmux beside Claude Code, updates both agents at every sandbox start, and tells every agent how
  to work here. It also aliases `claude` and `codex` to start in bypass mode: `sbx run` does that by
  default, but a session started from a shell does not, and here every agent is started from a shell
  in a tmux pane. Everything inside the sandbox comes from the kit, so recreating the sandbox
  recreates all of it.
- Before creating the sandbox, gates until the Codex sign-in is stored (`CODEX=off` skips it), and
  writes the binding that lets sbx hand that sign-in to our kit. The kit sets Codex up from whether a
  sign-in exists when the sandbox is created, so storing it afterwards means recreating the sandbox.
- Requires [`join-github`](../join-github/recipe.md) for the same reason. The proxy starts injecting
  a GitHub token the moment it is stored, but the placeholder `GH_TOKEN` that makes `gh` try at all
  is set only when a sandbox is created — a Docker maintainer says as much in
  [docker/sbx-releases#477](https://github.com/docker/sbx-releases/issues/477).

## Day to day

Through [`have-coordination`](../have-coordination/recipe.md), which puts a tmux grid inside this
sandbox. From anywhere on the tailnet:

```
ssh <server> -t agents          # attach the grid, inside the sandbox
git clone https://github.com/<you>/<project> ~/<project> && cd ~/<project>
claude                          # or codex — bypass mode either way
```

The first `claude` in the sandbox asks you to `/login`, once. The token is held on the Mac and
injected by the proxy, so the sandbox never holds it and later sessions do not ask again.

Work leaves by `git push` of a branch, with the GitHub token [`join-github`](../join-github/recipe.md)
stores on the Mac. Nothing else crosses the boundary.

## Sizing is decided once

Disk, memory and CPUs are fixed when the sandbox is created. Apply creates it with a 100 GB root disk
rather than the default 20 GB, because it holds every project and every dependency tree at once;
`DOCKER_SANDBOXES_ROOT_SIZE` on the first apply changes that. Memory and CPUs keep sbx's defaults —
half the host's memory, capped at 32 GiB, and all its CPUs — which suits a machine whose job is
running agents.

Changing any of them later means `sbx rm --force agents` and applying again, and removing the sandbox
deletes every checkout inside it. Push before you do that; anything unpushed is gone.

## After a reboot

The sandbox does not start by itself, deliberately — bringing the machine back unattended is the
host's job, launching agent work is yours. It persists as an object with everything inside it, and
the first `agents` after a reboot starts it again, because `sbx exec` starts a stopped sandbox.

## What one sandbox costs

Decided, not discovered:

- One blast radius. A prompt injection in one project's dependencies can read and rewrite every
  other project in the sandbox, and push branches anywhere the GitHub token reaches. Branch
  protection on `main` and a token limited to the repos agents work on are what bound it —
  [`../../prereqs/github-token.md`](../../prereqs/github-token.md).
- One network policy and one set of approvals, shared by every project.
- One `~/.claude` and one `~/.codex` — settings and history are shared across projects.

None of that reaches the Mac. That is the line this design holds.

## Not yet confirmed on a real server

- That an agent started from a shell — `sbx exec`, then `claude` — gets the injected sign-in the same
  way one started with `sbx run` does. Likely: Docker's claude kit does its sign-in work as files in
  the sandbox (`~/.claude/.credentials.json` holding placeholder tokens, an `apiKeyHelper` in
  `~/.claude/settings.json`) plus proxy rules, none of which care how the process was started, and a
  Docker maintainer suggests `sbx exec -it <sandbox> claude` in
  [docker/sbx-releases#242](https://github.com/docker/sbx-releases/issues/242). If it does not, the
  fallback is still one sandbox: Claude Code's agents view,
  `sbx run --name agents -- --dangerously-skip-permissions agents`.
- The Codex parts of the kit, which are new. That the install and the sign-in work in a sandbox
  created as `claude`; that sbx sets `SBX_CRED_OPENAI_MODE` for a credential a mixin declares, as it
  does for its own codex kit, since Codex's config is seeded from it; and that the update step runs
  at start. Run `codex` in a pane, and `claude --version` after a restart.
- That both agents got the kit's guidance. Ask each one what it was told about pushing to `main`.
- That `gh auth status` in a pane shows the injected token, and that `git push` of a branch works —
  see [`join-github`](../join-github/recipe.md), which has the evidence for both.
