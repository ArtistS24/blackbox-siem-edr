#!/bin/bash
set -euo pipefail

script_dir=$(dirname "$(readlink -f "$0")")

source "$script_dir/logger.sh"
source "$script_dir/../config/config.conf"

type="${1:-}"
target="${2:-}"

if [[ -z "$type" || -z "$target" ]]; then
    log_event "ERROR" "RESPONSE" "invalid_input" '{"error":"TYPE and TARGET required"}'
    exit 1
fi

[[ -f "$POLICIES_FILE" ]] || echo '{"global":{"edr_response":false}}' > "$POLICIES_FILE"

auto_kill=$(jq -r '.global.edr_response // false' "$POLICIES_FILE")

if [[ "$auto_kill" != "true" ]]; then

    skip_json=$(jq -n \
        --arg type "$type" \
        --arg target "$target" \
        '{
            action: "skipped",
            reason: "policy_disabled",
            target_type: $type,
            target: $target
        }')

    log_event "INFO" "RESPONSE" "policy_skip" "$skip_json"
    exit 0
fi

case "$type" in

    PROCESS)

        if kill -0 "$target" 2>/dev/null; then

            kill "$target" 2>/dev/null || true
            sleep 1

            if kill -0 "$target" 2>/dev/null; then
                kill -9 "$target" 2>/dev/null || true
            fi

            action_json=$(jq -n \
                --arg pid "$target" \
                '{
                    action: "process_terminated",
                    pid: ($pid|tonumber)
                }')

            log_event "CRITICAL" "RESPONSE" "action_executed" "$action_json"

        else

            fail_json=$(jq -n \
                --arg pid "$target" \
                '{
                    action: "process_not_found",
                    pid: ($pid|tonumber)
                }')

            log_event "WARNING" "RESPONSE" "action_failed" "$fail_json"

        fi
        ;;

    NETWORK_BLOCK)

        iptables -N BLACKBOX-IN 2>/dev/null || true
        iptables -N BLACKBOX-OUT 2>/dev/null || true
        iptables -C INPUT -j BLACKBOX-IN 2>/dev/null || iptables -I INPUT 1 -j BLACKBOX-IN 2>/dev/null || true
        iptables -C OUTPUT -j BLACKBOX-OUT 2>/dev/null || iptables -I OUTPUT 1 -j BLACKBOX-OUT 2>/dev/null || true
        iptables -I BLACKBOX-IN 1 -s "$target" -j DROP 2>/dev/null || true
        iptables -I BLACKBOX-OUT 1 -d "$target" -j DROP 2>/dev/null || true

        block_json=$(jq -n \
            --arg ip "$target" \
            '{
                action: "network_ip_blocked",
                target_ip: $ip
            }')

        log_event "CRITICAL" "RESPONSE" "action_executed" "$block_json"
        ;;

    *)

        unknown_json=$(jq -n \
            --arg type "$type" \
            --arg target "$target" \
            '{
                action: "unknown_type",
                target_type: $type,
                target: $target
            }')

        log_event "WARNING" "RESPONSE" "invalid_type" "$unknown_json"
        ;;

esac
