#!/bin/bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BASE_DIR/.env"

TG_SEND="$BASE_DIR/infra-tools/tg_send.sh"

mapfile -t KNOWN_SCRIPTS < <(find "$BASE_DIR" -type f -name "*.sh" -printf "%P\n" | sort)

LINES=""
COUNT=0

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
      MATCHED_SCRIPT="$(basename "$SCRIPT")"
      break
    fi
  done

  if [ -z "$MATCHED_SCRIPT" ]; then
    continue
  fi

  LINES="${LINES}${PID}: ${MATCHED_SCRIPT}"$'\n'
  COUNT=$((COUNT + 1))
done

if [ "$COUNT" -eq 0 ]; then
  LINES="none"
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
MSG
)

"$TG_SEND" "$MESSAGE"
