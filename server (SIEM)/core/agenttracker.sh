#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

source "$ROOT_DIR/config/config.conf"

HOSTNAME="$1"
IP="$2"
CPU="${3:-}"
MEM="${4:-}"

if [[ -z "$HOSTNAME" ]]; then
    exit 0
fi

AGENTS_PATH="$ROOT_DIR/$AGENTS_FILE"

if [ ! -f "$AGENTS_PATH" ]; then
    echo '{"agents":[]}' > "$AGENTS_PATH"
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

exists=$(jq --arg host "$HOSTNAME" '.agents[] | select(.hostname==$host)' "$AGENTS_PATH")

if [ -z "$exists" ]; then

    AGENT_ID=$(openssl rand -hex 4)

    jq --arg id "$AGENT_ID" \
       --arg host "$HOSTNAME" \
       --arg ip "$IP" \
       --arg time "$NOW" \
       --arg cpu "${CPU:-0}" \
       --arg mem "${MEM:-0}" \
       '(.agents) += [{
            "agent_id": $id,
            "hostname": $host,
            "ip": $ip,
            "first_seen": $time,
            "last_seen": $time,
            "last_heartbeat": $time,
            "cpu_percent": ($cpu|tonumber),
            "memory_kb": ($mem|tonumber),
            "status": "online"
       }]' "$AGENTS_PATH" > "$ROOT_DIR/storage/tmp.json"

    mv "$ROOT_DIR/storage/tmp.json" "$AGENTS_PATH"

else
    jq --arg host "$HOSTNAME" \
       --arg ip "$IP" \
       --arg time "$NOW" \
       --arg cpu "$CPU" \
       --arg mem "$MEM" \
       '(.agents[] | select(.hostname==$host)) |= (
          .last_seen = $time |
          .last_heartbeat = $time |
          .ip = $ip |
          .status = "online" |
          (if $cpu != "" then .cpu_percent = ($cpu|tonumber) else . end) |
          (if $mem != "" then .memory_kb = ($mem|tonumber) else . end)
       )' "$AGENTS_PATH" > "$ROOT_DIR/storage/tmp.json"

    mv "$ROOT_DIR/storage/tmp.json" "$AGENTS_PATH"
fi
