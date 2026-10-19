log_event() {
  local level="$1"
  local module="$2"
  local event_type="$3"
  local json_data="$4"

  local auth_key="${AGENT_KEY:-unauthenticated}"

  json_output=$(jq -c -n \
    --arg ts "$(date -Iseconds)" \
    --arg host "$HOSTNAME" \
    --arg lvl "$level" \
    --arg mod "$module" \
    --arg evt "$event_type" \
    --arg key "$auth_key" \
    --argjson data "$json_data" \
    '{
      timestamp: $ts,
      host: $host,
      level: $lvl,
      module: $mod,
      event_type: $evt,
      auth_key: $key,
      data: $data
    }')

  echo "$json_output" | socat - TCP:$SIEM_IP:$SIEM_PORT

  echo "$json_output" >> "$ENDPOINT_LOG"
}
