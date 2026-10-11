#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# brew must not run as root, and the sbx login belongs to the admin user's config, not root's.
if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi
is_root && die "run this recipe as the admin user, not root"

COOKBOOK_KIT="$(cd "$(dirname "$0")" && pwd)/kit"

brew=$(brew_bin) || die "Homebrew not installed — run have-homebrew first"

if sbx=$(sbx_bin); then
  ok "sbx at $sbx"
else
  note "installing Docker Sandboxes"
  "$brew" tap docker/tap >/dev/null 2>&1 || true
  "$brew" install docker/tap/sbx || die "could not install sbx"
  sbx=$(sbx_bin) || die "sbx install finished but the binary is not on PATH"
  ok "installed $sbx"
fi

# sbx has no command that reports who is signed in — no `whoami` in the CLI reference or the binary
# — so there is nothing to check first. Sign in every time instead: `--password-stdin` with the
# stored token is idempotent, needs no browser, and verify proves it worked by creating a sandbox.
# The username is config, not a secret — it goes in server.env like SERVER_NAME. Only the token is
# Keychain material. Conflating the two would mean a username you cannot read back without unlocking
# a keychain, for no benefit.
if [ -z "${DOCKER_USER:-}" ]; then
  gate "have-agent-sandbox needs your Docker account, in two parts.

1. Your Docker username. Not a secret, so pass it once and it is recorded in server.env:

     DOCKER_USER=<your-docker-id> ./bin/cookbook apply have-agent-sandbox

2. A personal access token, which is a secret. Create one at
   https://app.docker.com/settings/personal-access-tokens — Read scope is enough, since sbx
   only needs to authenticate, not publish.

   Store it in the Keychain as the admin user (not with sudo). The command takes no value —
   it prompts, so the token never reaches your shell history or ps:

     $(secret_store_hint DOCKER_PAT)

Do both, then re-run the command in step 1. Stored once, later servers reuse the token."
fi
set_server_var DOCKER_USER "$DOCKER_USER"

if ! secret_get DOCKER_PAT; then
  gate "have-agent-sandbox needs a Docker personal access token to sign sbx in.

Create one at https://app.docker.com/settings/personal-access-tokens — Read scope is enough.
Then store it in the Keychain, as the admin user (not with sudo):

  $(secret_store_hint DOCKER_PAT)

Then re-run:
  ./bin/cookbook apply have-agent-sandbox"
fi

# --password-stdin keeps the token out of argv, where any local user could read it from ps.
# It is also what makes the login work with no browser, which a headless server has none of.
printf '%s' "$DOCKER_PAT" | with_timeout 120 "$sbx" login --username "$DOCKER_USER" --password-stdin >/dev/null \
  || { unset DOCKER_PAT; die "sbx login failed — check the token is valid and has Read scope"; }
unset DOCKER_PAT
ok "signed in to Docker as $DOCKER_USER"

# The preset is allow-all: what this machine protects is the Mac, not the network, and agents have
# to be able to read any documentation site. Setting one is also what stops the first sandbox
# prompting for a preset — a prompt on a server with nobody at the screen hangs rather than fails.
# So a failure here is a failure, not a warning: carrying on would leave a machine that looks set up
# and then stalls the first time somebody uses it. SBX_POLICY=balanced on a first run picks the
# stricter preset instead; docs/secrets-and-egress.md says when you would want it.
#
# `policy init` is documented as one-time setup — "once initialized, use sbx policy reset to start
# over" — so it runs only while no preset is recorded in server.env. Read the file, not the variable:
# SBX_POLICY=deny-all on the command line is how a first run picks a different preset. Do not gate
# it on `policy ls` succeeding first: on a fresh install there may be no policy to list, which is
# exactly when setting one matters most.
if /usr/bin/grep -q '^SBX_POLICY=' "$SERVER_ENV" 2>/dev/null; then
  ok "network policy preset: $SBX_POLICY (initialized once; 'sbx policy reset' starts over)"
else
  policy="${SBX_POLICY:-allow-all}"
  note "setting network policy preset: $policy"
  # Valid presets are allow-all, balanced and deny-all.
  if with_timeout 60 "$sbx" policy init "$policy" >/dev/null 2>&1; then
    set_server_var SBX_POLICY "$policy"
    ok "network policy preset: $policy"
  else
    die "could not set the policy preset with 'sbx policy init $policy'.

If sbx already has a policy and server.env lost the record of it, init refuses because it is
one-time. 'sbx policy reset' clears it — it stops running sandboxes — and then re-run this.
Otherwise, if the command form has changed, fix recipes/have-agent-sandbox/apply.sh rather
than working around it here — see 'This project corrects itself' in CLAUDE.md. An unset
policy means the first 'sbx run' prompts, and a prompt on a headless server hangs."
  fi
fi

# allow-all is `sbx policy allow network "**"`, and since Docker's August 2026 docs change neither
# the host nor private ranges are on the list of things blocked regardless of policy. A sandbox
# reaches the Mac's own services through host.docker.internal, which the proxy turns into
# localhost, and the Mac's LAN and tailnet addresses are private ranges. Deny rules outrank every
# allow, `**` included, so these keep the Mac out while the internet stays open. LAN devices go
# with them; nothing here needs them. The IPv6 rules cover loopback, unique-local (the tailnet's
# IPv6 range is one) and link-local. Each line is the rule and an address `policy check` can test it
# with, so a rule already in place is not added twice; for an IPv6 rule its own text in `policy ls`
# counts too, in case `policy check` reads an IPv6 address differently. Docker refuses a deny that
# repeats an allow for the very same resource (docker/sbx-releases#610), but these are ranges under
# `**`, which its docs describe as the way to block destinations under a broad allow.
deny_rules="localhost localhost
127.0.0.0/8 127.0.0.1
host.docker.internal host.docker.internal
10.0.0.0/8 10.0.0.1
172.16.0.0/12 172.16.0.1
192.168.0.0/16 192.168.1.1
169.254.0.0/16 169.254.169.254
100.64.0.0/10 100.100.100.100
::1/128 ::1
fc00::/7 fd00::1
fe80::/10 fe80::1"
rules_now=$(with_timeout 30 "$sbx" policy ls 2>/dev/null || true)
while read -r rule probe; do
  if with_timeout 30 "$sbx" policy check network "$probe" 2>/dev/null | /usr/bin/grep -q '^Denied' \
     || { case "$rule" in *:*) printf '%s\n' "$rules_now" | /usr/bin/grep -qF -- "$rule" ;; *) false ;; esac; }; then
    ok "sandboxes cannot reach $rule"
  else
    with_timeout 30 "$sbx" policy deny network "$rule" >/dev/null \
      || die "could not add a deny rule with 'sbx policy deny network $rule'"
    ok "denied sandbox access to $rule"
  fi
done <<EOF
$deny_rules
EOF

# sbx forwards the host's SSH agent into every sandbox by default, and on this machine that agent
# is whatever you brought with `ssh -A`. Any process in a sandbox could then ask it to sign — which
# is a push credential in a sandbox by another route. The daemon restart applies it to forwarders
# that already exist, so it only runs when the setting actually changed.
fwd=$(with_timeout 30 "$sbx" settings get ssh.agentForwardingEnabled 2>/dev/null | /usr/bin/tr -d '\r' || true)
if [ "$fwd" = "false" ]; then
  ok "SSH agent forwarding into sandboxes is off"
else
  with_timeout 30 "$sbx" settings set ssh.agentForwardingEnabled false >/dev/null \
    || die "could not turn off SSH agent forwarding with 'sbx settings set ssh.agentForwardingEnabled false'"
  with_timeout 120 "$sbx" daemon restart >/dev/null || die "set the forwarding setting but 'sbx daemon restart' failed"
  ok "turned off SSH agent forwarding into sandboxes"
fi

# A sandbox does not inherit any host-side agent config — ~/.claude on the Mac stays on the Mac.
# The supported way to give every sandbox the same defaults is a kit, which is also a committed
# file, so the guidance on how to work here lives in this repo rather than one machine's local
# state. have-shared-sandbox loads it when it creates the sandbox.
kit="$COOKBOOK_KIT"
[ -d "$kit" ] && set_server_var SBX_KIT "$kit"
# A kit sbx cannot parse would otherwise surface only when the sandbox is created. `kit inspect`
# reads it with the installed sbx's own schema, so a field this version rejects fails here.
with_timeout 30 "$sbx" kit inspect "$kit" >/dev/null \
  || die "sbx cannot read the kit at $kit — 'sbx kit inspect $kit' says why"
ok "kit readable by this sbx"

note "next: have-shared-sandbox creates the one sandbox every agent runs in"
