---
name: full-disk-access
summary: Full Disk Access for the terminal you are running this in
when: before-you-start
---
System Settings, then Privacy & Security, then Full Disk Access. Add Terminal (or whichever
terminal app you are in) and turn it on. You may have to quit and reopen the terminal
afterwards.

Why: macOS refuses to let this cookbook enable Remote Login without it, and the refusal is
silent — the command reports success and SSH stays off. That failure wastes twenty minutes
if you hit it, and none if you do this first.
