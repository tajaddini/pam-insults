#!/usr/bin/env bash
set -euo pipefail

BIN_DST=/usr/local/bin/pam-insult
DATA_DST=/usr/local/share/insults
PROFILE_DST=/usr/share/pam-configs/insults

(( EUID == 0 )) || { echo "run as root" >&2; exit 1; }

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">> installing picker -> $BIN_DST"
install -o root -g root -m 0755 "$src/bin/pam-insult" "$BIN_DST"

echo ">> installing insults -> $DATA_DST"
install -o root -g root -m 0755 -d "$DATA_DST"
for f in "$src"/insults/*.txt; do
    install -o root -g root -m 0644 "$f" "$DATA_DST/"
done

echo ">> installing PAM profile -> $PROFILE_DST"
install -o root -g root -m 0644 "$src/pam-configs/insults" "$PROFILE_DST"

echo ">> sanity check: picker output"
"$BIN_DST" "$DATA_DST" || true

echo ">> applying PAM stack"
pam-auth-update --force

echo
echo "Done. Generated /etc/pam.d/common-auth:"
echo "---------------------------------------"
cat /etc/pam.d/common-auth
echo "---------------------------------------"
cat <<'EOF'

Keep a root shell open (sudo -i) while you verify:

  sudo -k && sudo true    # wrong password  -> insult
  sudo -k && sudo true    # right password  -> no insult
  su - "$USER"            # right password  -> succeeds

Rollback:  sudo pam-auth-update --disable insults
EOF
