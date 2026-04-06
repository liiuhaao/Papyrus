#!/bin/zsh

set -euo pipefail

if [[ -n "${PAPYRUS_DEVELOPMENT_TEAM:-}" ]]; then
  echo "$PAPYRUS_DEVELOPMENT_TEAM"
  exit 0
fi

/usr/bin/security find-certificate -a -p -c "Apple Development" 2>/dev/null \
  | /usr/bin/openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null \
  | /usr/bin/sed -n 's/.*OU=\([^,]*\).*/\1/p' \
  | /usr/bin/head -n 1
