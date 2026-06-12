#!/bin/bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BASE_DIR/.env"

TG_SEND="$BASE_DIR/infra-tools/tg_send.sh"
COMMANDS_DIR="$BASE_DIR/control/commands"

COMMAND_LIST=$(
  find "$COMMANDS_DIR" -maxdepth 1 -type f -name "*.sh" -printf "%f\n" \
    | sed 's/\.sh$//' \
    | sort \
    | awk '{print "  /" $0}'
)

if [ -z "$COMMAND_LIST" ]; then
  COMMAND_LIST="- none"
fi

MESSAGE=$(cat <<MSG
AVAILABLE COMMANDS

$COMMAND_LIST

Usage:
Send any command exactly as shown above.
Example:
/status
/processes
/start provision_arm
/stop provision_arm
MSG
)

"$TG_SEND" "$MESSAGE"
