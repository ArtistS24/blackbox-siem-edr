#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

source "$ROOT_DIR/config/config.conf"

echo "[SIEM] Starting WEB server on port $WEB_PORT..."

cd "$ROOT_DIR/storage"
if [[ -z "$WEB_PORT" ]]; then
    echo "[ERROR] WEB_PORT is not set in config."
    exit 1
fi

while true; do
    python3 -m http.server "$WEB_PORT"
    echo "[!] Web server crashed, restarting..."
    sleep 5
done
