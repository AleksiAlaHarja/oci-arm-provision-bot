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

  if echo "$RESPONSE" | grep -q "ocid1.instance"; then
    tmp=$(mktemp)
    jq --arg now "$NOW" '
      .provision_success_total = ((.provision_success_total // 0) + 1)
      | .last_provision_success_at = $now
    ' "$STATS_FILE" > "$tmp" && mv "$tmp" "$STATS_FILE"

    echo "[$(date -Is)] Provision succeeded"

    "$BASE_DIR/infra-tools/tg_send.sh" "ARM instance provision succeeded."

    exit 0
  else
    ERROR_MSG=$(echo "$RESPONSE" | tr '\n' ' ' | cut -c 1-500)

    tmp=$(mktemp)
    jq --arg error "$ERROR_MSG" '
      .provision_fail_total = ((.provision_fail_total // 0) + 1)
      | .last_provision_error = $error
    ' "$STATS_FILE" > "$tmp" && mv "$tmp" "$STATS_FILE"

    echo "[$(date -Is)] Provision failed"
    echo "[$(date -Is)] Error saved to stats.json"
    echo "[$(date -Is)] Sleeping 300 seconds before next attempt"

    sleep 300
  fi
done
