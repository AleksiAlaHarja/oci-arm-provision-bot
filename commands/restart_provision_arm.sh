#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROCESSES_FILE="$BASE_DIR/state/processes.json"

PID=$(jq -r '.provision_arm.pid // empty' "$PROCESSES_FILE")

if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
fi

nohup "$BASE_DIR/daemon/provision_arm.sh" >/dev/null 2>&1 &
NEW_PID=$!
STARTED_AT=$(date -Is)

tmp=$(mktemp)
jq --argjson pid "$NEW_PID" --arg started_at "$STARTED_AT" '
  .provision_arm = {
    "pid": $pid,
    "script": "daemon/provision_arm.sh",
    "status": "running",
    "started_at": $started_at
  }
' "$PROCESSES_FILE" > "$tmp" && mv "$tmp" "$PROCESSES_FILE"

"$BASE_DIR/infra-tools/tg_send.sh" "Restarted provision_arm (PID $NEW_PID)"
