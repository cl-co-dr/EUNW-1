#!/usr/bin/env bash

set -euo pipefail

# =========================
# Configuration
# =========================
RPC="http://127.0.0.1:8545"
PATH_G="/root/BASE"
LOCK_FILE="/root/base.pid"
STATE_FILE="/root/base_last_block.state"
LOG_FILE="/var/log/base_block_monitor.log"

# =========================
# Logging
# =========================
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# =========================
# Functions
# =========================
get_block_number() {
  local hex
  hex=$(curl -s \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "$RPC" | jq -r '.result')

  if [[ -z "$hex" || "$hex" == "null" ]]; then
    echo "-1"
    return
  fi

  printf "%d\n" "$hex"
}

restart_once() {
  if [[ -f "$LOCK_FILE" ]]; then
    log "[WARN] Lock file exists, skipping restart"
    return
  fi

  log "[WARN] Block height stalled. Restarting node (one-time)"

  echo "restart_at=$(date '+%Y-%m-%d %H:%M:%S')" > "$LOCK_FILE"

  cd "$PATH_G"

  log "[INFO] docker compose down -t 100"
  docker compose down -t 100 >> "$LOG_FILE" 2>&1

  sleep 10

  log "[INFO] docker compose up -d"
  NODE_TYPE=base docker compose up -d >> "$LOG_FILE" 2>&1
}

# =========================
# Main (single-run)
# =========================
current_block=$(get_block_number)

if (( current_block < 0 )); then
  log "[ERROR] RPC error, exiting"
  exit 0
fi

if [[ ! -f "$STATE_FILE" ]]; then
  log "[INFO] Initial run. Saving block height: $current_block"
  echo "$current_block" > "$STATE_FILE"
  exit 0
fi

last_block=$(cat "$STATE_FILE")

log "[INFO] Current block: $current_block | Last block: $last_block"

if (( current_block <= last_block )); then
  restart_once
else
  echo "$current_block" > "$STATE_FILE"
  log "[INFO] Block height increased"
fi

