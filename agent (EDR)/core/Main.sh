#!/bin/bash

REQUIRED_CMDS=(jq inotifywait ss sha256sum openssl ps awk stat readlink curl)

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] Missing dependency: $cmd"
        exit 1
    fi
done

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] EDR Service must be run as root."
    exit 1
fi

script_dir=$(dirname "$(readlink -f "$0")")
source "$script_dir/../config/config.conf"

mkdir -p "$LOG_DIR"
touch "$ENDPOINT_LOG"
touch "$ALERT_LOG"

echo "[$(date)] BlackBox EDR Service Starting..." >> "$LOG_DIR/service.out"

bash "$script_dir/sync.sh" > /dev/null 2>&1 &
sync_pid=$!

bash "$script_dir/../agent/agent.sh" > /dev/null 2>&1 &
agent_pid=$!

bash "$script_dir/detection-engine.sh" > /dev/null 2>&1 &
detection_pid=$!

cleanup() {
     echo "[$(date)] Shutdown initiated..." >> "$LOG_DIR/service.out"
     kill "$agent_pid" "$detection_pid" "$sync_pid" 2>/dev/null
     pkill -f "sync.sh"
     pkill -f "agent.sh"
     pkill -f "detection-engine.sh"
     exit 0
}

trap cleanup SIGINT SIGTERM EXIT

while ps -p "$agent_pid" > /dev/null; do
    sleep 5
done

cleanup
