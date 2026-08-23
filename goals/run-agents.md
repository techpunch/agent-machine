---
name: run-agents
summary: Run coding agents on it
order: 7
recipes: [have-agent-sandbox]
---

Installs Docker Sandboxes (`sbx`), which runs Claude Code or Codex — whichever you have an account
for, or both — with each one in its own microVM with its own filesystem and network, and all its
outbound traffic going through a policy you set rather than straight out.

Every project you point an agent at runs in one of these, never on macOS itself. That separation is
what makes running an agent with permission prompts skipped a defensible thing to do.
