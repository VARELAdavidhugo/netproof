#!/usr/bin/env bash
set -euo pipefail

echo "[TEST] netproof example.com"

# Lance le script netproof avec output JSON
./netproof.sh -d example.com -o examples/sample-report.json --no-icmp -v

# Vérifie si jq est dispo pour valider le JSON
if command -v jq >/dev/null 2>&1; then
  jq . examples/sample-report.json >/dev/null
else
  echo "(jq non présent, skip pretty)"
fi

# Vérifie que overall_ok est vrai
if grep -q '"overall_ok": true' examples/sample-report.json; then
  echo "[OK] overall_ok=true"
else
  echo "[ERR] overall_ok=false"
  cat examples/sample-report.json
  exit 1
fi
