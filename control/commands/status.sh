#!/bin/bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BASE_DIR/.env"

TG_SEND="$BASE_DIR/infra-tools/tg_send.sh"
PROCESSES_FILE="$BASE_DIR/state/processes.json"

MANAGED_KEYS=("bot_control" "provision_arm" "report")

get_script_path() {
  case "$1" in
    bot_control) echo "control/bot_control.sh" ;;
    provision_arm) echo "daemon/provision_arm.sh" ;;
    report) echo "tasks/report.sh" ;;
  esac
}

get_script_name() {
  basename "$(get_script_path "$1")"
}

find_script_pids() {
  local script_path="$1"

  for PROC in /proc/[0-9]*; do
    PID="${PROC##*/}"

    if [ "$PID" = "$$" ]; then
      continue
    fi

    CMD=$(tr '\0' ' ' < "$PROC/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//' || true)

    if [ -z "$CMD" ]; then
      continue
    fi

    if [[ "$CMD" = *"$BASE_DIR/$script_path"* || "$CMD" = *"./$script_path"* || "$CMD" = *" $script_path"* || "$CMD" = "$script_path"* ]]; then
      ETIME_SECONDS=$(ps -p "$PID" -o etimes= 2>/dev/null | awk '{print $1}')
      PPID_VALUE=$(ps -p "$PID" -o ppid= 2>/dev/null | awk '{print $1}')

      if [ -n "$ETIME_SECONDS" ]; then
        echo "$PID|${PPID_VALUE:-unknown}|$ETIME_SECONDS"
      fi
    fi
  done
}

LINES=""
WARNINGS=""

for KEY in "${MANAGED_KEYS[@]}"; do
  SCRIPT_PATH=$(get_script_path "$KEY")
  SCRIPT_NAME=$(get_script_name "$KEY")

  mapfile -t MATCHES < <(find_script_pids "$SCRIPT_PATH")

  if [ "${#MATCHES[@]}" -eq 0 ]; then
    if [ "$KEY" = "provision_arm" ] && [ -f "$PROCESSES_FILE" ] && command -v jq >/dev/null 2>&1; then
      TRACKED_STATUS=$(jq -r '.provision_arm.status // "stopped"' "$PROCESSES_FILE" 2>/dev/null)

      if [ "$TRACKED_STATUS" = "running" ]; then
        tmp=$(mktemp)
        jq '.provision_arm.status = "stopped"' "$PROCESSES_FILE" > "$tmp" && mv "$tmp" "$PROCESSES_FILE"
        WARNINGS="${WARNINGS}provision_arm was marked running but no process was found. Marked stopped."$'\n'
      fi
    fi

    continue
  fi

  CHOSEN_PID=""

  if [ "$KEY" = "provision_arm" ] && [ -f "$PROCESSES_FILE" ] && command -v jq >/dev/null 2>&1; then
    TRACKED_PID=$(jq -r '.provision_arm.pid // empty' "$PROCESSES_FILE" 2>/dev/null)

    if [ -n "$TRACKED_PID" ]; then
      for ITEM in "${MATCHES[@]}"; do
        PID=$(echo "$ITEM" | cut -d'|' -f1)

        if [ "$PID" = "$TRACKED_PID" ]; then
          CHOSEN_PID="$PID"
          break
        fi
      done
    fi
  fi

  if [ -z "$CHOSEN_PID" ]; then
    CHOSEN_PID=$(printf "%s\n" "${MATCHES[@]}" | sort -t'|' -k3,3nr | head -1 | cut -d'|' -f1)
  fi

  LINES="${LINES}${CHOSEN_PID}: ${SCRIPT_NAME}"$'\n'

  if [ "${#MATCHES[@]}" -gt 1 ]; then
    EXTRA_PIDS=""

    for ITEM in "${MATCHES[@]}"; do
      PID=$(echo "$ITEM" | cut -d'|' -f1)
      PPID_VALUE=$(echo "$ITEM" | cut -d'|' -f2)

      if [ "$PID" != "$CHOSEN_PID" ]; then
        PARENT_IS_MATCHED="no"

        for PARENT_ITEM in "${MATCHES[@]}"; do
          PARENT_PID=$(echo "$PARENT_ITEM" | cut -d'|' -f1)

          if [ "$PPID_VALUE" = "$PARENT_PID" ]; then
            PARENT_IS_MATCHED="yes"
            break
          fi
        done

        if [ "$PARENT_IS_MATCHED" = "yes" ]; then
          EXTRA_PIDS="${EXTRA_PIDS} ${PID} (parent ${PPID_VALUE})"
        else
          EXTRA_PIDS="${EXTRA_PIDS} ${PID} (has no parent -> consider /stop ${PID})"
        fi
      fi
    done

    if [ -n "$EXTRA_PIDS" ]; then
      WARNINGS="${WARNINGS}Multiple ${SCRIPT_NAME} processes detected. Hidden extra PID(s):${EXTRA_PIDS}"$'\n'
    fi
  fi
done

if [ -z "$LINES" ]; then
  LINES="none"
fi

if [ -z "$WARNINGS" ]; then
  WARNINGS="none"
fi

NOW_TIME=$(TZ=Europe/Helsinki date +"%H%M")

if [ "$NOW_TIME" -lt 700 ]; then
  NEXT_REPORT="$(TZ=Europe/Helsinki date +"%d.%m.%y - 07:00:00") - report.sh"
else
  NEXT_REPORT="$(TZ=Europe/Helsinki date -d "tomorrow" +"%d.%m.%y - 07:00:00") - report.sh"
fi

MESSAGE=$(cat <<MSG
RUNNING PROCESSES
$LINES

SCHEDULED
$NEXT_REPORT

WARNINGS
$WARNINGS
MSG
)

"$TG_SEND" "$MESSAGE"