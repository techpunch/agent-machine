#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

if sbx=$(sbx_bin); then
  ok "sbx at $sbx ($(with_timeout 20 "$sbx" version 2>/dev/null | /usr/bin/head -1 | /usr/bin/tr -d '\r'))"
else
  miss "sbx not installed"
  verify_result
fi

# Every call is time-limited. sbx talks to a host daemon and, when signed out, to Docker's servers;
# either can stall, and a verify that hangs is worse on a headless box than one that fails.
[ -n "${DOCKER_USER:-}" ] && ok "Docker account recorded: $DOCKER_USER" \
  || miss "DOCKER_USER not recorded in server.env — run apply so a rebuild knows which account"

# sbx does not name its preset anywhere it can be read back — `policy ls` summarises rules, not the
# preset they came from — so this proves a policy exists and reports the recorded preset as recorded.
if policy_out=$(with_timeout 30 "$sbx" policy ls 2>/dev/null) && [ -n "$policy_out" ]; then
  if [ -n "${SBX_POLICY:-}" ]; then
    ok "a network policy is initialized (preset recorded as $SBX_POLICY)"
  else
    miss "a network policy exists but no SBX_POLICY is recorded in server.env — run apply"
  fi
else
  miss "no network policy readable from 'sbx policy ls' — the first 'sbx run' would prompt for one"
fi

kit="$(cd "$(dirname "$0")" && pwd)/kit"
with_timeout 30 "$sbx" kit inspect "$kit" >/dev/null 2>&1 \
  && ok "kit readable by this sbx" \
  || miss "sbx cannot read the kit at $kit — 'sbx kit inspect $kit' says why"

fwd=$(with_timeout 30 "$sbx" settings get ssh.agentForwardingEnabled 2>/dev/null | /usr/bin/tr -d '\r')
case "$fwd" in
  false) ok "SSH agent forwarding into sandboxes is off" ;;
  true)  miss "SSH agent forwarding into sandboxes is on — any sandbox can ask your agent to sign" ;;
  *)     blocked "could not read ssh.agentForwardingEnabled from sbx; forwarding is unverified" ;;
esac

# Behaviour, not configuration. A sandbox that cannot be created means the whole layer is decorative,
# and that is worth finding out here rather than the first time somebody wants to work. It is also
# the only proof of the Docker sign-in: sbx has no command that reports who is signed in. `shell` with
# no path is a mountless sandbox, so the probe touches nothing on the host.
probe="verify-probe-$$"
if with_timeout 180 "$sbx" create --pull missing --name "$probe" shell >/dev/null 2>&1; then
  ok "signed in and able to create a sandbox"
  # The wall around the Mac, tested by behaviour: `policy check` has reported a host deny rule that
  # the proxy did not enforce (docker/sbx-releases#546). sshd speaks first, so reading "SSH-" back
  # means the connection reached it. Tried by the host name sbx provides and by the Mac's own
  # LAN and tailnet addresses.
  targets="host.docker.internal"
  lan=$(/usr/sbin/ipconfig getifaddr en0 2>/dev/null || /usr/sbin/ipconfig getifaddr en1 2>/dev/null || true)
  [ -n "$lan" ] && targets="$targets $lan"
  ts=$(ts_cli) && tsip=$("$ts" ip -4 2>/dev/null | /usr/bin/head -1) && [ -n "$tsip" ] \
    && targets="$targets $tsip"
  for t in $targets; do
    if with_timeout 30 "$sbx" exec "$probe" bash -c \
        "timeout 8 bash -c 'exec 3<>/dev/tcp/$t/22 && head -c 4 <&3'" 2>/dev/null | /usr/bin/grep -q '^SSH-'; then
      miss "a sandbox reached the Mac's SSH at $t:22 — the deny rules are not holding"
    else
      ok "a sandbox cannot reach the Mac's SSH at $t:22"
    fi
  done
  # Since sbx v0.45.0 removal asks for confirmation; nobody is there to answer it.
  with_timeout 60 "$sbx" rm --force "$probe" >/dev/null 2>&1 \
    && ok "removed the probe sandbox again" \
    || miss "created sandbox '$probe' but could not remove it — clean up with: sbx rm --force $probe"
else
  miss "could not create a sandbox — signed out, or the daemon is unhappy; 'sbx diagnose' says which"
fi

verify_result
