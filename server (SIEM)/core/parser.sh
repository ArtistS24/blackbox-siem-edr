#!/bin/bash

set -o pipefail
set -o nounset

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

source "$ROOT_DIR/config/config.conf"

tail -F "$ROOT_DIR/$EVENT_LOG" | while read -r line
do
    [[ -z "$line" ]] && continue

    if (( ${#line} > $MAX_EVENT_SIZE )); then
        continue
    fi

    echo "$line" | jq -e . >/dev/null 2>&1 || continue

    event_type=$(echo "$line" | jq -r '.event_type // "unknown"')
    host=$(echo "$line" | jq -r '.host // empty')
    ip=$(echo "$line" | jq -r '.ip // .data.ip // empty')

    processed_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    normalized=$(echo "$line" | jq -c \
        --arg pt "$processed_time" \
        '. + {processed_at: $pt}')

    if [[ -n "$host" ]]; then
        cpu_stat=""
        mem_stat=""

        if [[ "$event_type" == "heartbeat" ]]; then
            cpu_stat=$(echo "$line" | jq -r '.data.cpu_percent // empty')
            mem_stat=$(echo "$line" | jq -r '.data.memory_kb // empty')
        fi

        bash "$ROOT_DIR/core/agenttracker.sh" "$host" "$ip" "$cpu_stat" "$mem_stat"
    fi

    case "$event_type" in
        "process_detection"|"detection"|"response_action"|"action_executed")
            echo "$normalized" >> "$ROOT_DIR/$ALERT_LOG"
        ;;
        *)
            echo "$normalized" >> "$ROOT_DIR/${EVENT_LOG}.processed"
        ;;
    esac
done
