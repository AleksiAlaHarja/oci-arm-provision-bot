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

      # Turvatarkistus: Vain sallittu käyttäjä
      if [ "$CHAT_ID" != "$TG_CHAT_ID" ]; then
        continue
      fi

      # ==============================
      # DYNAAMINEN KOMENTOJEN REITITYS
      # ==============================

      # Erotetaan pelkkä komennon nimi ilman kauttaviivaa (esim. "/start provision_arm" -> "start")
      CMD_RAW=$(echo "$TEXT" | awk '{print $1}')
      CMD_NAME=${CMD_RAW#/}

      # Tarkistetaan onko commands-kansiossa pyydettyä komentoa vastaava skripti (.sh)
      if [ -n "$CMD_NAME" ] && [ -f "$BASE_DIR/control/commands/${CMD_NAME}.sh" ]; then
        echo "[$(date -Is)] Delegating to modular command: ${CMD_NAME}.sh"
        # Ajetaan modulaarinen skripti ja annetaan sille alkuperäinen viesti parametrinä ($1)
        "$BASE_DIR/control/commands/${CMD_NAME}.sh" "$TEXT"
      else
        echo "Unknown command or script missing: $TEXT"
      fi

    done
  fi

  sleep 5
done
