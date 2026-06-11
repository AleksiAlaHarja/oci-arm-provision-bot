#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="tg_send"
TS=$(date +"%Y%m%d-%H%M%S")
LOG_DIR="$BASE_DIR/logs/$SCRIPT_NAME"
LOG_FILE="$LOG_DIR/${TS}_${SCRIPT_NAME}.log"

mkdir -p "$LOG_DIR"
exec >> "$LOG_FILE" 2>&1

source "$BASE_DIR/.env"

MESSAGE="$1"

if [ -z "$MESSAGE" ]; then
  echo "ERROR: No message provided"
  exit 1
fi

echo "[$(date -Is)] Sending Telegram message"

RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
  -d "chat_id=$TG_CHAT_ID" \
  -d "text=$MESSAGE")

echo "[$(date -Is)] Telegram API response:"
echo "$RESPONSE"

if echo "$RESPONSE" | grep -q '"ok":true'; then
  echo "[$(date -Is)] Message sent successfully"
  exit 0
else
  echo "[$(date -Is)] ERROR: Message send failed"
  exit 1
fi
