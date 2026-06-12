#!/bin/bash
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BASE_DIR/.env"

PROCESSES_FILE="$BASE_DIR/state/processes.json"
STATS_FILE="$BASE_DIR/state/stats.json"

PID=$(jq -r '.provision_arm.pid // empty' "$PROCESSES_FILE")
STATUS=$(jq -r '.provision_arm.status // "stopped"' "$PROCESSES_FILE")

# If status says running but PID is dead, update status to stopped
if [ "$STATUS" = "running" ] && { [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; }; then
    tmp=$(mktemp)
    jq '.provision_arm.status = "stopped"' "$PROCESSES_FILE" > "$tmp" && mv "$tmp" "$PROCESSES_FILE"
    STATUS="stopped"
fi

RUNNING=$(jq -r '
    to_entries
    | map(select(.value.status == "running"))
    | if length == 0 then "- none"
      else map("- " + .key + ".sh (PID " + (.value.pid|tostring) + ")") | join("\n")
      end
' "$PROCESSES_FILE")

NOW_TIME=$(TZ=Europe/Helsinki date +"%H%M")

if [ "$NOW_TIME" -lt 700 ]; then
    NEXT_REPORT="$(TZ=Europe/Helsinki date +"%d.%m.%y - 07:00:00") - report.sh"
else
    NEXT_REPORT="$(TZ=Europe/Helsinki date -d "tomorrow" +"%d.%m.%y - 07:00:00") - report.sh"
fi

STATUS_MESSAGE=$(printf "RUNNING:\n%s\n\nSCHEDULED:\n- %s\n" "$RUNNING" "$NEXT_REPORT")

"$BASE_DIR/infra-tools/tg_send.sh" "$STATUS_MESSAGE"