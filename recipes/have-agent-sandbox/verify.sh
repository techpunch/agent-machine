#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

if sbx=$(sbx_bin); then
  ok "sbx at $sbx ($(with_timeout 20 "$sbx" version 2>/dev/null | /usr/bin/head -1 | /usr/bin/tr -d '\r'))"
else
  miss "sbx not installed"
  [ -f "$(cd "$(dirname "$0")" && pwd)/kit/spec.yaml" ] \
  && ok "kit present (denial guidance and doc allowlist)" \
  || miss "no kit/spec.yaml beside this recipe"

verify_result
fi

# Every call is time-limited. sbx talks to a host daemon and, when signed out, to Docker's servers;
# either can stall, and a verify that hangs is worse on a headless box than one that fails.
who=$(with_timeout 30 "$sbx" whoami 2>/dev/null | /usr/bin/tr -d '\r')
if [ -n "$who" ]; then
  ok "signed in to Docker as $who"
  [ -n "${DOCKER_USER:-}" ] || miss "DOCKER_USER not recorded in server.env — run apply so a rebuild knows which account"
else
  miss "not signed in — apply will gate for a Docker personal access token"
  verify_result
fi

# The policy is the whole security posture, so check what is live rather than trusting server.env.
if policy_out=$(with_timeout 30 "$sbx" policy ls 2>/dev/null); then
  if [ -z "${SBX_POLICY:-}" ]; then
    miss "no SBX_POLICY recorded in server.env — run apply"
  elif printf '%s' "$policy_out" | /usr/bin/grep -qi "$SBX_POLICY"; then
    ok "network policy preset: $SBX_POLICY"
  else
    miss "active policy does not look like the recorded '$SBX_POLICY' — re-run apply, or reconcile by hand"
  fi
else
  blocked "could not read the active policy from sbx; the network posture is unverified, not proven good"
fi

# Behaviour, not configuration. A sandbox that cannot be created means the whole layer is decorative,
# and that is worth finding out here rather than the first time somebody wants to work.
probe="verify-probe-$$"
if with_timeout 180 "$sbx" create --name "$probe" >/dev/null 2>&1; then
  ok "created a probe sandbox"
  with_timeout 60 "$sbx" rm "$probe" >/dev/null 2>&1 \
    && ok "removed it again" \
    || miss "created sandbox '$probe' but could not remove it — clean up with: sbx rm $probe"
else
  miss "could not create a sandbox — sbx is installed and signed in but not working"
fi

verify_result
