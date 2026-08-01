#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# Colima and its VM belong to the logged-in user's session, not to root.
if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi
is_root && die "run this recipe as the admin user, not root"

brew=$(brew_bin) || die "Homebrew not installed — run have-homebrew first"
profile="${VM_PROFILE:-agent}"

colima_bin >/dev/null || { note "installing colima"; "$brew" install colima; }
colima=$(colima_bin) || die "colima install finished but the binary is not on disk"

# The target shape, sized for the reference server (a base M4 Mac mini: 10 cores, 16G,
# 256G). Most of the machine goes to the VM, because a server running this cookbook is
# doing nothing else. An agent that runs away is still bounded by the VM rather than
# taking the whole Mac down.
VM_CPUS_DEFAULT=6
VM_MEMORY_DEFAULT=10
VM_DISK_DEFAULT=100

# Clamped, not just defaulted, so a smaller machine gets a workable VM instead of a
# config it cannot honour. What is held back matters more than what is handed over: vz
# reserves the guest's memory outright rather than ballooning it, so an over-generous
# figure leaves macOS swapping rather than working.
if [ -z "${VM_CPUS:-}" ]; then
  cpu_total=$(/usr/sbin/sysctl -n hw.ncpu)
  cpu_want=$VM_CPUS_DEFAULT
  [ "$cpu_want" -gt "$(( cpu_total - 2 ))" ] && cpu_want=$(( cpu_total - 2 ))
  [ "$cpu_want" -lt 1 ] && cpu_want=1
  set_server_var VM_CPUS "$cpu_want"
fi

if [ -z "${VM_MEMORY:-}" ]; then
  mem_total=$(( $(/usr/sbin/sysctl -n hw.memsize) / 1073741824 ))
  mem_want=$VM_MEMORY_DEFAULT
  # Never leave macOS under 4G.
  [ "$mem_want" -gt "$(( mem_total - 4 ))" ] && mem_want=$(( mem_total - 4 ))
  [ "$mem_want" -lt 2 ] && die "only ${mem_total}G of RAM — too little to split with a VM"
  set_server_var VM_MEMORY "$mem_want"
fi

# Checked against free space, not total: on APFS the two differ a lot, and the number that
# matters is what the VM can actually grow into. Colima allocates this sparsely, so it is
# a ceiling rather than an upfront cost.
if [ -z "${VM_DISK:-}" ]; then
  disk_avail=$(/bin/df -g / | /usr/bin/awk 'NR==2 {print $4}')
  disk_want=$VM_DISK_DEFAULT
  # Hold back 40G for macOS updates and swap.
  [ "$disk_want" -gt "$(( disk_avail - 40 ))" ] && disk_want=$(( disk_avail - 40 ))
  [ "$disk_want" -lt 20 ] && die "only ${disk_avail}G free — free some space before building the VM"
  set_server_var VM_DISK "$disk_want"
fi

[ -z "${VM_PROFILE:-}" ] && set_server_var VM_PROFILE "$profile"

# Write the profile config before first start. `mounts: []` is what keeps the Mac's
# filesystem — SSH keys, cloud credentials, every repo — out of the guest.
cfg_dir="$HOME/.colima/$profile"
mkdir -p "$cfg_dir"
cat >"$cfg_dir/colima.yaml" <<YAML
# Managed by the agent-machine cookbook (recipes/have-agent-vm). Edits are overwritten.
cpu: $VM_CPUS
memory: $VM_MEMORY
disk: $VM_DISK
vmType: vz
mountType: virtiofs
# No host mounts. See docs/secrets-and-egress.md — this is the isolation boundary.
mounts: []
YAML
ok "wrote profile config $cfg_dir/colima.yaml"

if "$colima" status --profile "$profile" 2>&1 | /usr/bin/grep -qi running; then
  ok "VM '$profile' already running"
  # Starting a running VM does not re-read the profile, so the config written above has
  # not taken effect and will not until it is stopped. Say so rather than letting verify
  # be the first thing that notices.
  note "config changes need 'colima stop --profile $profile' then re-apply; a running VM keeps the size it was built with"
else
  note "starting VM '$profile' (${VM_CPUS} cpu, ${VM_MEMORY}G ram, ${VM_DISK}G disk)"
  "$colima" start --profile "$profile" || die "colima start failed"
fi

# Auto-start with the session, same LaunchAgent pattern as have-tailscale.
agents="$HOME/Library/LaunchAgents"
plist="$agents/$VM_AGENT_LABEL.plist"
mkdir -p "$agents"
cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$VM_AGENT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$colima</string>
    <string>start</string>
    <string>--profile</string>
    <string>$profile</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$(dirname "$colima"):/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
</dict>
</plist>
PLIST
ok "wrote auto-start agent $plist"

uid=$(id -u)
/bin/launchctl bootout "gui/$uid/$VM_AGENT_LABEL" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$uid" "$plist" 2>/dev/null \
  || note "could not bootstrap the agent in this session; it will load at next login"
