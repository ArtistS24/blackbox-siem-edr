#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../config/config.conf"
source "$SCRIPT_DIR/logger.sh"

SYNC_FILES=(
    "policies.json|$POLICIES_FILE"
    "rules.json|$RULES_FILE"
    "firewall.json|$FIREWALL_FILE"
)

while true; do
    NEEDS_RESTART=false
    NEEDS_FW_RELOAD=false

    for item in "${SYNC_FILES[@]}"; do
        REMOTE_NAME="${item%|*}"
        LOCAL_PATH="${item#*|}"

        curl -s -f "http://$SIEM_IP:$SIEM_WEB_PORT/$REMOTE_NAME" -o "$LOCAL_PATH.tmp"

        if [[ -f "$LOCAL_PATH.tmp" ]] && jq . "$LOCAL_PATH.tmp" >/dev/null 2>&1; then

            if ! diff -q "$LOCAL_PATH" "$LOCAL_PATH.tmp" > /dev/null 2>&1; then
                mv "$LOCAL_PATH.tmp" "$LOCAL_PATH"

                if [[ "$REMOTE_NAME" == "firewall.json" ]]; then
                    NEEDS_FW_RELOAD=true
                else
                    NEEDS_RESTART=true
                fi

                log_event "INFO" "SYNC" "config_updated" '{"file":"'$REMOTE_NAME'"}'
            else
                rm "$LOCAL_PATH.tmp"
            fi
        fi
    done

    if $NEEDS_RESTART; then
        log_event "INFO" "SYNC" "engine_restart" '{"reason":"policy_or_rule_change"}'
        pkill -f "agent.sh"
        pkill -f "detection-engine.sh"
    fi

    if $NEEDS_FW_RELOAD; then
        FW_ENABLED=$(jq -r '.global.firewall_enabled // false' "$POLICIES_FILE")
        if [[ "$FW_ENABLED" == "true" ]]; then
            bash "$SCRIPT_DIR/firewall.sh"
        else
            iptables -F BLACKBOX-IN 2>/dev/null
            iptables -F BLACKBOX-OUT 2>/dev/null
        fi
    fi

    sleep 60
done
