---
name: always-on
summary: Keep running unattended
recipes: [make-always-on, make-auto-login]
---

Never sleeps, wakes for network traffic, and comes back by itself after a power cut —
logging its admin user straight back in so everything else restarts with it.

Without this a server is fine until the first thunderstorm, and then it is a brick you have
to go and touch.
