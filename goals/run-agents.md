---
name: run-agents
summary: Run coding agents on it
order: 6
recipes: [have-agent-sandbox, have-shared-sandbox, join-github]
---

Installs Docker Sandboxes (`sbx`) and creates one sandbox — a microVM with its own filesystem and
network — that every coding agent on this server runs in: Claude Code, Codex, or both, whichever you
have an account for. Agents run with permission prompts skipped, which is defensible because nothing
from the Mac is inside the sandbox.

Each agent clones its project inside the sandbox, works on a branch, and pushes it to GitHub. The
Claude, Codex and GitHub sign-ins are stored on the Mac and injected into the sandbox's requests, so
agents can use them but never read them. Agents can read any website, so they can look up current
documentation.
