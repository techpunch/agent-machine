---
name: have-coordination
summary: The layer you actually drive the server through — a persistent tmux grid inside the agent sandbox.
requires: [have-shared-sandbox]
root: no
gates: none
---

A tmux session inside the shared agent sandbox, one pane per project, that survives you closing the
laptop. You attach to that one session instead of opening a terminal per agent, and detaching leaves
everything running.

What it installs: an `agents` helper on the Mac that attaches to the grid or creates it if it is not there —
`sbx exec -it agents tmux new-session -A -s agents`, so there is one entry point and no way to end up
with a second grid you forgot about. tmux and its config inside the sandbox come from the kit
[`have-shared-sandbox`](../have-shared-sandbox/recipe.md) creates it with.

```
ssh <server> -t agents                                    # from anywhere on the tailnet
git clone https://github.com/<you>/<project> ~/<project>  # in a pane, once per project
cd ~/<project> && claude                                  # or codex — bypass mode either way
```

Every pane is already inside the sandbox, so an agent is just `claude` or `codex`, and both start in
bypass mode from their config files — see
[`have-agent-sandbox`](../have-agent-sandbox/recipe.md#codex-as-well-as-claude-code). Typing `claude` on the
Mac itself is the one thing not to do: that runs on macOS, outside the sandbox, with everything the
sandbox exists to protect.

Why tmux rather than Zellij, herdr or an agent manager is argued in
[`../../docs/host-agent-design.md`](../../docs/host-agent-design.md). herdr is the one alternative
that passes on paper and is worth trialling; that doc has the test that would make it the default.

## Why the grid is inside the sandbox

It was on the Mac while the design was one sandbox per project, because there was no single guest to
put it in — a grid inside any one sandbox would only have seen that project. Now there is one sandbox
for everything, so the grid goes back inside it, where every pane starts in the right place and
nothing per pane has to cross the boundary.

What that costs: the grid lives and dies with the sandbox. Stopping or recreating the sandbox takes
the grid with it — but it takes every agent with it too, so nothing extra is lost.

## After a reboot

Neither the sandbox nor the grid comes back by itself. That is deliberate — auto-recreating panes
would mean auto-starting agent runs, and the posture here is to bring the machine back unattended but
launch agent work by hand. The first `agents` after a reboot starts the sandbox, because `sbx exec`
starts a stopped one, and creates a fresh grid in it. The checkouts inside are still there; the
agents are not, and each has to be started again by hand. Resuming them all at once is in
[`../../BACKLOG.md`](../../BACKLOG.md), and herdr does it natively — one of the reasons it is the
alternative worth trialling.

## Not yet confirmed on a real server

That the grid survives the `agents` connection ending. tmux forks its server away from the client,
which is what keeps sessions alive on any Linux box, and the sandbox is detached so it keeps running;
but whether `sbx exec` reaps everything it started when the session ends is not documented. Attach,
start something in a pane, drop the SSH connection without detaching, reconnect, and check. If it
does not survive, the fallback is tmux on the Mac with each pane running `sbx exec -it agents bash`,
and this file should say so.

## Phone access

An SSH client on the phone — Termius, Blink, Termux — over Tailscale, then the same
`ssh <server> -t agents`. Same grid, same panes, nothing extra installed anywhere.

Claude Code Remote Control is a second way in, and it is off by default. `/remote-control` used to
fail inside a sandbox: the proxy that makes the sign-in safe rewrites the `Authorization` header on
requests to `api.anthropic.com`, and Remote Control registers a purpose-scoped token for its polling
endpoint that got overwritten with an inference-only one, so the poll was refused. sbx v0.39.0
(19 August 2026) added a setting for it:

```
sbx settings set claude.remoteControl true
```

Host-wide, set once. That is also all Docker publishes: the release note and the Claude Code agent
page name the setting and say nothing about what it changes in the intercept, so whether the
host-held credential stays masked inside the sandbox is undocumented either way.

Not turned on by this recipe, for two reasons. The grid is still the way in: it surveys every project
at once rather than driving one session, which is what this machine is for. And on current stable it
does not work. The stall reported against v0.39.0 was fixed by v0.42, then v0.43 stopped forwarding
credentials the proxy did not issue, and `/rc` has asked for `/login` and failed with a 401 ever
since — still the case on v0.47.0. Docker closed
[docker/sbx-releases#12](https://github.com/docker/sbx-releases/issues/12) on 9 October 2026 with the
fix in v0.48.0-rc3, to ship in v0.48.0, and the setting is still required after it. Server mode,
`claude remote-control`, is a separate open bug,
[#695](https://github.com/docker/sbx-releases/issues/695). Turn it on once v0.48.0 is out if you want
the phone-browser path; it costs one command and nothing else here depends on it.

Codex Remote is the equivalent on the OpenAI side, and it fails here for a different reason — not the
proxy, the shape. It is driven from the ChatGPT desktop app: Settings > Connections >
Control this Mac or PC, then scan a QR code with the phone to pair it. OpenAI says outright that you
cannot set it up from the Codex CLI or the IDE extension, so there is no headless path in — a server
would need the desktop app installed, signed in, awake, and a screen-sharing session to scan the code
from. And what it then drives is Codex on that host's own filesystem, which is the thing this repo
does not do. Agents run in a microVM here, and a phone that can start host-side work has undone the
boundary the sandbox exists for.

The mode that does fit the shape of this machine is Codex Remote's SSH host: the desktop app on your
laptop reads a concrete `Host` alias from `~/.ssh/config`, starts a Codex app server on that machine
over SSH, and runs chats against its filesystem and shell. Tailscale is already the transport OpenAI
asks for here — the guide says not to expose app-server transports on a shared or public network and
to use a VPN or mesh network instead. Two things stop it being a recommendation rather than a note.
It wants `codex` on the remote login shell's `PATH`, which means installing an agent on the host that
this cookbook deliberately keeps agent-free. And it still runs outside the sandbox, so pointing it at
`<name>.sbx` from `sbx setup ssh` rather than at the server is the only version worth having — those
aliases resolve on the server rather than on your laptop, so it would need a jump through the server,
and nobody here has tried it. If you do, the answer belongs in this file.

Neither of these replaces the grid, and one reason is structural rather than a defect: the phone
reaches an SSH host through the desktop app, so the always-on machine is now your laptop. SSH and
tmux need nothing awake but the server.
