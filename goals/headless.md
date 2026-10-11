---
name: headless
summary: Run with no monitor, keyboard or mouse
order: 6
recipes: [make-headless]
---

Proves the server survives a reboot with nobody touching it, and only then tells you to
unplug the peripherals. The order matters: verifying remote access after the keyboard is
gone is how people end up driving back to the office.

You need an HDMI display emulator for this — see the prerequisites.
