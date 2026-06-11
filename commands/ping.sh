#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$BASE_DIR/infra-tools/tg_send.sh" "pong"
