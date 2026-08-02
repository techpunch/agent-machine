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

## Why the grid is on the host now

It used to live inside the VM, because the VM was where agents ran. With `sbx` each agent gets its own
microVM per invocation, so there is no long-lived guest to hold the session — and putting the grid
inside a disposable sandbox would defeat the point of it outlasting your connection.

So the grid runs on the Mac and each pane starts a sandbox. That is simpler in a way worth noting:
this recipe no longer depends on the agent layer at all. It requires only Homebrew, which means the
terminal grid works whether or not you have got as far as installing `sbx`.

## The session is not restarted for you

tmux sessions live and die with the login session. After a reboot the grid is gone and `agents`
creates a fresh one. That is deliberate — auto-recreating panes would mean auto-starting agent runs,
and the posture here is to bring the machine back unattended but launch agent work by hand.

## Phone access

Nothing to install. Claude Code Remote Control (`/rc` in a session) drives one specific session from
the Claude mobile app. It keeps execution on the server — only chat and tool results cross the
bridge. It is for nudging something already running while you are away from the desk, not for
surveying the whole grid; for that, attach.
