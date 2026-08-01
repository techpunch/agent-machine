#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"
need_root

out=$(/usr/sbin/systemsetup -setremotelogin on 2>&1 || true)
if /usr/sbin/systemsetup -getremotelogin 2>/dev/null | grep -q On; then
  ok "remote login (SSH): on"
else
  gate "Could not enable Remote Login: ${out:-no output}.
macOS requires Full Disk Access for the process calling systemsetup. Grant it to whichever
of these is running this recipe, then re-run:
  System Settings > Privacy & Security > Full Disk Access
    - Terminal          (if you are running locally)
    - sshd-keygen-wrapper (if Claude is driving this over SSH; add it with the + button,
                           it lives at /usr/libexec/sshd-keygen-wrapper)
Or enable it by hand: System Settings > General > Sharing > Remote Login."
fi

kickstart=/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart
if [ -x "$kickstart" ]; then
  "$kickstart" -activate -configure -access -on -restart -agent -privs -all -allowAccessFor -allUsers
  ok "remote management activated for all users"
else
  gate "ARD kickstart not found at $kickstart.
Enable it by hand: System Settings > General > Sharing > Screen Sharing."
fi

/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on >/dev/null
ok "application firewall: enabled"
