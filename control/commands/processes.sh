#!/bin/bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BASE_DIR/.env"

TG_SEND="$BASE_DIR/infra-tools/tg_send.sh"
PROCESSES_FILE="$BASE_DIR/state/processes.json"

declare -A COUNT
declare -A PIDS

MATCHES=0
RUNNING_BLOCK=""

mapfile -t KNOWN_SCRIPTS < <(find "$BASE_DIR" -type f -name "*.sh" -printf "%P\n" | sort)

for PROC in /proc/[0-9]*; do
  PID="${PROC##*/}"

  if [ "$PID" = "$$" ]; then
    continue
  fi

  CMD=$(tr '\0' ' ' < "$PROC/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//' || true)

  if [ -z "$CMD" ]; then
    continue
  fi

  MATCHED_SCRIPT=""

  for SCRIPT in "${KNOWN_SCRIPTS[@]}"; do
    if [[ "$CMD" = *"$BASE_DIR/$SCRIPT"* || "$CMD" = *"./$SCRIPT"* || "$CMD" = *" $SCRIPT"* || "$CMD" = "$SCRIPT"* ]]; then
      MATCHED_SCRIPT="$SCRIPT"
      break
    fi
  done

  if [ -z "$MATCHED_SCRIPT" ]; then
    continue
  fi

  PPID_VALUE=$(ps -p "$PID" -o ppid= 2>/dev/null | awk '{print $1}')
  STAT_VALUE=$(ps -p "$PID" -o stat= 2>/dev/null | awk '{print $1}')
  ELAPSED_VALUE=$(ps -p "$PID" -o etime= 2>/dev/null | awk '{print $1}')

  SHORT_CMD=$(echo "$CMD" | sed "s#$BASE_DIR/##g")

  RUNNING_BLOCK="${RUNNING_BLOCK}- id: $PID
  file: $MATCHED_SCRIPT
  parent_id: ${PPID_VALUE:-unknown}
  status: ${STAT_VALUE:-unknown}
  elapsed: ${ELAPSED_VALUE:-unknown}
  command: $SHORT_CMD

"

  COUNT["$MATCHED_SCRIPT"]=$(( ${COUNT["$MATCHED_SCRIPT"]:-0} + 1 ))
  PIDS["$MATCHED_SCRIPT"]="${PIDS["$MATCHED_SCRIPT"]:-} $PID"

  MATCHES=$((MATCHES + 1))
done

if [ "$MATCHES" -eq 0 ]; then
  RUNNING_BLOCK="- none"
fi

WARNINGS=""
WARNING_COUNT=0

for SCRIPT in "${KNOWN_SCRIPTS[@]}"; do
  SCRIPT_COUNT="${COUNT["$SCRIPT"]:-0}"

  if [ "$SCRIPT_COUNT" -gt 1 ]; then
    WARNINGS="${WARNINGS}- duplicate process detected
  file: $SCRIPT
  ids:${PIDS["$SCRIPT"]}

"
    WARNING_COUNT=$((WARNING_COUNT + 1))
  fi
done

if [ -f "$PROCESSES_FILE" ] && command -v jq >/dev/null 2>&1; then
  TRACKED_PID=$(jq -r '.provision_arm.pid // empty' "$PROCESSES_FILE" 2>/dev/null)
  TRACKED_STATUS=$(jq -r '.provision_arm.status // "unknown"' "$PROCESSES_FILE" 2>/dev/null)

  if [ "$TRACKED_STATUS" = "running" ] && [ -n "$TRACKED_PID" ]; then
    ACTUAL_PROVISION_PIDS="${PIDS["daemon/provision_arm.sh"]:-}"

    if [[ " $ACTUAL_PROVISION_PIDS " != *" $TRACKED_PID "* ]]; then
      WARNINGS="${WARNINGS}- state mismatch
  file: daemon/provision_arm.sh
  processes_json_pid: $TRACKED_PID
  issue: processes.json says running, but this PID was not found

"
      WARNING_COUNT=$((WARNING_COUNT + 1))
    fi
  fi
fi

if [ "$WARNING_COUNT" -eq 0 ]; then
  WARNINGS="- none"
fi

MESSAGE=$(cat <<MSG
PROCESS CHECK

BASE:
$BASE_DIR

RUNNING PROJECT SCRIPT PROCESSES:
$RUNNING_BLOCK

WARNINGS:
$WARNINGS
MSG
)

if [ "${#MESSAGE}" -gt 3900 ]; then
  MESSAGE="${MESSAGE:0:3800}

[truncated]"
fi

"$TG_SEND" "$MESSAGE"
