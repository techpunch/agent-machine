#!/bin/bash
. "$(dirname "$0")/../../lib/common.sh"

# The effective value of an sshd setting: the first one read wins, and the main config includes
# sshd_config.d/ in place, so read it in the same order and stop at the first Match block.
effective() {
  {
    /usr/bin/sed -n '1,/^Include \/etc\/ssh\/sshd_config\.d/p' /etc/ssh/sshd_config
    /bin/cat /etc/ssh/sshd_config.d/* 2>/dev/null
    /usr/bin/sed -n '/^Include \/etc\/ssh\/sshd_config\.d/,$p' /etc/ssh/sshd_config
  } | /usr/bin/awk -v k="$1" 'tolower($1)=="match" {exit} tolower($1)==tolower(k) {print tolower($2); exit}'
}

keys="$(_admin_home)/.ssh/authorized_keys"
if [ -s "$keys" ] && /usr/bin/grep -q '^[^#[:space:]]' "$keys"; then
  ok "authorized keys present ($(/usr/bin/grep -c '^[^#[:space:]]' "$keys") in $keys)"
else
  miss "no key in $keys — turning passwords off now would lock you out"
fi

for k in PasswordAuthentication KbdInteractiveAuthentication; do
  v=$(effective "$k")
  if [ "$v" = no ]; then
    ok "$k no"
  else
    miss "$k ${v:-yes (OpenSSH default)} — SSH still accepts the admin password"
  fi
done

verify_result
