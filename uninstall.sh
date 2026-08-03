#!/usr/bin/env bash
set -euo pipefail

(( EUID == 0 )) || { echo "run as root" >&2; exit 1; }

if [[ -f /usr/share/pam-configs/insults ]]; then
    echo ">> disabling profile"
    pam-auth-update --disable insults || true
    rm -f /usr/share/pam-configs/insults
    echo ">> regenerating PAM stack"
    pam-auth-update --force
fi

rm -f /usr/local/bin/pam-insult
rm -rf /usr/local/share/insults

echo "Done. Current /etc/pam.d/common-auth:"
cat /etc/pam.d/common-auth
