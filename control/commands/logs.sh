#!/bin/bash
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BASE_DIR/.env"

TEXT="$1"

if [ "$TEXT" = "/logs" ]; then
  LOG_HELP=$(cat <<'HELP'
Usage:
/logs
/logs provision_arm
/logs provision_arm 20
/logs all
/logs all 20

Available logs:
- bot_control
- provision_arm
- report
- tg_send
- tg_receive

Default lines: 5
HELP
)
  "$BASE_DIR/infra-tools/tg_send.sh" "$LOG_HELP"
  exit 0
fi

LOG_TARGET=$(echo "$TEXT" | awk '{print $2}')
LOG_LINES=$(echo "$TEXT" | awk '{print $3}')

if [ -z "$LOG_LINES" ]; then
  LOG_LINES=5
fi

if ! echo "$LOG_LINES" | grep -Eq '^[0-9]+$'; then
  "$BASE_DIR/infra-tools/tg_send.sh" "Invalid line count. Example: /logs provision_arm 20"
  exit 1
fi

case "$LOG_TARGET" in
  bot_control|provision_arm|report|tg_send|tg_receive)
    LATEST_LOG=$(ls -t "$BASE_DIR/logs/$LOG_TARGET"/*.log 2>/dev/null | head -n 1)

    if [ -z "$LATEST_LOG" ]; then
      "$BASE_DIR/infra-tools/tg_send.sh" "No logs found for $LOG_TARGET"
    else
      LOG_OUTPUT=$(tail -n "$LOG_LINES" "$LATEST_LOG")
      MESSAGE=$(printf "LOG: %s\nLINES: %s\nFILE: %s\n\n%s" "$LOG_TARGET" "$LOG_LINES" "$LATEST_LOG" "$LOG_OUTPUT")
      "$BASE_DIR/infra-tools/tg_send.sh" "$MESSAGE"
    fi
    ;;

  all)
    MESSAGE=$(printf "LOGS: all\nLINES: %s" "$LOG_LINES")

    for TARGET_DIR in bot_control provision_arm report tg_send tg_receive; do
      LATEST_LOG=$(ls -t "$BASE_DIR/logs/$TARGET_DIR"/*.log 2>/dev/null | head -n 1)

      if [ -z "$LATEST_LOG" ]; then
        MESSAGE=$(printf "%s\n\n== %s ==\nNo logs found" "$MESSAGE" "$TARGET_DIR")
      else
        LOG_OUTPUT=$(tail -n "$LOG_LINES" "$LATEST_LOG")
        MESSAGE=$(printf "%s\n\n== %s ==\n%s" "$MESSAGE" "$TARGET_DIR" "$LOG_OUTPUT")
      fi
    done

    "$BASE_DIR/infra-tools/tg_send.sh" "$MESSAGE"
    ;;

  *)
    "$BASE_DIR/infra-tools/tg_send.sh" "Unknown log target: $LOG_TARGET. Use /logs for help."
    ;;
esac
