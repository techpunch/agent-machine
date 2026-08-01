---
name: run-agents
summary: Run coding agents on it
recipes: [have-vm-claude-code]
---

An isolated Linux VM with Claude Code installed and signed in, its network bounded so a
compromised agent can reach the internet but not your laptop, your other machines, or this
Mac.

Every project you point an agent at runs in here, never on macOS itself. That separation is
the whole reason the VM exists.
