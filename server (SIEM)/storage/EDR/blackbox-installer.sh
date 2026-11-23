#!/bin/bash
# Location: storage/EDR/blackbox-installer.sh

SIEM_URL="$1" 
INSTALL_DIR="/opt/blackbox-edr"
LOG_DIR="/var/log/blackbox-edr"

if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] Must be run as root (sudo)." 
   exit 1
fi

echo "=========================================="
echo "    BLACKBOX EDR - SYSTEM DEPLOYMENT"
echo "=========================================="

# 0. Ensure Required Endpoint Dependencies
MISSING_PKGS=()
for entry in "socat:socat" "jq:jq" "openssl:openssl" "inotifywait:inotify-tools" "iptables:iptables" "ss:iproute2" "curl:curl"; do
    cmd="${entry%%:*}"
    pkg="${entry##*:}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done
if (( ${#MISSING_PKGS[@]} > 0 )); then
    echo "[*] Installing missing dependencies: ${MISSING_PKGS[*]}..."
    if command -v apt >/dev/null 2>&1; then
        apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${MISSING_PKGS[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q "${MISSING_PKGS[@]}"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q "${MISSING_PKGS[@]}"
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm "${MISSING_PKGS[@]}"
    else
        echo "[ERROR] Unsupported package manager. Install manually: ${MISSING_PKGS[*]}"
        exit 1
    fi
fi

# 1. Fetch Metadata (Ports & IP)
echo "[*] Connecting to SIEM for configuration..."
curl -s -f "$SIEM_URL/connection.info" -o "/tmp/connection.info" || { echo "SIEM unreachable"; exit 1; }
source "/tmp/connection.info"

# 2. Create System Paths
echo "[*] Initializing system paths..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/configs"
mkdir -p "$LOG_DIR"

# 3. Download and Move Files
echo "[*] Downloading and installing EDR binaries..."
curl -s "$SIEM_URL/agent_package.tar.gz" -o "/tmp/agent.tar.gz"
tar -xzf "/tmp/agent.tar.gz" -C "/tmp"

# We move the contents of the EDR folder from the zip into /opt/blackbox-edr
cp -r /tmp/EDR/* "$INSTALL_DIR/"
rm -rf /tmp/EDR /tmp/agent.tar.gz

# 4. Inject Dynamic Config & Fix Paths
echo "[*] Optimizing local configuration..."
CONF="$INSTALL_DIR/config/config.conf"

# Update SIEM Connection (What we got from connection.info)
sed -i "s|^SIEM_IP=.*|SIEM_IP=\"$SIEM_IP\"|" "$CONF"
sed -i "s|^SIEM_PORT=.*|SIEM_PORT=\"$SIEM_INGEST_PORT\"|" "$CONF"
sed -i "s|^SIEM_WEB_PORT=.*|SIEM_WEB_PORT=\"$SIEM_WEB_PORT\"|" "$CONF"

# Update Local Paths (Ensure they match the system install)
sed -i "s|^INSTALL_DIR=.*|INSTALL_DIR=\"$INSTALL_DIR\"|" "$CONF"
sed -i "s|^LOG_DIR=.*|LOG_DIR=\"$LOG_DIR\"|" "$CONF"

# 5. Set Executable Permissions
chmod +x "$INSTALL_DIR/core/"*.sh
chmod +x "$INSTALL_DIR/agent/"*.sh

# 6. Create the Systemd Service
echo "[*] Registering background service..."
cat <<SVC > /etc/systemd/system/blackbox-edr.service
[Unit]
Description=BlackBox EDR Agent Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash $INSTALL_DIR/core/Main.sh
Restart=always
RestartSec=5
User=root
StandardOutput=append:$LOG_DIR/service.out
StandardError=append:$LOG_DIR/service.out

[Install]
WantedBy=multi-user.target
SVC


# 6.5 HARDENING: Lock down permissions
echo "[*] Hardening file system permissions..."
chown -R root:root "$INSTALL_DIR"
chown -R root:root "$LOG_DIR"
chmod -R 700 "$INSTALL_DIR"
chmod -R 700 "$LOG_DIR"


# 7. Start the Engine
systemctl daemon-reload
systemctl enable blackbox-edr --now

echo "=========================================="
echo " [✓] SUCCESS: BlackBox EDR is now a system service."
echo " [✓] Files:    $INSTALL_DIR"
echo " [✓] Logs:     $LOG_DIR"
echo " [✓] Status:   Active and Reporting to $SIEM_IP"
echo "=========================================="