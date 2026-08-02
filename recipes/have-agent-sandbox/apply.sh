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

# Already signed in? `sbx login` is not idempotent in the useful sense — it would re-prompt — so
# check first and only authenticate when we have to.
if with_timeout 30 "$sbx" whoami >/dev/null 2>&1; then
  ok "already signed in to Docker as $(with_timeout 30 "$sbx" whoami 2>/dev/null | /usr/bin/tr -d '\r')"
else
  if ! secret_get DOCKER_PAT; then
    gate "have-agent-sandbox needs a Docker personal access token to sign sbx in.

Create one at https://app.docker.com/settings/personal-access-tokens
  Scope: Read is enough. sbx only needs to authenticate, not publish.

Then store it in the Keychain, as the admin user (not with sudo). The command takes no
value — it prompts, so the token never lands in your shell history or in ps:
  $(secret_store_hint DOCKER_PAT)

You will also need your Docker account username. Set it once:
  ./bin/cookbook apply have-agent-sandbox   # after storing DOCKER_USER below

  security add-generic-password -s $SECRET_SERVICE -a DOCKER_USER -T /usr/bin/security -U -w

Then re-run:
  ./bin/cookbook apply have-agent-sandbox"
  fi

  secret_get DOCKER_USER || die "DOCKER_USER not found — store your Docker username the same way as the token"

  # --password-stdin keeps the token out of argv, where any local user could read it from ps.
  # This is also what makes the login work with no browser, which a headless server has none of.
  printf '%s' "$DOCKER_PAT" | with_timeout 120 "$sbx" login --username "$DOCKER_USER" --password-stdin \
    || die "sbx login failed — check the token is valid and has Read scope"
  unset DOCKER_PAT
  ok "signed in to Docker as $DOCKER_USER"
fi

# The network policy. Left unset, the first `sbx run` prompts interactively for a preset, which on a
# server with nobody at the screen would hang rather than fail. Set it here instead.
policy="${SBX_POLICY:-balanced}"
if with_timeout 30 "$sbx" policy ls >/dev/null 2>&1; then
  note "applying network policy preset: $policy"
  # The exact subcommand is the one thing here not confirmed against a real install. If this is
  # wrong, the error will say so — fix it here rather than working around it at the call site.
  with_timeout 60 "$sbx" policy init "$policy" >/dev/null 2>&1 \
    || note "could not set the preset with 'sbx policy init $policy' — check 'sbx policy --help' and fix this recipe"
else
  note "sbx policy is not answering; the preset has not been set"
fi
set_server_var SBX_POLICY "$policy"

note "next: sbx run --clone claude   (then /login inside the sandbox, once)"
