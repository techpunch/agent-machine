---
name: lean
summary: Stop running what nobody is there to use
order: 7
recipes: [make-lean]
---

macOS ships tuned for a machine somebody sits in front of. On a server that nobody looks at,
Spotlight reindexes every repository an agent clones and every VM disk image `sbx` writes, the
screen saver draws for an empty room, and desktop widgets keep waking up to refresh.

Turning those off gives the CPU, RAM and disk back to the agents. Every change is written to the
run log with what it was before, so it can be undone.
