---
name: make-updates-manual
summary: Let macOS check for and download updates, but never install and reboot on its own.
requires: [have-server-identity]
root: yes
status: blocked
blocked_by: macOS 26 deprecated the only scriptable path, and no readable state has been confirmed to replace it — needs a real server to answer, not a laptop
---

The problem is real and worth solving. An unattended macOS update installs itself and restarts the
machine, which kills every agent mid-run with no warning and no record beyond the reboot itself. A
server that reboots when Apple decides rather than when you do is not unattended, it is unpredictable.
The wanted end state is narrow: keep checking and downloading, so `softwareupdate --list` still tells
you what is pending and the bits are already on disk, but never install or restart without a human.

This recipe has no scripts because the honest answer, as of macOS 26, is that we cannot verify it.

## What was looked up, so nobody repeats it

Apple's enterprise notes for macOS Tahoe 26 say software update management via MDM commands,
restrictions, and the `com.apple.SoftwareUpdate` payload is deprecated, and that it will be removed
entirely in the 2026 OS release. Management moves to declarative device management, which requires
an MDM server — something this project deliberately does not assume, since the whole premise is a
spare Mac somebody owns.

That deprecation is about the MDM payload, not necessarily the local preference domain, and the
local domain is demonstrably still live on 26.3: `/Library/Preferences/com.apple.SoftwareUpdate`
carries `AutomaticDownload` on a stock machine. So the widely-cited

```
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false
```

may well still work. What could not be established from a laptop is whether `softwareupdated` on 26
honours that key, and where System Settings records the toggle now — the key is absent from the
domain on a stock 26.3 install, which is consistent with both "absent means default" and "no longer
used".

Writing the recipe anyway would produce the specific failure this repo exists to avoid: an `apply`
that sets a key, and a `verify` that reads the same key back and goes green, on a server that is
still quietly rebooting itself at 3am. A verify that confirms only its own write is a verify that
lies.

## What unblocks it

One session on a real server running the current macOS, answering two questions:

- Toggle "Install macOS updates" off in System Settings > General > Software Update > the (i) beside
  Automatic Updates, then diff `/Library/Preferences/com.apple.SoftwareUpdate` before and after. If
  the toggle writes `AutomaticallyInstallMacOSUpdates` there, verify has something real to read.
- Write the key with `defaults` and check whether the System Settings toggle follows it. If it does,
  apply has something real to write, and this becomes an ordinary recipe.

If neither holds, the setting is GUI-only on current macOS and this should become a gate in
`make-headless` — named as a step somebody does over Screen Sharing while the monitor is still
attached, rather than a recipe pretending to automate it.

## Until then

Do it by hand, once, while you still have a screen: System Settings > General > Software Update, the
(i) beside Automatic Updates, and turn off "Install macOS updates". Leave "Check for updates" and
"Download new updates when available" on. Security responses and system files are a separate pair of
toggles and should stay on — they are the ones that patch without a restart.
