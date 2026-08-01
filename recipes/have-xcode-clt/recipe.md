---
name: have-xcode-clt
summary: Ensure the Xcode Command Line Tools are installed (git, clang, make).
requires: [have-server-identity]
root: no
gates: GUI installer dialog on a machine that has never had them
---

Homebrew needs a compiler and `git`, so this is the prerequisite under `have-homebrew`.

`xcode-select --install` opens a GUI dialog and returns immediately — it does not block until the
install finishes, and on a headless server nobody is there to click Install. Apply therefore triggers
the installer and then waits, polling for the tools to appear; if they haven't shown up inside the
timeout it stops at a gate and tells you to approve the dialog over Screen Sharing.

On a server that already has Xcode proper installed this verifies clean without doing anything.
