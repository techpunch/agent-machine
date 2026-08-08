---
name: make-lean
summary: Stop the background work a server with nobody at the screen has no use for.
requires: [have-server-identity]
root: yes
verify_root: no
gates: none
---

An agent server spends its CPU, RAM and disk bandwidth on one thing, and macOS ships configured for
a different machine — a laptop somebody sits in front of. This recipe turns off the parts of that
default that a headless box cannot benefit from, and writes every change to the run log with what it
was before, because these are system settings somebody may want back.

What it turns off, and why each one is worth a line:

- Spotlight indexing, on `/` and `/System/Volumes/Data`. This is the one that matters. An agent
  server is close to the worst case Spotlight can be given: agents clone and rebuild repositories
  continuously, and `sbx` keeps multi-gigabyte VM disk images that churn on every run. `mds` and
  `mds_stores` reindex all of it, forever, to serve a search UI that nobody is sitting in front of.
- The screen saver, by setting the admin user's idle time to zero. `make-always-on` sets
  `displaysleep 0`, so the display never sleeps and the screen saver is the one thing left that will
  start on its own and keep the GPU busy — drawing, through the headless dongle, for nobody.
- Desktop widgets. Widgets are live: they hold timers and wake to refresh whether or not a display
  is attached, and on current macOS they are on by default. A desktop nobody looks at should not be
  running any.

## What it deliberately does not do

Automatic software updates stay exactly as they were. Turning them off would suit an unattended
server — an update that reboots the machine kills every running agent, and this cookbook has no way
to schedule that around them — but leaving a network-reachable host unpatched is a security decision
about a whole fleet, not a performance tweak, and it does not belong in a recipe whose subject is
wasted CPU. If you want it, it should be its own recipe with its own argument.

Bluetooth stays on for the same kind of reason. A headless server has no keyboard or mouse to pair,
so the radio is doing nothing useful — but it is also a recovery path, and `make-headless` is built
around not removing recovery paths until the replacement is proven.

Nothing here is erased, only switched off. Spotlight's existing index is left on disk rather than
wiped with `mdutil -E`, so re-enabling indexing does not mean rebuilding from nothing.

## Undoing it

Each setting independently, as the admin user except where root is needed:

```
sudo mdutil -a -i on
defaults -currentHost delete com.apple.screensaver idleTime
defaults write com.apple.WindowManager StandardHideWidgets -bool false
```

`./bin/cookbook log` shows what was changed and when, with the previous value on each line — that is
the record to read before undoing anything, since it says what this server looked like beforehand
rather than what a default macOS install does.

## What is not proven here

The screen saver preference is the long-standing key macOS exposes for this, and verify reads it
back, so the recipe can tell you the setting is in place. It cannot tell you the screen saver engine
on this macOS version honours it — that changed shape in Sonoma and we have no headless server here
to watch. Treat a green line as "the setting is set", and if you find a server running a screen
saver anyway, that is a cookbook defect worth reporting rather than a machine being odd.
