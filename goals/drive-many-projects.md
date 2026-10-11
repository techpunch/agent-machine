---
name: drive-many-projects
summary: Drive many projects at once
order: 8
recipes: [have-coordination]
---

A persistent tmux grid inside the agent sandbox, one pane per project. From anywhere on the tailnet,
`ssh <server> -t agents` attaches to it, and detaching leaves every agent running.

Adds an `agents` command on the Mac that attaches to the grid,
creating it if it is not already there. Needs the agent sandbox, so it brings that along if you have
not set it up yet.
