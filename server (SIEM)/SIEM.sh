#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must be run as root."
   exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

CONFIG_FILE="$ROOT_DIR/config/config.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "[ERROR] Missing config file. Run setup first."
    exit 1
fi

EVENT_LOG="${EVENT_LOG:-logs/events.log}"
ALERT_LOG="${ALERT_LOG:-logs/alerts.log}"
AGENTS_FILE="${AGENTS_FILE:-storage/agents.json}"

echo "================================="
echo "    Black Box SIEM Framework     "
echo "================================="
echo "Version: ${SIEM_VERSION:-1.0}"
echo

for cmd in socat jq openssl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "[ERROR] Missing dependency: $cmd"
        read -rp "Install it now? (y/n): " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install -y "$cmd"
            elif command -v yum &> /dev/null; then
                sudo yum install -y "$cmd"
            elif command -v pacman &> /dev/null; then
                sudo pacman -S --noconfirm "$cmd"
            else
                echo "[ERROR] Unsupported package manager."
                exit 1
            fi
        else
            echo "[SIEM] Cannot continue without $cmd."
            exit 1
        fi
    fi
done

if ! grep -q "^INITIALIZED=true" "$CONFIG_FILE"; then
    echo "[SIEM] First time setup detected..."
    bash "$ROOT_DIR/core/setup.sh"
fi

mkdir -p "$ROOT_DIR/$LOG_DIR"
mkdir -p "$ROOT_DIR/storage"
mkdir -p "$ROOT_DIR/$SERVICE_LOGS_DIR"
touch "$ROOT_DIR/$EVENT_LOG"
touch "$ROOT_DIR/$ALERT_LOG"

if [ ! -s "$ROOT_DIR/$AGENTS_FILE" ]; then
    echo '{"agents":[]}' > "$ROOT_DIR/$AGENTS_FILE"
fi
if [ ! -s "$ROOT_DIR/storage/rules.json" ] || ! jq -e '.process_rules' "$ROOT_DIR/storage/rules.json" >/dev/null 2>&1; then
    echo '{"process_rules":[]}' > "$ROOT_DIR/storage/rules.json"
fi
if [ ! -s "$ROOT_DIR/storage/policies.json" ]; then
    cat <<EOF > "$ROOT_DIR/storage/policies.json"
{
  "global": {"edr_response":true, "firewall_enabled":false},
  "settings": {
    "watch_dirs": "/tmp /home /var/www /opt",
    "file_monitor_interval": 0.5,
    "max_hash_size_mb": 10,
    "hash_extensions": "sh py elf bin so jar exe run",
    "process_monitor_interval": 2,
    "file_event_ttl": 2,
    "file_hash_ttl": 300,
    "process_hash_ttl": 600,
    "network_event_ttl": 30
  }
}
EOF
fi

is_running() {
    local pid_file="$1"
    [[ -f "$pid_file" ]] && ps -p $(cat "$pid_file") > /dev/null 2>&1
}

INGEST_RUNNING=false
PARSER_RUNNING=false
WEB_RUNNING=false

is_running "$ROOT_DIR/$SERVICE_LOGS_DIR/ingest.pid" && INGEST_RUNNING=true
is_running "$ROOT_DIR/$SERVICE_LOGS_DIR/parser.pid" && PARSER_RUNNING=true
is_running "$ROOT_DIR/$SERVICE_LOGS_DIR/web.pid" && WEB_RUNNING=true

if $INGEST_RUNNING && $PARSER_RUNNING && $WEB_RUNNING; then
    echo "[SIEM] Services already running."
    echo "[SIEM] Launching dashboard only..."
    echo
    sleep 1.5
    bash "$ROOT_DIR/cli/dashboard.sh"
    exit 0
fi

echo "[SIEM] Starting missing services..."

if ! $INGEST_RUNNING; then
    echo "[SIEM] Starting ingestion engine..."
    nohup bash "$ROOT_DIR/core/ingest.sh" > "$ROOT_DIR/logs/ingest.out" 2>&1 &
    echo $! > "$ROOT_DIR/$SERVICE_LOGS_DIR/ingest.pid"
fi

if ! $PARSER_RUNNING; then
    echo "[SIEM] Starting parser engine..."
    nohup bash "$ROOT_DIR/core/parser.sh" > "$ROOT_DIR/logs/parser.out" 2>&1 &
    echo $! > "$ROOT_DIR/$SERVICE_LOGS_DIR/parser.pid"
fi

if ! $WEB_RUNNING; then
    echo "[SIEM] Starting WEB server..."
    nohup bash "$ROOT_DIR/core/web-server.sh" > "$ROOT_DIR/logs/web.out" 2>&1 &
    echo $! > "$ROOT_DIR/$SERVICE_LOGS_DIR/web.pid"
fi

sleep 1

is_running "$ROOT_DIR/$SERVICE_LOGS_DIR/ingest.pid" || echo "[ERROR] Ingest failed to start"
is_running "$ROOT_DIR/$SERVICE_LOGS_DIR/parser.pid" || echo "[ERROR] Parser failed to start"
is_running "$ROOT_DIR/$SERVICE_LOGS_DIR/web.pid" || echo "[ERROR] WEB server failed to start"

echo "[SIEM] Preparing EDR deployment packages..."
bash "$ROOT_DIR/core/prep-deployment.sh"

echo "[SIEM] System ready."
echo

echo "[SIEM] Launching dashboard..."
echo "[INFO] Press Ctrl+C to exit dashboard (services stay running)"
echo

bash "$ROOT_DIR/cli/dashboard.sh"

echo
echo "[SIEM] Dashboard closed."
echo "[SIEM] Services are still running in background."
echo "Use ./core/stopservice.sh to stop them."
