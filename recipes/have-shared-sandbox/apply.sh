#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# The sandbox belongs to the admin user's sbx, not root's.
if is_root && [ -n "${SUDO_USER:-}" ]; then
  note "re-running as $SUDO_USER"
  exec /usr/bin/sudo -u "$SUDO_USER" -H "$0" "$@"
fi
is_root && die "run this recipe as the admin user, not root"

sbx=$(sbx_bin) || die "sbx not installed — run have-agent-sandbox first"
kit="$(cd "$(dirname "$0")/../have-agent-sandbox" && pwd)/kit"
name="${SBX_SANDBOX:-agents}"

# One sandbox holds every project, so it gets more disk than the 20 GB default. Disk, memory and
# CPUs are all fixed when the sandbox is created — changing them later means recreating it, which
# throws away every checkout inside. Memory and CPUs keep sbx's defaults: half the host's memory
# (capped at 32 GiB) and all its CPUs.
export DOCKER_SANDBOXES_ROOT_SIZE="${DOCKER_SANDBOXES_ROOT_SIZE:-100g}"

if with_timeout 30 "$sbx" ls -q 2>/dev/null | /usr/bin/grep -qx "$name"; then
  ok "sandbox '$name' exists"
else
  # No path after the agent: a mountless sandbox. Nothing from the Mac is visible inside it, which
  # is the whole point — the repos are cloned in, and the .git/config attack in
  # docs/pushing-agent-code.md has no host folder to land in. `claude` is not who the sandbox is
  # for — every agent runs in it. It picks the base kit, and Docker's claude kit is what makes
  # `/login` inside the sandbox store the sign-in on the Mac and inject it; the binary it ships is
  # incidental, since the kit updates it at every start.
  # The kit seeds Codex's config from how the openai credential resolves when the sandbox is
  # created, so the Codex sign-in has to exist first — stored afterwards, Codex stays signed out
  # until the sandbox is recreated, which costs every checkout in it. CODEX=off creates it anyway.
  if [ "${CODEX:-on}" != off ]; then
    if out=$(with_timeout 30 "$sbx" secret ls -g --service openai 2>/dev/null) \
       && printf '%s\n' "$out" | /usr/bin/tail -n +2 | /usr/bin/grep -qw openai; then
      ok "Codex sign-in stored in sbx"
    else
      gate "Sign Codex in before the sandbox is created.

The sandbox's Codex setup is fixed when it is created, from whether a sign-in exists. On the Mac,
over Screen Sharing — it opens a browser there:

  $sbx secret set openai --oauth

Then re-run:
  ./bin/cookbook apply have-shared-sandbox

Not using Codex? Re-run with CODEX=off in front instead. Codex will be installed but signed out,
and signing it in later means recreating the sandbox."
    fi
  fi

  # Our kit is not built into sbx, so sbx uses the Codex sign-in it declares only with an approved
  # binding — and with nobody at the screen it withholds the credential silently rather than ask.
  # Writing the binding here is what Docker documents for unattended runs. The domains are the
  # kit's OAuth token endpoint and resource host; the file approves, it holds no secret.
  bind="$HOME/.config/sbx/credentials.yaml"
  if [ ! -f "$bind" ]; then
    /bin/mkdir -p "$(dirname "$bind")"
    printf 'bindings:\n  openai:\n    oauth:\n      domains: [auth.openai.com, chatgpt.com]\n' > "$bind"
    ok "approved the kit's Codex sign-in in $bind"
  elif /usr/bin/grep -q '^  openai:' "$bind"; then
    ok "a Codex sign-in binding already exists in $bind"
  else
    gate "$bind exists but has no openai entry, and editing YAML by pattern is how it breaks.
Add these lines under its 'bindings:' key:

  openai:
    oauth:
      domains: [auth.openai.com, chatgpt.com]

Then re-run:
  ./bin/cookbook apply have-shared-sandbox"
  fi

  note "creating sandbox '$name' (mountless, root disk $DOCKER_SANDBOXES_ROOT_SIZE)"
  with_timeout 600 "$sbx" create --kit "$kit" --name "$name" claude >/dev/null \
    || die "could not create sandbox '$name' — 'sbx diagnose' says why"
  ok "created sandbox '$name'"
fi

# A sandbox stops shortly after its last session disconnects unless it is detached, and the grid
# lives inside it. `run -d` against an existing sandbox switches it to detached for good, so
# running it again is harmless.
with_timeout 120 "$sbx" run -d --name "$name" >/dev/null \
  || die "could not start sandbox '$name' detached with 'sbx run -d --name $name'"
ok "sandbox '$name' runs detached"

# The kit installs tmux and Codex during create. Whether a failed install step fails the create is
# not documented, so look rather than assume.
with_timeout 60 "$sbx" exec "$name" sh -c 'command -v tmux && command -v codex' >/dev/null 2>&1 \
  || die "tmux or Codex is not installed in '$name' — a kit install step failed; 'sbx diagnose' and
the kit at $kit are where to look"
ok "tmux and Codex installed in '$name' (Claude Code and Codex update themselves at each sandbox start)"

set_server_var SBX_SANDBOX "$name"

note "next: sign Claude Code in once, from inside the sandbox:"
note "  $sbx exec -it $name bash    then run: claude, and /login"
