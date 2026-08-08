#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

if brew=$(brew_bin); then
  ok "brew at $brew ($("$brew" --version 2>/dev/null | head -1))"
else
  miss "brew not found in /opt/homebrew/bin or /usr/local/bin"
  verify_result
fi

# A Mac that has been migrated from an Intel machine, or had Homebrew installed once under
# Rosetta, ends up with the x86 prefix. brew_bin would happily return it, and then every
# formula installed through it — colima included — is an x86 binary emulated on ARM. It
# works just well enough not to look broken.
if [ "$(/usr/bin/uname -m)" = "arm64" ] && [ "$brew" = "/usr/local/bin/brew" ]; then
  miss "this is an Apple Silicon Mac but brew is the Intel install at /usr/local — everything it installs will be x86 under Rosetta. Install the native one at /opt/homebrew."
fi

# Both prefixes present is common after a migration, and the danger is not having two but
# not knowing which one a fresh login shell will pick.
if [ -x /opt/homebrew/bin/brew ] && [ -x /usr/local/bin/brew ]; then
  note "two Homebrew installs present (/opt/homebrew and /usr/local)"
fi

# Match the specific brew, not the string "brew shellenv". With two installs present, a
# line pointing at the other prefix passes a substring check while putting the wrong brew
# on PATH for every login shell — including the ones later recipes run in.
# Homebrew reports to InfluxDB on every command unless told not to. Read the state through brew's
# own CLI rather than a config file, whose location has moved between versions. NO_AUTO_UPDATE
# because a verify has to stay cheap: without it this can trigger a full metadata refresh.
analytics=$(HOMEBREW_NO_AUTO_UPDATE=1 "$brew" analytics state 2>/dev/null) || analytics=""
case "$analytics" in
  *"analytics are disabled"*) ok "brew analytics off" ;;
  *"analytics are enabled"*)  miss "brew analytics on — brew reports home on every command" ;;
  *)                          skip "could not read brew analytics state" ;;
esac

profile="$(_admin_home)/.zprofile"
if grep -q "$brew shellenv" "$profile" 2>/dev/null; then
  ok "shellenv line for $brew present in $profile"
elif grep -q 'brew shellenv' "$profile" 2>/dev/null; then
  miss "$profile has a 'brew shellenv' line, but not for $brew — a fresh login shell would get the other Homebrew"
else
  miss "no 'brew shellenv' line in $profile — brew won't be on PATH in a fresh login shell"
fi

verify_result
