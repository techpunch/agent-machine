---
name: drive-many-projects
summary: Drive many projects at once
order: 6
recipes: [have-coordination]
---

A persistent tmux grid on the server, one pane per project. You attach to one session from anywhere
on the tailnet instead of opening a terminal per agent, and detaching leaves everything running.

Installs tmux, a managed `~/.tmux.conf`, and an `agents` command that attaches to the grid, creating
it if it is not already there. Useful on its own, and independent of whether you have set up the
agent sandbox yet.
