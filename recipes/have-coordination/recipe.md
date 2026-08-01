---
name: have-coordination
summary: The layer you actually drive the server through — a persistent tmux grid in the VM.
requires: [have-vm-claude-code]
root: no
gates: none
---

A tmux session inside the VM, one pane per project, that survives you closing the laptop. You attach
to that one session instead of opening a terminal per agent, and detaching leaves everything running.

What it installs: tmux in the guest, a managed `~/.tmux.conf`, and an `agents` helper on the guest's
PATH that attaches to the session or creates it if it is not there — `tmux new-session -A`, so there
is one entry point and no way to end up with a second detached session you forgot about.

Attach from the Mac, or from anywhere over Tailscale:

```
ssh <admin>@<server>
colima ssh --profile agent -- -t agents
```

Then split panes and start an agent in each. The session name is recorded as `VM_TMUX_SESSION`.

## Why this and not an orchestrator

The people running many agents at volume agree the bottleneck is not spawning or coordinating them,
it is how fast you can review what they produce — and the wrapper apps that hide the terminal tend to
get discarded for that reason. A multiplexer is the smallest thing that solves the actual problem,
which is that agent processes must outlive your SSH connection. See "Driving the setup" in
[`../../docs/host-agent-design.md`](../../docs/host-agent-design.md).

Add a worktree board later if reading diffs across many tasks becomes the thing that slows you down.
Not before.

## Why it does not need containers

This requires `have-vm-claude-code`, not `have-containers` or `have-agent-auth`. A multiplexer holding
sessions does not care how many agents there are or what they run in, so the grid works today against
the Claude Code already in the VM and gains panes as more agents arrive.

## Phone access

Nothing to install. Claude Code Remote Control (`/rc` in a session) drives one specific session from
the Claude mobile app, and Codex has the equivalent through the ChatGPT app once it is signed in.
Both keep execution in the VM — only chat and tool results cross the bridge. They are for nudging
something already running while you are away from the desk, not for surveying the whole grid; for
that, attach.

## The session is not restarted for you

tmux sessions live and die with the VM. After a VM restart the grid is gone and `agents` creates a
fresh one. That is deliberate — auto-recreating panes would mean auto-starting agent runs, and the
posture in the design doc is to auto-start the sandbox but launch agent runs by hand.
