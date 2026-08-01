#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# Homebrew refuses to run as root. If the driver was invoked with sudo, hand this
# recipe back to the admin user.
if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER (Homebrew must not run as root)"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi
is_root && die "run this recipe as the admin user, not root"

if ! brew_bin >/dev/null; then
  note "installing Homebrew"
  # NONINTERACTIVE stops the installer waiting on a keypress nobody is there to press.
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

brew=$(brew_bin) || die "Homebrew install finished but brew is still not on disk"

profile="$HOME/.zprofile"
if ! grep -q 'brew shellenv' "$profile" 2>/dev/null; then
  printf 'eval "$(%s shellenv)"\n' "$brew" >>"$profile"
  note "added brew shellenv to $profile"
fi

eval "$("$brew" shellenv)"
ok "$("$brew" --version | head -1)"
