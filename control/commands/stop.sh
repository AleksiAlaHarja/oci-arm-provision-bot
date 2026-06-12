#!/bin/bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BASE_DIR/.env"

TG_SEND="$BASE_DIR/infra-tools/tg_send.sh"
STATUS_SCRIPT="$BASE_DIR/control/commands/status.sh"
PROCESSES_FILE="$BASE_DIR/state/processes.json"

TEXT="${1:-}"
PID=$(echo "$TEXT" | awk '{print $2}')

if [ -z "$PID" ]; then
    "$TG_SEND" "Which process do you want to stop? Use /stop <PID>. Current status:"
    "$STATUS_SCRIPT"
    exit 0
fi

if ! echo "$PID" | grep -Eq '^[0-9]+$'; then
    "$TG_SEND" "Invalid PID: $PID. Use /stop <PID>. Current status:"
    "$STATUS_SCRIPT"
    exit 1
fi

if ! kill -0 "$PID" 2>/dev/null; then
    "$TG_SEND" "Process $PID is not running. Current status:"
    "$STATUS_SCRIPT"
    exit 1
fi

CMD=$(tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//' || true)

if [ -z "$CMD" ]; then
    "$TG_SEND" "Could not inspect process $PID. Refusing to stop it."
    exit 1
fi

if [[ "$CMD" != *"$BASE_DIR"* ]]; then
    "$TG_SEND" "Refusing to stop PID $PID because it does not look like an oci-arm-provision-bot process."
    exit 1
fi

SHORT_CMD=$(echo "$CMD" | sed "s#$BASE_DIR/##g")

kill "$PID"

sleep 1

if kill -0 "$PID" 2>/dev/null; then
    "$TG_SEND" "Failed to stop process $PID: $SHORT_CMD"
    exit 1
fi

if [ -f "$PROCESSES_FILE" ] && command -v jq >/dev/null 2>&1; then
    tmp=$(mktemp)
    jq --argjson pid "$PID" '
      with_entries(
        if (.value.pid? == $pid) then
          .value.status = "stopped"
        else
          .
        end
      )
    ' "$PROCESSES_FILE" > "$tmp" && mv "$tmp" "$PROCESSES_FILE"
fi

"$TG_SEND" "Stopped process $PID: $SHORT_CMD"
