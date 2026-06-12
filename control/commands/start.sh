#!/bin/bash
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BASE_DIR/.env"

TEXT="$1"
TARGET=$(echo "$TEXT" | awk '{print $2}')

if [ "$TARGET" != "provision_arm" ]; then
    "$BASE_DIR/infra-tools/tg_send.sh" $'Unsupported target. \nUse eg: \n/start provision_arm'
    exit 1
fi

PROCESSES_FILE="$BASE_DIR/state/processes.json"
PID=$(jq -r '.provision_arm.pid // empty' "$PROCESSES_FILE")
STATUS=$(jq -r '.provision_arm.status // "stopped"' "$PROCESSES_FILE")

if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null && [ "$STATUS" = "running" ]; then
    "$BASE_DIR/infra-tools/tg_send.sh" "provision_arm already running (PID $PID)"
else
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

    "$BASE_DIR/infra-tools/tg_send.sh" "Started provision_arm (PID $NEW_PID)"
fi
