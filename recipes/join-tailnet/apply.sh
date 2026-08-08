#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"
need_root
need_var SERVER_SLUG

cli=$(ts_cli) || die "tailscale not installed — run have-tailscale first"

# "Connected" is not the same as "connected the way this cookbook needs". A Mac that was
# already signed in — to a personal account, interactively, under its own name — reports
# Running while being untagged, wrongly named, and carrying a 90-day key expiry that will
# silently drop it off the tailnet. Treating that as done is how you get a verify that
# fails forever while apply insists there is nothing to do.
status=$("$cli" status --json 2>/dev/null || true)
connected=false
matches=true
printf '%s' "$status" | grep -q '"BackendState" *: *"Running"' && connected=true

if $connected; then
  dns=$(printf '%s' "$status" | /usr/bin/plutil -extract Self.DNSName raw -o - - 2>/dev/null || true)
  have_name="${dns%%.*}"
  [ "$have_name" = "$SERVER_SLUG" ] || { matches=false; note "joined as '$have_name', wanted '$SERVER_SLUG'"; }
  printf '%s' "$status" | grep -q '"tag:host"' || { matches=false; note "existing node is not tagged tag:host"; }
fi

if $connected && $matches; then
  ok "already connected to the tailnet as $SERVER_SLUG with tag:host"
else
  if $connected; then
    note "re-joining with a tagged key to correct the above"
  fi

  if ! secret_get TS_AUTHKEY; then
    gate "join-tailnet needs a Tailscale tag:host pre-auth key.

To mint one, in the Tailscale admin console signed in as the tailnet owner:
  1. Access controls — check the ACL policy has a tagOwners entry for tag:host, e.g.
       \"tagOwners\": { \"tag:host\": [\"<your-account>\"] }
     The tag has to exist before a key can carry it. Full context: docs/shared-setup.md
  2. Settings > Keys > Generate auth key.
  3. On that form, top to bottom:
       Description  what it provisions and when, e.g. 'agent-machine servers (tag:host)'
       Reusable     ON   — the same key provisions the next server too
       Expiration   90 days, the maximum offered. This expires the key, not the nodes it
                    authenticated: a tagged node's own key never expires, so servers already
                    joined stay joined. What you lose in 90 days is provisioning the next one.
       Ephemeral    OFF  — an ephemeral node is removed when it goes offline
       Tags         ON, set to tag:host — this is also what disables key expiry for the node
       Pre-approved ON, if the field is there at all. It only appears when your tailnet
                    requires device approval; on most tailnets there is nothing to do.
  4. Generate and copy the tskey-auth-... value.

Then store it in the Keychain, as the admin user (not with sudo). The command takes no
value — it prompts, so the key never lands in your shell history or in ps:
  $(secret_store_hint TS_AUTHKEY)

Paste the key at the prompt, then re-run:
  ./bin/cookbook apply join-tailnet

Stored once, it provisions every later server too. If you would rather not store it, the
one-shot form still works, at the cost of the key being visible in ps while it runs:
  TS_AUTHKEY='tskey-auth-...' ./bin/cookbook apply join-tailnet"
  fi
  # Hand the key over in a file rather than on the command line: --authkey=<value> would
  # put it in argv, where any local user can read it out of ps for the life of the command.
  keyfile=$(/usr/bin/mktemp -t ts-authkey) || die "could not create a temp file for the key"
  trap 'rm -f "$keyfile"' EXIT INT TERM
  chmod 600 "$keyfile"
  printf '%s' "$TS_AUTHKEY" >"$keyfile"
  unset TS_AUTHKEY

  # --force-reauth is what makes this work on a machine that was already signed in: without
  # it, `up` on a Running node keeps the existing identity and quietly ignores the key, so
  # the wrong name and missing tag survive. --reset drops leftover flags from whatever the
  # previous setup did (advertised routes, exit-node settings, custom DNS).
  reauth=""
  $connected && reauth="--force-reauth --reset"
  # shellcheck disable=SC2086
  "$cli" up $reauth --hostname="$SERVER_SLUG" --auth-key="file:$keyfile" --accept-dns=false
  rm -f "$keyfile"
  ok "joined the tailnet as $SERVER_SLUG"

  # The old node object does not disappear on its own. It keeps the name, which is why the
  # new one can end up as <name>-1, and it is the thing to delete in the admin console.
  $connected && note "the machine's previous tailnet node may still exist in the admin console — delete it there if the name looks wrong"
fi

ip=$("$cli" ip -4 2>/dev/null | head -1 || true)
[ -n "$ip" ] && set_server_var TS_IP "$ip" && ok "tailscale IP: $ip"
