#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../config/config.conf"
source "$SCRIPT_DIR/logger.sh"

if [[ $EUID -ne 0 ]]; then
    log_event "ERROR" "FIREWALL" "permission_denied" '{"error":"Firewall requires root"}'
    exit 1
fi

ENABLED=$(jq -r '.global.firewall_enabled // false' "$POLICIES_FILE" 2>/dev/null)

if [[ "$ENABLED" != "true" ]]; then
    iptables -F BLACKBOX-IN 2>/dev/null
    iptables -F BLACKBOX-OUT 2>/dev/null
    exit 0
fi

iptables -N BLACKBOX-IN 2>/dev/null
iptables -N BLACKBOX-OUT 2>/dev/null

if ! iptables -C INPUT -j BLACKBOX-IN 2>/dev/null; then
    iptables -I INPUT 1 -j BLACKBOX-IN
fi
if ! iptables -C OUTPUT -j BLACKBOX-OUT 2>/dev/null; then
    iptables -I OUTPUT 1 -j BLACKBOX-OUT
fi

iptables -F BLACKBOX-IN
iptables -F BLACKBOX-OUT

iptables -A BLACKBOX-IN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A BLACKBOX-OUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A BLACKBOX-IN -i lo -j ACCEPT
iptables -A BLACKBOX-OUT -o lo -j ACCEPT
iptables -A BLACKBOX-IN -p tcp --dport 22 -j ACCEPT
iptables -A BLACKBOX-OUT -p tcp --dport "$SIEM_PORT" -j ACCEPT
iptables -A BLACKBOX-OUT -p tcp --dport "$SIEM_WEB_PORT" -j ACCEPT

if [[ ! -f "$FIREWALL_FILE" ]]; then
    log_event "WARNING" "FIREWALL" "missing_config" '{"path":"'$FIREWALL_FILE'"}'
    exit 0
fi

COUNT=$(jq '.rules | length' "$FIREWALL_FILE")

for (( i=0; i<$COUNT; i++ )); do
    direction=$(jq -r ".rules[$i].direction" "$FIREWALL_FILE")
    action=$(jq -r ".rules[$i].action" "$FIREWALL_FILE")
    ip=$(jq -r ".rules[$i].ip // empty" "$FIREWALL_FILE")
    port=$(jq -r ".rules[$i].port // empty" "$FIREWALL_FILE")
    proto=$(jq -r ".rules[$i].protocol // \"tcp\"" "$FIREWALL_FILE")

    if [[ "$direction" == "in" ]]; then
        cmd="iptables -A BLACKBOX-IN"
        [[ -n "$ip" ]] && cmd="$cmd -s $ip"
    else
        cmd="iptables -A BLACKBOX-OUT"
        [[ -n "$ip" ]] && cmd="$cmd -d $ip"
    fi

    [[ -n "$port" ]] && cmd="$cmd -p $proto --dport $port"

    cmd="$cmd -j $action"

    $cmd
done

log_event "INFO" "FIREWALL" "rules_applied" '{"rule_count":'$COUNT'}'
