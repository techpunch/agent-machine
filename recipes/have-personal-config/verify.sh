#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

home=$(_admin_home)
src="${PERSONAL_CONFIG_DIR:-$home/src}"

# Only the clones are checked. Whether the files are placed is not knowable from here — each repo
# decides its own layout, and inventing a marker file to test against would be asserting a
# convention these repos have not agreed to.
for repo in homedir claude-clojure-plus; do
  if [ -d "$src/$repo/.git" ]; then
    ok "$repo cloned at $src/$repo"
  else
    miss "$repo not cloned into $src"
  fi
done

verify_result
