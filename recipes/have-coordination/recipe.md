---
name: have-coordination
summary: The layer you actually drive the server through — a persistent tmux grid.
requires: [have-homebrew]
root: no
gates: none
---

A tmux session on the server, one pane per project, that survives you closing the laptop. You attach
to that one session instead of opening a terminal per agent, and detaching leaves everything running.

What it installs: tmux, a managed `~/.tmux.conf`, and an `agents` helper that attaches to the session
or creates it if it is not there — `tmux new-session -A`, so there is one entry point and no way to
end up with a second detached session you forgot about.

```
ssh <server> -t agents        # attach the grid from anywhere on the tailnet
sbx run --clone claude        # in a pane: one project, in its own sandbox
```

`sbx run` attaches you to the agent, so the pane is the session. There is no second step and nothing
to SSH into per project — one connection to the server reaches every agent. If you want a shell in a
sandbox rather than its agent, that is `sbx setup ssh` once, then `ssh <sandbox>.sbx`, which is an
escape hatch for debugging a build rather than the way in.

## Why the grid is on the host now

It used to live inside the VM, because the VM was the one long-lived guest everything ran in. With
`sbx` there is no single guest — each project gets its own sandbox — so a grid inside any one of them
would only see that project, and would vanish with it.

So the grid runs on the Mac and each pane attaches to a sandbox. That is simpler in a way worth noting:
this recipe no longer depends on the agent layer at all. It requires only Homebrew, which means the
terminal grid works whether or not you have got as far as installing `sbx`.

## The session is not restarted for you

tmux sessions live and die with the login session. After a reboot the grid is gone and `agents`
creates a fresh one. That is deliberate — auto-recreating panes would mean auto-starting agent runs,
and the posture here is to bring the machine back unattended but launch agent work by hand.

## Phone access

An SSH client on the phone — Termius, Blink, Termux — over Tailscale, then the same
`ssh <server> -t agents`. Same grid, same panes, nothing extra installed on the server.

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
at once rather than driving one session, which is what this machine is for. And the fix is half
landed — the outbound half connects while the inbound stream stalls, so commands sent from a phone
hang until something is typed in the sandbox, reported against v0.39.0 in
docker/sbx-releases#12 and unresolved. Turn it on if you want the phone-browser path anyway; it costs
one command and nothing else here depends on it.

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
