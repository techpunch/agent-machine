#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# The secret belongs to the admin user's sbx store, not root's.
if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi
is_root && die "run this recipe as the admin user, not root"

sbx=$(sbx_bin) || die "sbx not installed — run have-agent-sandbox first"

# `sbx secret ls --service github` prints a header and one row per stored github secret, so a row
# naming github is the stored token. The value is masked in that output and never read here.
if with_timeout 30 "$sbx" secret ls -g --service github 2>/dev/null | /usr/bin/tail -n +2 | /usr/bin/grep -qw github; then
  ok "a GitHub token is stored in sbx and injected into every sandbox"
  exit 0
fi

# The token is typed by the human, not passed here: `sbx secret set github` prompts for it, so it
# never reaches argv, shell history, server.env or this transcript.
gate "join-github needs a GitHub token for agents to push branches with.

Make it first — a fine-grained token limited to the repos agents work on, and a rule on
each repo that stops anything landing on main without a pull request. Both are in
prereqs/github-token.md.

Then store it with sbx, as the admin user (not with sudo). The command prompts for the
token, so it never reaches your shell history or ps:

  $sbx secret set github

The proxy injects it into requests to github.com and api.github.com from every sandbox;
no sandbox can read it. Then re-run:

  ./bin/cookbook apply join-github"
