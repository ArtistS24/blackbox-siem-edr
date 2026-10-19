#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
CONFIG_FILE="$ROOT_DIR/config/config.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    mkdir -p "$ROOT_DIR/config"
    echo "INITIALIZED=false" > "$CONFIG_FILE"
    LISTEN_PORT=9000
    WEB_PORT=9100
    LOG_DIR="logs"
    SERVICE_LOGS_DIR="services-logs"
fi

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
nc='\033[0m'

set_config() {
    key="$1"
    value="$2"
    if grep -q "^$key=" "$CONFIG_FILE"; then
        sed -i "s|^$key=.*|$key=$value|" "$CONFIG_FILE"
    else
        echo "$key=$value" >> "$CONFIG_FILE"
    fi
}

check_port() {
    local port="$1"

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo -e "${red}[!] Invalid port format.${nc}"
        return 1
    fi

    if (( port < 1 || port > 65535 )); then
        echo -e "${red}[!] Port must be between 1-65535.${nc}"
        return 1
    fi

    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$port$"; then
        echo -e "${red}[!] Port $port is currently in use on this system.${nc}"
        return 1
    fi

    return 0
}

clear
echo -e "${cyan}"
echo "====================================="
echo "      BLACK BOX SIEM SETUP"
echo "====================================="
echo -e "${nc}"

while true; do
    read -rp "Enter SIEM Ingest port (Logs) [default: $LISTEN_PORT]: " port
    port=${port:-$LISTEN_PORT}
    check_port "$port" && break
done

while true; do
    read -rp "Enter SIEM Web port (Files) [default: $WEB_PORT]: " web_port
    web_port=${web_port:-$WEB_PORT}

    if [[ "$web_port" == "$port" ]]; then
        echo -e "${red}[!] WEB port cannot be the same as Ingest port.${nc}"
        continue
    fi

    check_port "$web_port" && break
done

read -rp "Log directory name [default: $LOG_DIR]: " log_dir
log_dir=${log_dir:-$LOG_DIR}

read -rp "Service PIDs directory [default: $SERVICE_LOGS_DIR]: " service_logs_dir
service_logs_dir=${service_logs_dir:-$SERVICE_LOGS_DIR}

read -rp "Enable EDR Active Response (Kill on Match)? (y/n) [default: y]: " edr_response
edr_response=${edr_response:-y}
[[ "$edr_response" =~ ^[Yy]$ ]] && edr_response_val=true || edr_response_val=false

read -rp "Enable SIEM-managed Firewall? (y/n) [default: n]: " firewall
firewall=${firewall:-n}
[[ "$firewall" =~ ^[Yy]$ ]] && firewall_val=true || firewall_val=false

echo -e "\n${yellow}[+] Saving system configuration...${nc}"

set_config "LISTEN_PORT" "$port"
set_config "WEB_PORT" "$web_port"
set_config "LOG_DIR" "\"$log_dir\""
set_config "SERVICE_LOGS_DIR" "\"$service_logs_dir\""
set_config "INITIALIZED" "true"

echo -e "${yellow}[+] Initializing data structures...${nc}"

mkdir -p "$ROOT_DIR/storage"
mkdir -p "$ROOT_DIR/storage/EDR"
mkdir -p "$ROOT_DIR/$log_dir"
mkdir -p "$ROOT_DIR/$service_logs_dir"

touch "$ROOT_DIR/$log_dir/events.log"
touch "$ROOT_DIR/$log_dir/alerts.log"

if [[ ! -f "$ROOT_DIR/storage/policies.json" ]]; then
    cat <<EOF > "$ROOT_DIR/storage/policies.json"
{
  "global": {
    "edr_response": $edr_response_val,
    "firewall_enabled": $firewall_val
  },
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

if [[ ! -f "$ROOT_DIR/storage/rules.json" ]]; then
    echo '{"process_rules":[]}' > "$ROOT_DIR/storage/rules.json"
fi

if [[ ! -f "$ROOT_DIR/storage/firewall.json" ]]; then
    echo '{"default_input":"ACCEPT","default_output":"ACCEPT","rules":[]}' > "$ROOT_DIR/storage/firewall.json"
fi

if [[ ! -f "$ROOT_DIR/storage/agents.json" ]]; then
    echo '{"agents":[]}' > "$ROOT_DIR/storage/agents.json"
fi

MY_IP=$(hostname -I | awk '{print $1}')

echo -e "${green}"
echo "====================================="
echo "      SETUP COMPLETE"
echo "====================================="
echo -e "${nc}"
echo " Ingest Port       : $port"
echo " Web Port          : $web_port"
echo " Log Storage       : $ROOT_DIR/$log_dir"
echo " Active Response   : $edr_response_val"
echo " Firewall Logic    : $firewall_val"
echo "-------------------------------------"
echo -e "${cyan}Agent Enrollment URL:${nc} http://$MY_IP:$web_port"
echo ""
echo "You can now start the SIEM by running: ./SIEM.sh"
echo ""

sleep 2
