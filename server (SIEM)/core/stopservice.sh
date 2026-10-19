#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
CONFIG_FILE="$ROOT_DIR/config/config.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "[ERROR] Missing config file."
    exit 1
fi

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
nc='\033[0m'

echo "[SIEM] Stopping services..."

kill_pid() {
    local pid="$1"
    local name="$2"

    if ps -p "$pid" > /dev/null 2>&1; then
        kill "$pid" 2>/dev/null
        sleep 0.5

        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${yellow}[!] Force killing $name (PID $pid)...${nc}"
            kill -9 "$pid" 2>/dev/null
        fi

        echo -e "${green}[*] Stopped $name${nc}"
    else
        echo -e "${yellow}[!] $name not running${nc}"
    fi
}

for service in ingest parser web; do
    pid_file="$ROOT_DIR/$SERVICE_LOGS_DIR/${service}.pid"

    if [[ -f "$pid_file" ]]; then
        pid=$(cat "$pid_file" 2>/dev/null)

        if [[ -n "$pid" ]]; then
            kill_pid "$pid" "$service"
        else
            echo -e "${yellow}[!] Invalid PID file for $service${nc}"
        fi

        rm -f "$pid_file"
    else
        echo -e "${yellow}[!] No PID file for $service${nc}"
    fi
done

echo "[SIEM] Cleaning up ports..."

for port in "$LISTEN_PORT" "$WEB_PORT"; do
    pids=$(lsof -ti tcp:"$port" 2>/dev/null)

    if [[ -n "$pids" ]]; then
        for p in $pids; do
            kill "$p" 2>/dev/null
            sleep 0.3
            kill -9 "$p" 2>/dev/null
        done
        echo -e "${green}[*] Freed port $port${nc}"
    else
        echo -e "${yellow}[!] Port $port already free${nc}"
    fi
done

sleep 0.5
remaining=$(ss -ltn 2>/dev/null | grep -E ":($LISTEN_PORT|$WEB_PORT) ")

if [[ -n "$remaining" ]]; then
    echo -e "${red}[!] WARNING: Some services still running:${nc}"
    echo "$remaining"
else
    echo -e "${green}[*] All services fully stopped.${nc}"
fi

echo "[SIEM] Shutdown complete."
