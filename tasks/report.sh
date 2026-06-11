#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="report"
TS=$(date +"%Y%m%d-%H%M%S")
LOG_DIR="$BASE_DIR/logs/$SCRIPT_NAME"
LOG_FILE="$LOG_DIR/${TS}_${SCRIPT_NAME}.log"

mkdir -p "$LOG_DIR"
exec >> "$LOG_FILE" 2>&1

source "$BASE_DIR/.env"

STATS_FILE="$BASE_DIR/state/stats.json"
PROCESSES_FILE="$BASE_DIR/state/processes.json"

echo "[$(date -Is)] report.sh started"

ATTEMPTS=$(jq -r '.provision_attempts_total // 0' "$STATS_FILE")
SUCCESSES=$(jq -r '.provision_success_total // 0' "$STATS_FILE")
FAILS=$(jq -r '.provision_fail_total // 0' "$STATS_FILE")
LAST_ATTEMPT=$(jq -r '.last_provision_attempt_at // "none"' "$STATS_FILE")
LAST_SUCCESS=$(jq -r '.last_provision_success_at // "none"' "$STATS_FILE")
LAST_ERROR=$(jq -r '.last_provision_error // "none"' "$STATS_FILE")

echo "Attempts: $ATTEMPTS"
echo "Successes: $SUCCESSES"
echo "Fails: $FAILS"
echo "Last attempt: $LAST_ATTEMPT"
echo "Last success: $LAST_SUCCESS"
echo "Last error: $LAST_ERROR"

RUNNING=$(jq -r 'to_entries | map(select(.value.status == "running")) | if length == 0 then "- none" else map("- " + .key + ".sh (PID " + (.value.pid|tostring) + ")") | join("\n") end' "$PROCESSES_FILE")

echo "Running:"
echo "$RUNNING"

MESSAGE=$(printf "Daily report\n\nProvision attempts total: %s\nSuccessful provisions: %s\nFailed provisions: %s\n\nLast attempt:\n%s\n\nLast success:\n%s\n\nLast error:\n%s\n\nRunning:\n%s\n" "$ATTEMPTS" "$SUCCESSES" "$FAILS" "$LAST_ATTEMPT" "$LAST_SUCCESS" "$LAST_ERROR" "$RUNNING")

"$BASE_DIR/infra-tools/tg_send.sh" "$MESSAGE"

echo "[$(date -Is)] report.sh finished"
