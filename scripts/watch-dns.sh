#!/usr/bin/env bash
set -uo pipefail

API_HOST="${API_HOST:-api.example.com}"
RESOLVER="${RESOLVER:-1.1.1.1}"
INTERVAL="${INTERVAL:-10}"

echo "watching https://$API_HOST via $RESOLVER, start $(date +%T)"

while true; do
  TS=$(date +%T)
  REGION=$(curl -sS --max-time 5 "https://$API_HOST/health" 2>/dev/null || echo "curl-fail")
  TARGET=$(nslookup -type=CNAME "$API_HOST" "$RESOLVER" 2>&1 | grep -Eio "d-[a-z0-9]+|timed out" | head -1)
  echo "$TS | $REGION | ${TARGET:-no-answer}"
  sleep "$INTERVAL"
done
