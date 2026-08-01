# Shared helpers for cookbook recipes. Source this at the top of every apply.sh / verify.sh:
#
#   . "$(dirname "$0")/../../lib/common.sh"
#
# Exit code contract:
#   verify.sh — 0 satisfied, 1 not satisfied, 2 blocked (needs a human or an unmet external condition)
#   apply.sh  — 0 applied (or already satisfied), 1 failed, 3 stopped at a manual gate

set -euo pipefail

# Recipes run under sudo about half the time, and $HOME becomes /var/root when they do.
# The server state belongs to the admin user either way, so resolve their home explicitly.
_admin_home() {
  if [ -n "${SUDO_USER:-}" ]; then
    /usr/bin/dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}'
  else
    printf '%s' "$HOME"
  fi
}

STATE_DIR="${AGENT_MACHINE_STATE_DIR:-$(_admin_home)/.agent-machine}"
TS_AGENT_LABEL="com.agent-machine.tailscale-relaunch"
VM_AGENT_LABEL="com.agent-machine.agent-vm"
SERVER_ENV="$STATE_DIR/server.env"
SERVER_LEDGER="$STATE_DIR/server.md"
RUN_LOG="$STATE_DIR/run.log"

[ -f "$SERVER_ENV" ] && . "$SERVER_ENV"

# ---- output -----------------------------------------------------------------
# Recipes print one line per checked fact so a failed verify says which fact failed.

_unsatisfied=0
_blocked=0

ok()      { printf '  ok      %s\n' "$*"; }
miss()    { printf '  MISSING %s\n' "$*"; _unsatisfied=1; }
blocked() { printf '  BLOCKED %s\n' "$*"; _blocked=1; }
note()    { printf '  note    %s\n' "$*"; }
skip()    { printf '  n/a     %s\n' "$*"; }
die()     { printf 'error: %s\n' "$*" >&2; exit 1; }

# Call as the last line of verify.sh.
verify_result() {
  [ "$_blocked" -eq 1 ] && exit 2
  [ "$_unsatisfied" -eq 1 ] && exit 1
  exit 0
}

# Stop an apply.sh at a manual gate. Everything before the gate has already been applied.
gate() {
  printf '\nGATE — a human has to do this before the recipe can finish:\n%s\n' "$*"
  exit 3
}

# ---- server state --------------------------------------------------------------

# Anything written under sudo would otherwise land root-owned in the admin user's home.
_own_state_dir() {
  [ -n "${SUDO_USER:-}" ] && /usr/sbin/chown -R "$SUDO_USER" "$STATE_DIR" 2>/dev/null || true
}

need_var() {
  local name="$1"
  [ -n "${!name:-}" ] || die "$name is not set. Add it to $SERVER_ENV (see recipes/have-server-identity)."
}

# Persist a config value to server.env so later runs and later recipes can read it.
set_server_var() {
  local name="$1" value="$2"
  mkdir -p "$STATE_DIR"
  touch "$SERVER_ENV"
  chmod 600 "$SERVER_ENV"
  if grep -q "^${name}=" "$SERVER_ENV" 2>/dev/null; then
    /usr/bin/sed -i '' "s|^${name}=.*|${name}=\"${value}\"|" "$SERVER_ENV"
  else
    printf '%s="%s"\n' "$name" "$value" >>"$SERVER_ENV"
  fi
  _own_state_dir
  export "$name=$value"
}

# Append one line to the run log. Distinct from the ledger on purpose: the ledger is the
# server's current state, one row per recipe that verified clean, rewritten as things
# change. The log is the history — every attempt, gate, and failure, never pruned. When
# something went wrong three weeks ago, the ledger cannot tell you and this can.
log_event() {
  local event="$1" subject="${2:--}" detail="${3:-}"
  mkdir -p "$STATE_DIR"
  printf '%s  %-12s %-24s %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$event" "$subject" "$detail" >>"$RUN_LOG"
  _log_rotate
  _own_state_dir
}

# The log carries the full output of every apply, so on a long-lived server it grows
# without bound. Roll at 5MB and keep one previous file: enough history to diagnose
# something that happened weeks ago, bounded enough never to be the reason a disk fills.
_log_rotate() {
  local size
  size=$(/usr/bin/wc -c <"$RUN_LOG" 2>/dev/null || echo 0)
  [ "${size:-0}" -gt 5242880 ] || return 0
  /bin/mv "$RUN_LOG" "$RUN_LOG.1" 2>/dev/null || return 0
  printf '%s  %-12s %-24s %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "log-rolled" "-" "previous log kept at $(basename "$RUN_LOG").1" >>"$RUN_LOG"
}

# Record one recipe in the server ledger. Called by the driver after a successful verify,
# not by apply.sh itself — the ledger records what is true, not what was attempted.
#
# Exactly one row per recipe: the previous row is dropped before the new one is written.
# Appending instead would turn the ledger into a second, worse copy of run.log, and the
# whole reason both files exist is that they answer different questions — this one answers
# "what is this machine", the log answers "what happened to it".
record_applied() {
  local recipe="$1" detail="${2:-}" tmp
  mkdir -p "$STATE_DIR"
  [ -f "$SERVER_LEDGER" ] || printf '# Server ledger\n\n| Recipe | Applied (UTC) | Detail |\n|---|---|---|\n' >"$SERVER_LEDGER"

  tmp="$SERVER_LEDGER.tmp.$$"
  # grep exits 1 when it drops every line, which under set -e would abort the recipe.
  /usr/bin/grep -v "^| ${recipe} |" "$SERVER_LEDGER" >"$tmp" || true
  /bin/mv "$tmp" "$SERVER_LEDGER"

  printf '| %s | %s | %s |\n' "$recipe" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$detail" >>"$SERVER_LEDGER"
  _own_state_dir
}

# ---- secrets ----------------------------------------------------------------
#
# Three tiers, in the order secret_get tries them:
#   1. the environment  — the escape hatch for unattended runs; visible in ps
#   2. the Keychain     — stored once via a prompt, fetched silently thereafter
#   3. neither          — the recipe gates and tells the human how to store it
#
# What the Keychain buys: the value never reaches argv, shell history, or a Claude
# transcript. What it does not buy: protection from an agent running as this same admin
# user, which can call /usr/bin/security itself. See docs/secrets-and-egress.md.

SECRET_SERVICE="agent-machine"

# Read one Keychain item, without ever blocking. A locked keychain or an ACL that does not
# cover the caller makes `security` raise a GUI prompt, which on a headless server hangs
# forever — the one thing a recipe must never do. macOS ships no timeout(1), so the read is
# fenced with perl's alarm and a timeout is reported the same as "not found".
_keychain_read() {
  local account="$1" cmd
  # Under sudo the item lives in the admin user's keychain, not root's.
  if is_root && [ -n "${SUDO_USER:-}" ]; then
    cmd="/usr/bin/sudo -u $SUDO_USER /usr/bin/security"
  else
    cmd="/usr/bin/security"
  fi
  SECRET_ACCOUNT="$account" SECRET_CMD="$cmd" SECRET_SVC="$SECRET_SERVICE" /usr/bin/perl -e '
    eval {
      local $SIG{ALRM} = sub { die "timeout\n" };
      alarm 5;
      my $out = `$ENV{SECRET_CMD} find-generic-password -w -s $ENV{SECRET_SVC} -a $ENV{SECRET_ACCOUNT} 2>/dev/null`;
      alarm 0;
      exit 1 if $?;
      print $out;
      exit 0;
    };
    exit 1;
  '
}

# Resolve a secret into the named variable. Returns 1 if it is not available anywhere, so
# the caller can gate. Never prints the value.
secret_get() {
  local name="$1" value
  if [ -n "${!name:-}" ]; then
    note "$name supplied from the environment (visible in ps for the life of the command)"
    return 0
  fi
  value=$(_keychain_read "$name") || return 1
  [ -n "$value" ] || return 1
  export "$name=$value"
  note "$name read from the Keychain"
  return 0
}

# The exact command to store a secret, kept in one place so every gate says the same thing.
# No value on the command line — `security` prompts for it, so it stays out of argv and
# shell history.
secret_store_hint() {
  printf 'security add-generic-password -s %s -a %s -T /usr/bin/security -U -w' \
    "$SECRET_SERVICE" "$1"
}

# ---- macOS helpers ----------------------------------------------------------

# ComputerName is a human label and may contain spaces and capitals. LocalHostName,
# HostName, and Tailscale hostnames may not — macOS and Tailscale both silently rewrite
# them, which would leave verify comparing against a name that can never match. Every
# machine-facing name is derived from SERVER_NAME through here instead.
slugify() {
  printf '%s' "$1" \
    | /usr/bin/tr '[:upper:]' '[:lower:]' \
    | /usr/bin/sed -e 's/[^a-z0-9-]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

is_root() { [ "$(id -u)" -eq 0 ]; }
need_root() { is_root || die "run this recipe with sudo"; }

# Apple Silicon drops some pmset/systemsetup keys entirely. Treat an absent key as n/a
# rather than as a failure, so verify doesn't go red on hardware that can't have it.
pmset_val() { /usr/bin/pmset -g custom 2>/dev/null | /usr/bin/awk -v k="$1" '$1==k {print $2; exit}'; }

# systemsetup refuses to answer without root by printing a message and exiting 0, so the
# only way to tell "off" from "you didn't ask as root" is to match the text.
systemsetup_needs_root() { case "$1" in *administrator\ access*) return 0 ;; *) return 1 ;; esac; }

# Tailscale installs as a cask (GUI app) or a formula; find whichever CLI is present.
ts_cli() {
  for c in /Applications/Tailscale.app/Contents/MacOS/Tailscale \
           /opt/homebrew/bin/tailscale /usr/local/bin/tailscale; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

colima_bin() {
  for c in /opt/homebrew/bin/colima /usr/local/bin/colima; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# Run a command inside the agent VM. Recipes that configure the guest go through here so
# the profile name lives in one place.
vm_ssh() {
  local colima; colima=$(colima_bin) || return 1
  "$colima" ssh --profile "${VM_PROFILE:-agent}" -- "$@"
}

brew_bin() {
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && { printf '%s' "$b"; return 0; }
  done
  return 1
}
