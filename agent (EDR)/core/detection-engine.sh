#!/bin/bash

script_dir=$(dirname "$(readlink -f "$0")")

source "$script_dir/logger.sh"
source "$script_dir/../config/config.conf"

declare -A alerted_pids
declare -A last_alert_time

cooldown_seconds=10

[[ -f "$RULES_FILE" ]] || echo '{"process_rules":[]}' > "$RULES_FILE"
[[ -f "$POLICIES_FILE" ]] || echo '{"global":{"edr_response":false,"firewall_enabled":false}}' > "$POLICIES_FILE"

tail -F "$ENDPOINT_LOG" | while read -r line; do

    echo "$line" | jq -e . >/dev/null 2>&1 || continue

    event_type=$(echo "$line" | jq -r '.event_type // empty')
    process_name=$(echo "$line" | jq -r '.data.process_name // empty')
    command_line=$(echo "$line" | jq -r '.data.command_line // empty')
    pid=$(echo "$line" | jq -r '.data.pid // empty')

    [[ -z "$event_type" ]] && continue
    [[ -z "$pid" ]] && continue
    [[ ! "$pid" =~ ^[0-9]+$ ]] && continue

    if [[ "$event_type" == "process_start" ]]; then

        process_name=$(basename "$process_name" | tr -d '[:space:]')

        match=$(jq -c \
            --arg pname "$process_name" \
            --arg cmd "$command_line" \
            '
            .process_rules[]? |
            .value as $val |
            select(
                (.match == "process_name" and $pname == $val) or
                (.match == "command_line" and ($cmd | contains($val)))
            )
            ' "$RULES_FILE")

        [[ -z "$match" ]] && continue

        rule_name=$(echo "$match" | jq -r '.name')
        mitre_id=$(echo "$match" | jq -r '.mitre')
        severity=$(echo "$match" | jq -r '.severity')

        if [[ -n "${alerted_pids[$pid]:-}" ]]; then
            continue
        fi

        current_time=$(date +%s)
        last_time=${last_alert_time[$rule_name]:-0}

        if (( current_time - last_time < cooldown_seconds )); then
            continue
        fi

        alerted_pids[$pid]=1
        last_alert_time[$rule_name]=$current_time

        alert_json=$(jq -n \
            --arg rule "$rule_name" \
            --arg mitre "$mitre_id" \
            --arg proc "$process_name" \
            --arg sev "$severity" \
            --arg pid "$pid" \
            '{
                rule_id: $rule,
                mitre_technique: $mitre,
                process_name: $proc,
                severity: $sev,
                pid: ($pid|tonumber)
            }')

        jq -nc \
        --arg ts "$(date -Iseconds)" \
        --arg host "$HOST_ID" \
        --arg rule "$rule_name" \
        --arg mitre "$mitre_id" \
        --arg proc "$process_name" \
        --arg sev "$severity" \
        --arg pid "$pid" \
        '{
            timestamp: $ts,
            host: $host,
            event_type: "process_detection",
            rule_id: $rule,
            mitre_technique: $mitre,
            severity: $sev,
            process_name: $proc,
            pid: ($pid|tonumber)
        }' >> "$ALERT_LOG"

        log_event "CRITICAL" "DETECTION" "process_detection" "$alert_json"

        auto_kill=$(jq -r '.global.edr_response // false' "$POLICIES_FILE")

        if [[ "$auto_kill" == "true" && "$severity" == "CRITICAL" ]]; then
            log_event "CRITICAL" "DETECTION" "response_action" '{"action":"killing_process","pid":'$pid'}'
            bash "$script_dir/response.sh" "PROCESS" "$pid"
        fi

    fi

done
