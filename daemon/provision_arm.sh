#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="provision_arm"
TS=$(date +"%Y%m%d-%H%M%S")
LOG_DIR="$BASE_DIR/logs/$SCRIPT_NAME"
LOG_FILE="$LOG_DIR/${TS}_${SCRIPT_NAME}.log"

mkdir -p "$LOG_DIR"
exec >> "$LOG_FILE" 2>&1

source "$BASE_DIR/.env"

STATS_FILE="$BASE_DIR/state/stats.json"
PROCESSES_FILE="$BASE_DIR/state/processes.json"

echo "[$(date -Is)] provision_arm.sh daemon started"

while true; do
  echo "[$(date -Is)] Starting provision attempt"

  IMAGE_ID=$(oci compute image list \
    --compartment-id "$OCI_COMPARTMENT_ID" \
    --operating-system "Canonical Ubuntu" \
    --operating-system-version "24.04" \
    --shape "VM.Standard.A1.Flex" \
    --all \
    --query 'data | sort_by(@,&"time-created") | reverse(@) | [0].id' \
    --raw-output)

  echo "[$(date -Is)] Selected image: $IMAGE_ID"

  if [ -z "$IMAGE_ID" ] || [ "$IMAGE_ID" = "null" ]; then
    echo "[$(date -Is)] ERROR: IMAGE_ID not found"
    sleep 300
    continue
  fi

  NOW=$(date -Is)

  tmp=$(mktemp)
  jq --arg now "$NOW" '
    .provision_attempts_total = ((.provision_attempts_total // 0) + 1)
    | .last_provision_attempt_at = $now
  ' "$STATS_FILE" > "$tmp" && mv "$tmp" "$STATS_FILE"

  echo "[$(date -Is)] Updated provision attempt counter"
  echo "[$(date -Is)] Launching ARM instance"

  RESPONSE=$(oci compute instance launch \
    --availability-domain "$OCI_AD" \
    --compartment-id "$OCI_COMPARTMENT_ID" \
    --shape "VM.Standard.A1.Flex" \
    --subnet-id "$OCI_SUBNET_ID" \
    --image-id "$IMAGE_ID" \
    --shape-config '{"ocpus":1,"memoryInGBs":6}' \
    --boot-volume-size-in-gbs 50 \
    --metadata "{\"ssh_authorized_keys\":\"$OCI_SSH_PUBLIC_KEY\"}" \
    2>&1)

  echo "[$(date -Is)] OCI response:"
  echo "$RESPONSE"

  NOW=$(date -Is)

  # 1. ONNISTUMINEN (Tarkistetaan onko vasteessa luodun instanssin id)
  if echo "$RESPONSE" | grep -q "ocid1.instance"; then
    tmp=$(mktemp)
    jq --arg now "$NOW" '
      .provision_success_total = ((.provision_success_total // 0) + 1)
      | .last_provision_success_at = $now
    ' "$STATS_FILE" > "$tmp" && mv "$tmp" "$STATS_FILE"

    echo "[$(date -Is)] Provision succeeded"
    "$BASE_DIR/infra-tools/tg_send.sh" "🚀 ARM instance provision succeeded! Palvelin on pystyssä."
    exit 0

  # 2. NORMAALI SKENAARIO: RESURSSIPULA (Odotetaan ja yritetään uudelleen)
  elif echo "$RESPONSE" | grep -iqE "out of host capacity|out of capacity|outcapacity|insufficient.*capacity|limit exceeded"; then
    ERROR_MSG=$(echo "$RESPONSE" | tr '\n' ' ' | cut -c 1-500)

    tmp=$(mktemp)
    jq --arg error "$ERROR_MSG" '
      .provision_fail_total = ((.provision_fail_total // 0) + 1)
      | .last_provision_error = $error
    ' "$STATS_FILE" > "$tmp" && mv "$tmp" "$STATS_FILE"

    echo "[$(date -Is)] Provision failed due to capacity. Sleeping 300 seconds."
    sleep 300

  # 3. KRIITTINEN VIRHE: Jokin konfiguraatio tai oikeus on väärin (Pysäytetään)
  else
    ERROR_MSG=$(echo "$RESPONSE" | tr '\n' ' ' | cut -c 1-500)

    # Päivitetään stats.json virhetiedot
    tmp=$(mktemp)
    jq --arg error "$ERROR_MSG" '
      .provision_fail_total = ((.provision_fail_total // 0) + 1)
      | .last_provision_error = $error
    ' "$STATS_FILE" > "$tmp" && mv "$tmp" "$STATS_FILE"

    # Päivitetään processes.json status stopped-tilaan, jotta /status ei näytä "running"
    tmp_proc=$(mktemp)

    if jq --argjson pid "$$" '
      .provision_arm.status = "stopped"
      | .provision_arm.stopped_at = now | todate
      | .provision_arm.stopped_pid = $pid
    ' "$PROCESSES_FILE" > "$tmp_proc" && mv "$tmp_proc" "$PROCESSES_FILE"; then
      PROCESS_STATE_UPDATED="yes"
    else
      PROCESS_STATE_UPDATED="no"
    fi

    echo "[$(date -Is)] CRITICAL ERROR ENCOUNTERED. Stopping daemon. PID=$$"

    ERROR_CODE=$(echo "$RESPONSE" | grep -o '"code": "[^"]*"' | head -1 | cut -d'"' -f4)
    ERROR_MESSAGE=$(echo "$RESPONSE" | grep -o '"message": "[^"]*"' | head -1 | cut -d'"' -f4)
    ERROR_STATUS=$(echo "$RESPONSE" | grep -o '"status": [0-9]*' | head -1 | awk '{print $2}')
    ERROR_OPERATION=$(echo "$RESPONSE" | grep -o '"operation_name": "[^"]*"' | head -1 | cut -d'"' -f4)
    ERROR_REQUEST_ID=$(echo "$RESPONSE" | grep -o '"opc-request-id": "[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$ERROR_CODE" ]; then
      ERROR_CODE="unknown"
    fi

    if [ -z "$ERROR_MESSAGE" ]; then
      ERROR_MESSAGE=$(echo "$RESPONSE" | tr '\n' ' ' | cut -c 1-300)
    fi

    if [ -z "$ERROR_STATUS" ]; then
      ERROR_STATUS="unknown"
    fi

    if [ -z "$ERROR_OPERATION" ]; then
      ERROR_OPERATION="unknown"
    fi

    if [ -z "$ERROR_REQUEST_ID" ]; then
      ERROR_REQUEST_ID="unknown"
    fi

    ALERT_MESSAGE=$(cat <<MSG
PROVISION_ARM STOPPED DUE TO CRITICAL ERROR

Process:
PID: $$
File: provision_arm.sh
Stopped: yes
processes.json updated: $PROCESS_STATE_UPDATED

Error:
Code: $ERROR_CODE
Status: $ERROR_STATUS
Operation: $ERROR_OPERATION
Message: $ERROR_MESSAGE

OCI request id:
$ERROR_REQUEST_ID

Action:
The daemon has exited. Check logs and restart with:
/start provision_arm
MSG
)

    "$BASE_DIR/infra-tools/tg_send.sh" "$ALERT_MESSAGE"

    exit 1
  fi
done
