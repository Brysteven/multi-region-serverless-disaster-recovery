#!/usr/bin/env bash

set -euo pipefail

REGION_A="us-east-1"
REGION_B="ap-southeast-1"
TABLE="dr-items"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

ROLE_A=$(aws cloudformation describe-stack-resources --stack-name dr-serverless --region "$REGION_A" \
  --query "StackResources[?LogicalResourceId=='HealthFunctionRole'].PhysicalResourceId" --output text)
HC_A=$(aws cloudformation describe-stack-resources --stack-name dr-serverless --region "$REGION_A" \
  --query "StackResources[?LogicalResourceId=='HealthCheckA'].PhysicalResourceId" --output text)
URL_A=$(aws cloudformation describe-stacks --stack-name dr-serverless --region "$REGION_A" \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text)
URL_B=$(aws cloudformation describe-stacks --stack-name dr-serverless --region "$REGION_B" \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text)

echo "== Info =="
echo "role A       : $ROLE_A"
echo "health check : $HC_A"
echo "endpoint A   : $URL_A"
echo "endpoint B   : $URL_B"

cleanup() {
  if [ -n "${ROLE_A:-}" ]; then
    aws iam delete-role-policy --role-name "$ROLE_A" --policy-name DrillDeny 2>/dev/null || true
  fi
}
trap cleanup EXIT

hc_status() {
  local ok tot
  read -r ok tot <<<"$(aws route53 get-health-check-status --health-check-id "$HC_A" \
    --query "[length(HealthCheckObservations[?contains(StatusReport.Status,'Success')]), length(HealthCheckObservations)]" \
    --output text 2>/dev/null || echo '0 0')"
  if [ "${tot:-0}" -eq 0 ]; then echo "Unknown:0:0"; return; fi
  if [ $((ok * 100)) -le $((tot * 18)) ]; then echo "Unhealthy:$ok:$tot"; else echo "Healthy:$ok:$tot"; fi
}

echo; echo "== Baseline health check (must be Healthy before strike) =="
BASE_DEADLINE=$((SECONDS + 600))
BSTATUS=""
while [ $SECONDS -lt $BASE_DEADLINE ]; do
  IFS=: read -r BSTATUS BOK BTOT <<<"$(hc_status)"
  echo "  $BSTATUS ($BOK/$BTOT checkers healthy)"
  [ "$BSTATUS" = "Healthy" ] && break
  sleep 15
done
if [ "$BSTATUS" != "Healthy" ]; then
  echo "!! health check A is not Healthy yet. Wait for Healthy before drilling. Nothing was changed."
  exit 1
fi


echo; echo "== Baseline health =="
echo "A: $(curl -s -o /dev/null -w '%{http_code}' "$URL_A/health") (must be 200)"
echo "B: $(curl -s -o /dev/null -w '%{http_code}' "$URL_B/health") (must be 200)"

RPO_ID="rp-$(date +%s)"
T0=$(date +%s)
echo; echo "== Sample RPO at t0 =="
echo "write item to A: id=$RPO_ID"
curl -s -X POST "$URL_A/items" -H "Content-Type: application/json" -d "{\"id\":\"$RPO_ID\",\"data\":\"rpo-sample\"}"

echo; echo "== Strike region A: attach DrillDeny =="
aws iam put-role-policy --role-name "$ROLE_A" --policy-name DrillDeny \
  --policy-document file://drilldeny.json
echo "DrillDeny attached. Polling health check until Unhealthy..."

DEADLINE=$((SECONDS + 600))
while [ $SECONDS -lt $DEADLINE ]; do
  IFS=: read -r STATUS OK_N TOT_N <<<"$(hc_status)"
  ELAPSED=$(( $(date +%s) - T0 ))
  echo "  t+${ELAPSED}s : $STATUS ($OK_N/$TOT_N checkers healthy)"
  case "$STATUS" in
    Unhealthy) T_FLIP=$(date +%s); FLIP_ELAPSED=$((T_FLIP - T0)); break ;;
  esac
  sleep 10
done

if [ -z "${T_FLIP:-}" ]; then echo "!! timeout, health check A did not flip"; exit 1; fi
echo; echo "FLIP detected at t+${FLIP_ELAPSED}s (A -> Unhealthy)"

echo "A: $(curl -s -o /dev/null -w '%{http_code}' "$URL_A/health") (must be 503)"
echo "B: $(curl -s -o /dev/null -w '%{http_code}' "$URL_B/health") (must be 200)"

echo; echo "== Re-check RPO via endpoint B =="
echo "read item $RPO_ID via B:"
curl -s "$URL_B/items/$RPO_ID"
echo

if [ "${HOLD_SECONDS:-0}" -gt 0 ]; then
  HOLD_UNTIL=$(( FLIP_ELAPSED + HOLD_SECONDS ))
  echo; echo "== Holding the strike until t+${HOLD_UNTIL}s (HOLD_SECONDS=$HOLD_SECONDS) =="
  while [ $(( $(date +%s) - T0 )) -lt $HOLD_UNTIL ]; do
    echo "  t+$(( $(date +%s) - T0 ))s : strike held"
    sleep 15
  done
fi

echo; echo "== Failback: delete DrillDeny =="
aws iam delete-role-policy --role-name "$ROLE_A" --policy-name DrillDeny
echo "DrillDeny deleted. Polling health check back to Healthy..."

DEADLINE=$((SECONDS + 600))
while [ $SECONDS -lt $DEADLINE ]; do
  IFS=: read -r STATUS OK_N TOT_N <<<"$(hc_status)"
  echo "  t+$(( $(date +%s) - T0 ))s : $STATUS ($OK_N/$TOT_N checkers healthy)"
  case "$STATUS" in
    Healthy) T_RESTORE=$(date +%s); RESTORE_ELAPSED=$((T_RESTORE - T0)); break ;;
  esac
  sleep 10
done

if [ -z "${T_RESTORE:-}" ]; then echo "!! timeout, health check did not return to Healthy"; exit 1; fi
echo; echo "RESTORE at t+${RESTORE_ELAPSED}s (A -> Healthy)"

echo; echo "== Summary =="
echo "t0                    : $T0"
echo "flip (A->Unhealthy)   : t+${FLIP_ELAPSED}s"
echo "restore (A->Healthy)  : t+${RESTORE_ELAPSED}s"
echo "RPO sample id         : $RPO_ID"
echo "detection lag (RTO without the DNS TTL) : ${FLIP_ELAPSED}s"
