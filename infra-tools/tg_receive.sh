#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="tg_receive"
TS=$(date +"%Y%m%d-%H%M%S")
LOG_DIR="$BASE_DIR/logs/$SCRIPT_NAME"
LOG_FILE="$LOG_DIR/${TS}_${SCRIPT_NAME}.log"

mkdir -p "$LOG_DIR"

source "$BASE_DIR/.env"

OFFSET_FILE="$BASE_DIR/state/tg_offset.txt"
OFFSET="${1:-$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)}"

echo "[$(date -Is)] Receiving Telegram updates with offset: $OFFSET" >> "$LOG_FILE"

RESPONSE=$(curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/getUpdates?offset=$OFFSET")

echo "[$(date -Is)] Telegram API response:" >> "$LOG_FILE"
echo "$RESPONSE" >> "$LOG_FILE"

echo "$RESPONSE"
