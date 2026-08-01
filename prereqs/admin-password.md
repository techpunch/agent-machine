---
name: admin-password
summary: The admin account's password, for one command you type yourself
when: before-you-start
---
Just have it to hand — you will type it into one command, not tell it to me.

Auto-login is the one setting that unlocks the machine itself, so this cookbook never
accepts that password, never stores it, and never passes it through a script. At the right
moment I will hand you a command ending in `-password -`, which makes macOS prompt for it
directly. Nothing reaches your shell history, the process list, or this transcript.
