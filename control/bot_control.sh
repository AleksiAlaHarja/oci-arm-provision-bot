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

"$BASE_DIR/infra-tools/tg_send.sh" $'Bot_control.sh started. \nRecommended to check /status. \nIf provision_arm is not running, use "/start provision_arm".'

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

      # Turvatarkistus: Vain sallittu käyttäjä
      if [ "$CHAT_ID" != "$TG_CHAT_ID" ]; then
        continue
      fi

      # ==============================
      # DYNAAMINEN KOMENTOJEN REITITYS
      # ==============================

      # Erotetaan pelkkä komennon nimi ilman kauttaviivaa
      # Esim. "/start provision_arm" -> "start"
      CMD_RAW=$(echo "$TEXT" | awk '{print $1}')
      CMD_NAME=${CMD_RAW#/}
      COMMAND_SCRIPT="$BASE_DIR/control/commands/${CMD_NAME}.sh"

      if [ -n "$CMD_NAME" ] && [ -f "$COMMAND_SCRIPT" ]; then
        echo "[$(date -Is)] Command script found: ${CMD_NAME}.sh"

        if [ ! -x "$COMMAND_SCRIPT" ]; then
          echo "[$(date -Is)] Command script is not executable, running chmod +x: $COMMAND_SCRIPT"
          chmod +x "$COMMAND_SCRIPT"

          if [ ! -x "$COMMAND_SCRIPT" ]; then
            echo "[$(date -Is)] Failed to make command executable: $COMMAND_SCRIPT"
            "$BASE_DIR/infra-tools/tg_send.sh" "Command found but could not make it executable: ${CMD_NAME}.sh"
            continue
          fi
        fi

        echo "[$(date -Is)] Delegating to modular command: ${CMD_NAME}.sh"
        "$COMMAND_SCRIPT" "$TEXT"

      else
        echo "[$(date -Is)] Unknown command or script missing: $TEXT"
        "$BASE_DIR/infra-tools/tg_send.sh" "Unknown command: $CMD_RAW. No handler found at control/commands/${CMD_NAME}.sh"
      fi

    done
  fi

  sleep 5
done
