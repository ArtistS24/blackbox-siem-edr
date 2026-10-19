#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

source "$ROOT_DIR/config/config.conf"

mkdir -p "$ROOT_DIR/$LOG_DIR"

if [ ! -f "$ROOT_DIR/$EVENT_LOG" ]; then
    touch "$ROOT_DIR/$EVENT_LOG"
fi

echo "[SIEM] Listening for agents on port $LISTEN_PORT..."

while true; do
    socat TCP-LISTEN:$LISTEN_PORT,reuseaddr,fork SYSTEM:"cat >> $ROOT_DIR/$EVENT_LOG"
    echo "[!] socat crashed, restarting..."
    sleep 5
done