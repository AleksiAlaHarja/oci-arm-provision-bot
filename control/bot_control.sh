#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="bot_control"
TS=$(date +"%Y%m%d-%H%M%S")
LOG_DIR="$BASE_DIR/logs/$SCRIPT_NAME"
LOG_FILE="$LOG_DIR/${TS}_${SCRIPT_NAME}.log"

mkdir -p "$LOG_DIR"
exec >> "$LOG_FILE" 2>&1

source "$BASE_DIR/.env"

OFFSET_FILE="$BASE_DIR/state/tg_offset.txt"
PROCESSES_FILE="$BASE_DIR/state/processes.json"
STATS_FILE="$BASE_DIR/state/stats.json"

echo "[$(date -Is)] bot_control.sh started"

"$BASE_DIR/infra-tools/tg_send.sh" "Bot control käynnistyi. Tarkista tila komennolla /status. Jos provision_arm ei ole käynnissä, käynnistä se komennolla /start provision_arm."

while true; do

  # ==============================
  # AUTOMAATTINEN DAILY REPORT 07:00
  # ==============================

  TODAY=$(TZ=Europe/Helsinki date +"%Y-%m-%d")
  CURRENT_TIME=$(TZ=Europe/Helsinki date +"%H:%M")

  LAST_REPORT_DATE=$(jq -r '.last_report_date // empty' "$STATS_FILE")

  if [[ "$CURRENT_TIME" > "06:59" ]] && [ "$LAST_REPORT_DATE" != "$TODAY" ]; then
    echo "[$(date -Is)] Running scheduled daily report"

    "$BASE_DIR/tasks/report.sh"

    tmp=$(mktemp)
    jq --arg today "$TODAY" '
      .last_report_date = $today
    ' "$STATS_FILE" > "$tmp" && mv "$tmp" "$STATS_FILE"
  fi

  # ==============================
  # TELEGRAM POLLING
  # ==============================

  OFFSET=$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)

  echo "[$(date -Is)] Checking Telegram updates with offset: $OFFSET"

  UPDATES=$("$BASE_DIR/infra-tools/tg_receive.sh" "$OFFSET")
  COUNT=$(echo "$UPDATES" | jq '.result | length' 2>/dev/null)

  if [ -z "$COUNT" ] || [ "$COUNT" = "null" ]; then
    sleep 5
    continue
  fi

  if [ "$COUNT" -gt 0 ]; then
    for i in $(seq 0 $((COUNT - 1))); do
      UPDATE_ID=$(echo "$UPDATES" | jq -r ".result[$i].update_id")
      CHAT_ID=$(echo "$UPDATES" | jq -r ".result[$i].message.chat.id")
      TEXT=$(echo "$UPDATES" | jq -r ".result[$i].message.text // empty")

      NEXT_OFFSET=$((UPDATE_ID + 1))
      echo "$NEXT_OFFSET" > "$OFFSET_FILE"

      echo "[$(date -Is)] Received message: $TEXT"

      if [ "$CHAT_ID" != "$TG_CHAT_ID" ]; then
        continue
      fi

      case "$TEXT" in

        "/ping")
          "$BASE_DIR/infra-tools/tg_send.sh" "pong"
          ;;

        "/report")
          "$BASE_DIR/tasks/report.sh"
          ;;

        "/status")
          PID=$(jq -r ".provision_arm.pid // empty" "$PROCESSES_FILE")
          STATUS=$(jq -r '.provision_arm.status // "stopped"' "$PROCESSES_FILE")

          if [ "$STATUS" = "running" ] && { [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; }; then
            tmp=$(mktemp)
            jq '.provision_arm.status = "stopped"' "$PROCESSES_FILE" > "$tmp" && mv "$tmp" "$PROCESSES_FILE"
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
          ;;

        "/start provision_arm")
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
          ;;

        "/stop provision_arm")
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
          ;;

        "/restart provision_arm")
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
          ;;


        "/logs")
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
          ;;

        /logs\ *)
          LOG_TARGET=$(echo "$TEXT" | awk '{print $2}')
          LOG_LINES=$(echo "$TEXT" | awk '{print $3}')

          if [ -z "$LOG_LINES" ]; then
            LOG_LINES=5
          fi

          if ! echo "$LOG_LINES" | grep -Eq '^[0-9]+$'; then
            "$BASE_DIR/infra-tools/tg_send.sh" "Invalid line count. Example: /logs provision_arm 20"
            continue
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

              for LOG_TARGET in bot_control provision_arm report tg_send tg_receive; do
                LATEST_LOG=$(ls -t "$BASE_DIR/logs/$LOG_TARGET"/*.log 2>/dev/null | head -n 1)

                if [ -z "$LATEST_LOG" ]; then
                  MESSAGE=$(printf "%s\n\n== %s ==\nNo logs found" "$MESSAGE" "$LOG_TARGET")
                else
                  LOG_OUTPUT=$(tail -n "$LOG_LINES" "$LATEST_LOG")
                  MESSAGE=$(printf "%s\n\n== %s ==\n%s" "$MESSAGE" "$LOG_TARGET" "$LOG_OUTPUT")
                fi
              done

              "$BASE_DIR/infra-tools/tg_send.sh" "$MESSAGE"
              ;;

            *)
              "$BASE_DIR/infra-tools/tg_send.sh" "Unknown log target: $LOG_TARGET. Use /logs for help."
              ;;
          esac
          ;;

        *)
          echo "Unknown command: $TEXT"
          ;;

      esac
    done
  fi

  sleep 5
done
``
