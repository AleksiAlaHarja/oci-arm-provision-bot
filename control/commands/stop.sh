#!/bin/bash
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BASE_DIR/.env"

TEXT="$1"
TARGET=$(echo "$TEXT" | awk '{print $2}')

if [ "$TARGET" != "provision_arm" ]; then
    "$BASE_DIR/infra-tools/tg_send.sh" "Unsupported target: $TARGET. Use /stop provision_arm"
    exit 1
fi

PROCESSES_FILE="$BASE_DIR/state/processes.json"
PID=$(jq -r '.provision_arm.pid // empty' "$PROCESSES_FILE")

if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    tmp=$(mktemp)
    jq '.provision_arm.status = "stopped"' "$PROCESSES_FILE" > "$tmp" && mv "$tmp" "$PROCESSES_FILE"
    "$BASE_DIR/infra-tools/tg_send.sh" "Stopped provision_arm (PID $PID)"
else
    tmp=$(mktemp)
    jq '.provision_arm.status = "stopped"' "$PROCESSES_FILE" > "$tmp" && mv "$tmp" "$PROCESSES_FILE"
    "$BASE_DIR/infra-tools/tg_send.sh" "provision_arm is not running"
fi