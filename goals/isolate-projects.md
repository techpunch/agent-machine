---
name: isolate-projects
summary: Keep projects apart from each other
recipes: [have-containers]
---

A container per project, so an untrusted repo cannot read your other projects' files or
reach their credentials. Adds an `agent-run` command inside the VM that starts a project
with the right isolation without you remembering any flags.

Worth taking as soon as you run more than one thing on the box, and required before you
point an agent at code you have not read.
