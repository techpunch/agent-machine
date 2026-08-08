#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# These are the admin user's dotfiles, not root's. Cloning as root would leave a tree the
# admin user cannot write and a ~/src owned by the wrong account.
if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi
is_root && die "run this recipe as the admin user, not root"

home="$HOME"
src="${PERSONAL_CONFIG_DIR:-$home/src}"
mkdir -p "$src"

cloned=""
for repo in homedir claude-clojure-plus; do
  if [ -d "$src/$repo/.git" ]; then
    ok "$repo already cloned"
    continue
  fi
  note "cloning $repo"
  # HTTPS rather than SSH: the sandbox workflow already standardises on it, and a server with no
  # agent-forwarded key cannot use SSH remotes anyway.
  if /usr/bin/git -C "$src" clone "https://github.com/bobfejes/$repo.git" >/dev/null 2>&1; then
    ok "cloned $repo into $src"
    cloned="$cloned $repo"
  else
    gate "could not clone bobfejes/$repo into $src.

If the repo is private, this server needs a credential to read it. Authenticate once as the
admin user, then re-run:

  gh auth login                 # if the GitHub CLI is installed, easiest
  # or clone by hand with a token you paste at the prompt:
  git -C $src clone https://github.com/bobfejes/$repo.git

Then:
  ./bin/cookbook apply have-personal-config

If the repo has been renamed or moved, fix the URL in recipes/have-personal-config/apply.sh
rather than working around it here — see 'This project corrects itself' in CLAUDE.md."
  fi
done

set_server_var PERSONAL_CONFIG_DIR "$src"

# Placement is deliberately not automated. Each repo knows its own layout and this recipe does
# not, and the failure mode of guessing is overwriting ~/.zprofile or ~/.claude on a machine
# that is about to lose its keyboard.
gate "Both repos are cloned into $src. Placing the files is yours to do, because only the
repos know where their contents belong.

  cd $src/homedir              # follow its README, or run its install script
  cd $src/claude-clojure-plus  # same

Two things to watch as you do it:

  - have-coordination writes a managed ~/.tmux.conf and appends ~/.local/bin to ~/.zprofile.
    If your dotfiles carry either, run have-coordination after this so the managed files land
    on top, and decide deliberately which one you want to win.
  - Anything you place that sets credentials belongs on the host only. Sandboxes inherit
    nothing from this home directory, which is intentional.

Nothing else in the cookbook waits on this. When the files are where you want them, carry on:

  ./bin/cookbook status"
