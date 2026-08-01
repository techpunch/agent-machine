#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

mkdir -p "$STATE_DIR"

# The server already has a name — adopt it rather than inventing one. SERVER_NAME in the
# environment wins, so you can still rename a server deliberately by exporting it.
computer=$(/usr/sbin/scutil --get ComputerName 2>/dev/null || true)
name="${SERVER_NAME:-$computer}"
[ -n "$name" ] || die "the machine has no ComputerName; set SERVER_NAME and re-run"

admin="${ADMIN_USER:-${SUDO_USER:-$(id -un)}}"
/usr/bin/dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -qw "$admin" \
  || die "user '$admin' is not an admin; run as an admin user or set ADMIN_USER"

slug=$(slugify "$name")
[ -n "$slug" ] || die "'$name' slugifies to nothing usable as a hostname; set SERVER_NAME explicitly"

set_server_var SERVER_NAME "$name"
set_server_var SERVER_SLUG "$slug"
set_server_var ADMIN_USER "$admin"
note "adopted SERVER_NAME=$name SERVER_SLUG=$slug ADMIN_USER=$admin"

# Seed the ledger before the part that can stop for lack of root, so a server always ends up
# with its state files even if the rename has to wait.
[ -f "$SERVER_LEDGER" ] || {
  {
    printf '# %s\n\n' "$name"
    printf 'Local record for this server. Not in the cookbook — `git pull` never touches it.\n'
    printf 'Config lives next door in `server.env`.\n\n'
    printf '| Recipe | Applied (UTC) | Detail |\n|---|---|---|\n'
  } >"$SERVER_LEDGER"
  _own_state_dir
  note "created ledger at $SERVER_LEDGER"
}

# Make the three scutil names agree. A GUI-named Mac routinely has a LocalHostName that
# differs, and Tailscale + SSH + Screen Sharing all key off different ones.
host=$(/usr/sbin/scutil --get HostName 2>/dev/null || true)
local_host=$(/usr/sbin/scutil --get LocalHostName 2>/dev/null || true)
if [ "$computer" != "$name" ] || [ "$host" != "$slug" ] || [ "$local_host" != "$slug" ]; then
  is_root || die "scutil names disagree and fixing them needs root — re-run with sudo"
  /usr/sbin/scutil --set ComputerName  "$name"
  /usr/sbin/scutil --set HostName      "$slug"
  /usr/sbin/scutil --set LocalHostName "$slug"
  note "set ComputerName=$name, HostName/LocalHostName=$slug"
fi
