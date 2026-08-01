#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

profile="${VM_PROFILE:-agent}"

if ! colima=$(colima_bin); then
  miss "colima not installed"
  verify_result
fi
ok "colima at $colima"

status=$("$colima" status --profile "$profile" 2>&1)
if printf '%s' "$status" | /usr/bin/grep -qi 'running'; then
  ok "VM '$profile' is running"
else
  miss "VM '$profile' is not running: $(printf '%s' "$status" | head -1)"
  verify_result
fi

# The whole isolation argument rests on this one. Colima mounts $HOME by default, so a
# VM that came up with a mount can read every credential and repo on the Mac.
cfg="$(_admin_home)/.colima/$profile/colima.yaml"
if [ ! -f "$cfg" ]; then
  miss "no profile config at $cfg"
else
  mounts=$(/usr/bin/awk '/^mounts:/{f=1;next} f&&/^[a-z]/{exit} f&&/location:/{print}' "$cfg")
  if [ -z "$mounts" ]; then
    ok "no host mounts configured"
  else
    miss "host mounts configured — the VM can read the Mac's filesystem:"
    printf '%s\n' "$mounts" | /usr/bin/sed 's/^/            /'
  fi
fi

# Ask the running VM rather than trusting the config file: a mount added by an older
# Colima's defaults would not appear above.
if live=$("$colima" ssh --profile "$profile" -- findmnt -t virtiofs,9p,sshfs -n 2>/dev/null); then
  if [ -z "$live" ]; then
    ok "no host filesystems mounted in the running VM"
  else
    miss "the running VM has host filesystems mounted:"
    printf '%s\n' "$live" | /usr/bin/sed 's/^/            /'
  fi
else
  note "could not inspect mounts inside the VM (ssh unavailable)"
fi

for var in VM_CPUS VM_MEMORY VM_DISK; do
  [ -n "${!var:-}" ] && ok "$var=${!var}" || miss "$var not recorded in server.env"
done

# Recording the numbers is not the same as the VM having them. `colima start` on a VM that
# is already up does not re-read the profile, so a pre-existing 'agent' VM — one you made
# by hand months ago, or one from an older run of this recipe — keeps whatever size it was
# built with while server.env confidently reports something else. Compare the live VM.
live=$("$colima" list --json 2>/dev/null | /usr/bin/grep "\"name\":\"$profile\"" || true)
if [ -z "$live" ]; then
  note "could not read live VM resources from 'colima list --json' — size not compared"
else
  live_cpus=$(printf '%s' "$live" | /usr/bin/sed -n 's/.*"cpus":\([0-9]*\).*/\1/p')
  live_mem_b=$(printf '%s' "$live" | /usr/bin/sed -n 's/.*"memory":\([0-9]*\).*/\1/p')

  if [ -n "$live_cpus" ] && [ -n "${VM_CPUS:-}" ]; then
    [ "$live_cpus" = "$VM_CPUS" ] \
      && ok "running VM has $live_cpus vCPU, matching VM_CPUS" \
      || miss "running VM has $live_cpus vCPU but VM_CPUS=$VM_CPUS — resize with 'colima stop --profile $profile' then re-apply"
  fi

  if [ -n "$live_mem_b" ] && [ -n "${VM_MEMORY:-}" ]; then
    live_mem=$(( live_mem_b / 1073741824 ))
    [ "$live_mem" = "$VM_MEMORY" ] \
      && ok "running VM has ${live_mem}G RAM, matching VM_MEMORY" \
      || miss "running VM has ${live_mem}G RAM but VM_MEMORY=$VM_MEMORY — resize with 'colima stop --profile $profile' then re-apply"
  fi
fi

plist="$(_admin_home)/Library/LaunchAgents/$VM_AGENT_LABEL.plist"
[ -f "$plist" ] && ok "auto-start agent at $plist" \
  || miss "no auto-start agent at $plist — the VM won't come back after a reboot"

verify_result
