log_event() {
  local level="$1"
  local module="$2"
  local event_type="$3"
  local json_data="$4"

  local auth_key="${AGENT_KEY:-unauthenticated}"

  json_output=$(jq -c -n \
    --arg ts "$(date -Iseconds)" \
    --arg host "${HOST_ID:-${HOSTNAME:-$(hostname)}}" \
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

  if command -v socat >/dev/null 2>&1; then
    echo "$json_output" | socat - TCP:$SIEM_IP:$SIEM_PORT 2>/dev/null || true
  else
    (echo "$json_output" > "/dev/tcp/$SIEM_IP/$SIEM_PORT") 2>/dev/null || true
  fi

  echo "$json_output" >> "$ENDPOINT_LOG"
}
