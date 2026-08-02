#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# brew must not run as root, and the sbx login belongs to the admin user's config, not root's.
if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi
is_root && die "run this recipe as the admin user, not root"

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

# `sbx login` would re-prompt, so check first and only authenticate when we have to. One call,
# not two: each one can take the full timeout if the daemon is unhappy.
who=$(with_timeout 30 "$sbx" whoami 2>/dev/null | /usr/bin/tr -d '\r' || true)
if [ -n "$who" ]; then
  ok "already signed in to Docker as $who"
else
  # The username is config, not a secret — it goes in server.env like SERVER_NAME. Only the
  # token is Keychain material. Conflating the two would mean a username you cannot read back
  # without unlocking a keychain, for no benefit.
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
  printf '%s' "$DOCKER_PAT" | with_timeout 120 "$sbx" login --username "$DOCKER_USER" --password-stdin \
    || { unset DOCKER_PAT; die "sbx login failed — check the token is valid and has Read scope"; }
  unset DOCKER_PAT
  ok "signed in to Docker as $DOCKER_USER"
fi

# The network policy is the whole security posture, and it is also what stops the first `sbx run`
# prompting for a preset — a prompt on a server with nobody at the screen hangs rather than fails.
# So a failure here is a failure, not a warning: carrying on would leave a machine that looks set up
# and then stalls the first time somebody uses it.
#
# Do not gate this on `policy ls` succeeding first. On a fresh install there may be no policy to
# list, which is exactly when setting one matters most.
policy="${SBX_POLICY:-balanced}"
note "setting network policy preset: $policy"
if with_timeout 60 "$sbx" policy init "$policy" >/dev/null 2>&1; then
  set_server_var SBX_POLICY "$policy"
  ok "network policy preset: $policy"
else
  die "could not set the policy preset with 'sbx policy init $policy'.

Valid presets are allow-all, balanced and deny-all. If the command form has changed, fix
recipes/have-agent-sandbox/apply.sh rather than working around it here — see 'This project
corrects itself' in CLAUDE.md. An unset policy means the first 'sbx run' prompts, and a
prompt on a headless server hangs."
fi

# Default-deny fails quietly unless something makes it loud. The proxy is explicit — a blocked
# request gets `HTTP/1.1 403 Forbidden` with `Blocked by network policy: domain <host>` and the
# reason — but an agent that sees that will usually route around it and answer from memory, which
# reads as confident and is a worse outcome than being told it could not read the docs.
#
# The guidance that tells it not to lives in sandbox-CLAUDE.md next to this script. Installing it
# needs a running sandbox, since `~/.claude` is inside one, so it is a note rather than a step:
# there is no confirmed way to write that volume from the host without one.
note "install the sandbox guidance once, from inside your first sandbox:"
note "  sbx run --clone claude   # then paste recipes/have-agent-sandbox/sandbox-CLAUDE.md into ~/.claude/CLAUDE.md"

note "next: sbx run --clone claude   (then /login inside the sandbox, once)"
