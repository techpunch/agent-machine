# Backlog of Features

## Implement something like this after we get sub vms sorted out

"My dev machine restarts for updates about once a week, and the worst part was always reopening a dozen Claude Code sessions by hand and trying to remember what each one was doing. Now I name every session with claude -n or /rename, and I added SessionStart and SessionEnd hooks that write each session's id, name, and directory to a file that a small script reads on boot to resume them all. After my last restart, all 19 sessions were back in about 30 seconds."

– Will Laves, works on Data Engineering at Anthropic

Note: herdr does this natively. After a restart it restores the layout and, once you attach, resumes
each Claude Code and Codex pane with `claude --resume <id>` or `codex resume <id>` — no hooks or boot
script to maintain. So the herdr trial in
[`docs/host-agent-design.md`](docs/host-agent-design.md#herdr-the-one-that-passes-on-paper) is the
first way to get this. If herdr does not pass it and the grid stays tmux, the approach above is the
fallback: session hooks inside the sandbox writing each session's id, name and directory, and a
script `agents` runs to resume them.
