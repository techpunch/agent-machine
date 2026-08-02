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

Not Claude Code Remote Control. `/rc` works for an agent running on the host, but not for one in a
sandbox, and the reason is structural rather than a bug waiting to be fixed. The proxy that makes the
sign-in safe works by rewriting the `Authorization` header on requests to `api.anthropic.com`;
Remote Control registers a purpose-scoped token for its polling endpoint, and that token is exactly
what gets overwritten. The substituted one carries inference scopes only, so the poll is refused.
`remote-control.anthropic.com` also fails to resolve inside the VM.

There is no setting for this. `sbx policy allow network` has no TLS-bypass flag, the choice between
intercepting and passing a host through is internal, and a self-supplied token does not help because
`claude setup-token` credentials cannot establish Remote Control sessions by design. Tracked upstream
as docker/sbx-releases#8; nothing has shipped as of v0.37.1. If it lands, this section is worth
revisiting — but SSH plus the grid is the better fit for this machine anyway, because it surveys
every project at once rather than driving one session.
