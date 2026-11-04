#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
source "$ROOT_DIR/config/config.conf"

MY_IP=$(hostname -I | awk '{print $1}')

cat <<EOF > "$ROOT_DIR/storage/connection.info"
SIEM_IP="$MY_IP"
SIEM_INGEST_PORT="$LISTEN_PORT"
SIEM_WEB_PORT="$WEB_PORT"
EOF

echo "[*] Packaging EDR agent..."
cd "$ROOT_DIR/.."
if [[ -d "EDR" ]]; then
    tar --owner=0 --group=0 -czf "$ROOT_DIR/storage/agent_package.tar.gz" EDR/
elif [[ -d "agent (EDR)" ]]; then
    tar --owner=0 --group=0 --transform 's|^agent (EDR)|EDR|' -czf "$ROOT_DIR/storage/agent_package.tar.gz" "agent (EDR)"/
fi

echo "[*] Deployment files ready."
