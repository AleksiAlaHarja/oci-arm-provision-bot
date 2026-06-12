#!/bin/bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BASE_DIR/.env"

TG_SEND="$BASE_DIR/infra-tools/tg_send.sh"

"$TG_SEND" $'Server /reboot requested. \nServer will reboot in a few seconds. \nBot_control.sh will notify when it´s back online.'

sleep 5

sudo -n systemctl reboot

EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
  "$TG_SEND" "Reboot failed. Check sudo permissions."
  exit "$EXIT_CODE"
fi
