#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"
need_root
need_var ADMIN_USER
need_var SERVER_SLUG

conf=/etc/ssh/sshd_config.d/001-agent-machine.conf
home=$(/usr/bin/dscl . -read "/Users/$ADMIN_USER" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')
keys="$home/.ssh/authorized_keys"

if [ -f "$conf" ] && /usr/bin/grep -q '^PasswordAuthentication no' "$conf"; then
  ok "SSH accepts keys only ($conf)"
  exit 0
fi

if ! { [ -s "$keys" ] && /usr/bin/grep -q '^[^#[:space:]]' "$keys"; }; then
  gate "No SSH key is authorized for $ADMIN_USER yet. On each Mac or Linux client:

  ssh-keygen -t ed25519                     # only if ~/.ssh/id_ed25519 does not exist
  ssh-copy-id $ADMIN_USER@$SERVER_SLUG      # asks for the password one last time

Phone apps (Termius, Blink) and anything else: prereqs/client-ssh-key.md. Then re-run:
  ./bin/cookbook apply make-ssh-keys-only"
fi

if [ "${KEY_LOGIN_TESTED:-}" != yes ]; then
  gate "Prove a key login works before passwords go. From each client, in a new terminal:

  ssh -o PreferredAuthentications=publickey $ADMIN_USER@$SERVER_SLUG true

It must return with no password prompt and no error. Then re-run:
  KEY_LOGIN_TESTED=yes ./bin/cookbook apply make-ssh-keys-only"
fi

printf '# Managed by the agent-machine cookbook (recipes/make-ssh-keys-only).\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n' > "$conf"
/bin/chmod 644 "$conf"
if ! out=$(/usr/sbin/sshd -t 2>&1); then
  /bin/rm -f "$conf"
  die "sshd rejected the config, so it was removed again: $out"
fi
ok "SSH accepts keys only ($conf)"
note "applies to new connections; this one stays open. Test from a client before closing it."
note "Screen Sharing still takes the admin password — that is the way back in if keys are lost."
