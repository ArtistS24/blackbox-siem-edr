#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "Must be root."
   exit 1
fi

echo "[*] Stopping BlackBox EDR Service..."
systemctl stop blackbox-edr
systemctl disable blackbox-edr

echo "[*] Cleaning Firewall..."
iptables -D INPUT -j BLACKBOX-IN 2>/dev/null
iptables -D OUTPUT -j BLACKBOX-OUT 2>/dev/null
iptables -F BLACKBOX-IN 2>/dev/null
iptables -F BLACKBOX-OUT 2>/dev/null
iptables -X BLACKBOX-IN 2>/dev/null
iptables -X BLACKBOX-OUT 2>/dev/null

echo "[*] Removing Files..."
rm -f /etc/systemd/system/blackbox-edr.service
systemctl daemon-reload
rm -rf /opt/blackbox-edr
rm -rf /var/log/blackbox-edr

echo "[✓] BlackBox EDR service uninstalled."
