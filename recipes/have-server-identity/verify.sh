#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

[ -f "$SERVER_ENV" ] && ok "server.env exists at $SERVER_ENV" || miss "server.env not found at $SERVER_ENV"
if [ ! -f "$SERVER_LEDGER" ]; then
  miss "ledger not found at $SERVER_LEDGER"
# The heading is the ledger's only claim about which machine it describes, and a rename
# leaves it naming the old one. Checked here rather than assumed, because a server set up
# before apply learned to retitle keeps the stale name for good otherwise — apply never runs
# again on a recipe that verifies clean.
elif [ -n "${SERVER_NAME:-}" ] && [ "$(/usr/bin/head -1 "$SERVER_LEDGER")" != "# $SERVER_NAME" ]; then
  miss "ledger at $SERVER_LEDGER is titled '$(/usr/bin/head -1 "$SERVER_LEDGER")', not '# $SERVER_NAME'"
else
  ok "ledger exists at $SERVER_LEDGER"
fi

if [ -n "${SERVER_NAME:-}" ]; then
  ok "SERVER_NAME=$SERVER_NAME"
else
  miss "SERVER_NAME not set"
fi

computer=$(/usr/sbin/scutil --get ComputerName 2>/dev/null || true)
host=$(/usr/sbin/scutil --get HostName 2>/dev/null || true)
local_host=$(/usr/sbin/scutil --get LocalHostName 2>/dev/null || true)

if [ -n "${SERVER_NAME:-}" ] && [ "$computer" != "$SERVER_NAME" ]; then
  miss "ComputerName is '$computer', server.env says '$SERVER_NAME'"
elif [ -n "$computer" ]; then
  ok "ComputerName=$computer"
fi

slug=$(slugify "${SERVER_NAME:-$computer}")
if [ -n "${SERVER_SLUG:-}" ] && [ "$SERVER_SLUG" != "$slug" ]; then
  miss "SERVER_SLUG=$SERVER_SLUG does not match SERVER_NAME '$SERVER_NAME' (expected '$slug')"
else
  ok "SERVER_SLUG=$slug"
fi

[ "$host" = "$slug" ] || miss "HostName is '${host:-unset}', expected '$slug'"
[ "$local_host" = "$slug" ] || miss "LocalHostName is '${local_host:-unset}', expected '$slug'"

if [ -n "${ADMIN_USER:-}" ]; then
  if /usr/bin/dscl . -read "/Groups/admin" GroupMembership 2>/dev/null | grep -qw "$ADMIN_USER"; then
    ok "ADMIN_USER=$ADMIN_USER is in the admin group"
  else
    miss "ADMIN_USER=$ADMIN_USER is not in the admin group"
  fi
else
  miss "ADMIN_USER not set"
fi

verify_result
