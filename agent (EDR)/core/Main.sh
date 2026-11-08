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
mkdir -p "$(dirname "$RULES_FILE")"
mkdir -p "$(dirname "$AGENT_ID_FILE")"
touch "$ENDPOINT_LOG"
touch "$ALERT_LOG"
[[ -s "$RULES_FILE" ]] || echo '{"process_rules":[]}' > "$RULES_FILE"
[[ -s "$POLICIES_FILE" ]] || echo '{"global":{"edr_response":true,"firewall_enabled":false},"settings":{"watch_dirs":"/tmp /home /var/www /opt","file_monitor_interval":0.5,"max_hash_size_mb":10,"hash_extensions":"sh py elf bin so jar exe run","process_monitor_interval":2,"file_event_ttl":2,"file_hash_ttl":300,"process_hash_ttl":600,"network_event_ttl":30}}' > "$POLICIES_FILE"
[[ -s "$FIREWALL_FILE" ]] || echo '{"default_input":"ACCEPT","default_output":"ACCEPT","rules":[]}' > "$FIREWALL_FILE"

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

while true; do
    if ! ps -p "$agent_pid" > /dev/null 2>&1; then
        bash "$script_dir/../agent/agent.sh" > /dev/null 2>&1 &
        agent_pid=$!
    fi
    if ! ps -p "$detection_pid" > /dev/null 2>&1; then
        bash "$script_dir/detection-engine.sh" > /dev/null 2>&1 &
        detection_pid=$!
    fi
    sleep 5
done

cleanup
