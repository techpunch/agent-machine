#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

cli=$(ts_cli) || { miss "tailscale not installed"; verify_result; }

status=$("$cli" status --json 2>/dev/null || true)
[ -n "$status" ] || { miss "tailscale not running or not logged in"; verify_result; }

backend=$(printf '%s' "$status" | /usr/bin/plutil -extract BackendState raw -o - - 2>/dev/null || true)
case "$backend" in
  Running) ok "backend state: Running" ;;
  *)       miss "backend state: ${backend:-unknown}" ;;
esac

# Tailscale lowercases and hyphenates whatever you give it, so compare against the slug,
# not the human ComputerName.
want="${SERVER_SLUG:-$(slugify "${SERVER_NAME:-}")}"
# DNSName is the authoritative tailnet name. HostName is only what the client reported,
# which on a macOS GUI client is the unsanitized ComputerName until --hostname is passed.
dns=$(printf '%s' "$status" | /usr/bin/plutil -extract Self.DNSName raw -o - - 2>/dev/null || true)
name="${dns%%.*}"
[ -n "$name" ] || name=$(printf '%s' "$status" | /usr/bin/plutil -extract Self.HostName raw -o - - 2>/dev/null || true)
if [ -n "$want" ] && [ "$name" != "$want" ]; then
  miss "tailnet node name is '$name', expected '$want'"
else
  ok "tailnet node name: $name"
fi

if printf '%s' "$status" | grep -q '"tag:host"'; then
  ok "node is tagged tag:host"
else
  miss "node is not tagged tag:host — it was probably joined interactively, not with a tagged key"
fi

ip=$("$cli" ip -4 2>/dev/null | head -1 || true)
if [ -z "$ip" ]; then
  miss "no tailscale IPv4 address"
elif [ "${TS_IP:-}" = "$ip" ]; then
  ok "tailscale IP: $ip"
else
  # Recording it is apply's job — a verify that writes is a verify you stop trusting.
  miss "tailscale IP is $ip but server.env says '${TS_IP:-unset}' — run apply to record it"
fi

verify_result
