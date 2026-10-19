#!/bin/bash

set -o pipefail
set -o nounset

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/logger.sh"
source "$SCRIPT_DIR/../config/config.conf"

AGENT_ID_FILE="${AGENT_ID_FILE:-/tmp/agent_id}"
mkdir -p "$(dirname "$AGENT_ID_FILE")"

if [[ -f "$AGENT_ID_FILE" ]]; then
    AGENT_ID=$(cat "$AGENT_ID_FILE")
else
    AGENT_ID=$(openssl rand -hex 8)
    echo "$AGENT_ID" > "$AGENT_ID_FILE"
fi

HOSTNAME=$(hostname)
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
MAC_ADDR=$(ip link show 2>/dev/null | awk '/ether/ {print $2; exit}')
MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || echo "N/A")

declare -A seen_processes_map
declare -A seen_network_connections
declare -A file_event_cache
declare -A file_hash_cache
declare -A file_hash_time
declare -A process_hash_cache
declare -A process_hash_time
declare -A login_session_cache

declare -A PID_COMM_CACHE
declare -A PID_PATH_CACHE

NETWORK_EVENT_TTL=${NETWORK_EVENT_TTL:-30}
FILE_EVENT_TTL=${FILE_EVENT_TTL:-2}
FILE_HASH_TTL=${FILE_HASH_TTL:-300}
PROCESS_HASH_TTL=${PROCESS_HASH_TTL:-600}

PROCESS_MONITOR_INTERVAL=${PROCESS_MONITOR_INTERVAL:-2}
NETWORK_MONITOR_INTERVAL=${NETWORK_MONITOR_INTERVAL:-5}
LOGIN_MONITOR_INTERVAL=${LOGIN_MONITOR_INTERVAL:-10}
HEARTBEAT_INTERVAL=${HEARTBEAT_INTERVAL:-30}

MAX_HASH_SIZE=$(( ${MAX_HASH_SIZE_MB:-10} * 1024 * 1024 ))
IFS=' ' read -r -a HASH_EXT_ARRAY <<< "${HASH_EXTENSIONS:-sh py elf bin exe}"

sys_info=$(jq -n \
 --arg agent "$AGENT_ID" \
 --arg kernel "$(uname -r)" \
 --arg os "$(uname -s)" \
 --arg arch "$(uname -m)" \
 --arg hostname "$HOSTNAME" \
 --arg ip "$HOST_IP" \
 --arg mac "$MAC_ADDR" \
 --arg machine "$MACHINE_ID" \
 '{
   agent_id:$agent,
   kernel:$kernel,
   os:$os,
   architecture:$arch,
   hostname:$hostname,
   ip:$ip,
   mac_address:$mac,
   machine_id:$machine
 }')

log_event "INFO" "AGENT" "agent_start" "$sys_info"

trap "exit 0" SIGINT SIGTERM

should_hash_file(){
    local file="$1"
    ext="${file##*.}"
    for allowed in "${HASH_EXT_ARRAY[@]}"; do
        [[ "$ext" == "$allowed" ]] && return 0
    done
    return 1
}

file_monitor(){
inotifywait -m -r -e create,delete,move,close_write \
--exclude '(^|/)\.#|~$|\.swp$|\.tmp$|/tmp/#' --format '%e %w%f' $WATCH_DIRS |
while read -r event file
do
    now=$(date +%s)
    [[ -z "$file" ]] && continue
    key="${file}_${event}"
    last=${file_event_cache[$key]:-0}

    if (( now - last < FILE_EVENT_TTL )); then
        continue
    fi
    file_event_cache[$key]=$now

    if [[ -f "$file" ]]; then
        size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        hash="N/A"
        if should_hash_file "$file" && [[ "$size" -le "$MAX_HASH_SIZE" ]]; then
            last_hash=${file_hash_time[$file]:-0}
            if (( now - last_hash > FILE_HASH_TTL )); then
                hash=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
                file_hash_cache[$file]=$hash
                file_hash_time[$file]=$now
            else
                hash=${file_hash_cache[$file]}
            fi
        fi
        owner=$(stat -c '%U' "$file" 2>/dev/null || echo "unknown")
        perms=$(stat -c '%a' "$file" 2>/dev/null || echo "000")

        json_data=$(jq -n \
        --arg path "$file" \
        --arg hash "$hash" \
        --arg event "$event" \
        --arg owner "$owner" \
        --arg perms "$perms" \
        '{
            file_path:$path,
            sha256:$hash,
            action:$event,
            owner:$owner,
            permissions:$perms
        }')
    else
        unset file_hash_cache["$file"]
        json_data=$(jq -n \
        --arg path "$file" \
        --arg event "$event" \
        '{
            file_path:$path,
            action:$event
        }')
    fi
    log_event "INFO" "FILE_MONITOR" "file_event" "$json_data"
done
}

login_monitor(){
while read -r user tty date time rest; do
    ip=$(echo "$rest" | tr -d '()')
    session_key="${user}_${tty}_${ip}"
    if [[ -z "${login_session_cache[$session_key]:-}" ]]; then
        login_session_cache[$session_key]=1
        json=$(jq -n \
        --arg user "$user" \
        --arg tty "$tty" \
        --arg ip "$ip" \
        '{
            user:$user,
            terminal:$tty,
            source_ip:$ip
        }')
        log_event "INFO" "AUTH_MONITOR" "user_login" "$json"
    fi
done < <(who)
}

process_monitor(){
now=$(date +%s)
while read -r pid ppid user comm args; do
    [[ -z "$pid" || ! -d "/proc/$pid" ]] && continue

    proc_start=$(awk '{print $22}' /proc/$pid/stat 2>/dev/null || echo "")
    [[ -z "$proc_start" ]] && continue
    proc_key="${pid}_${proc_start}"

    PID_COMM_CACHE[$pid]="$comm"

    if [[ -z "${seen_processes_map[$proc_key]:-}" ]]; then
        proc_path=$(readlink -f /proc/$pid/exe 2>/dev/null || echo "")

        PID_PATH_CACHE[$pid]="$proc_path"

        parent_name=$(ps -p "$ppid" -o comm= 2>/dev/null || echo "")
        cwd=$(readlink -f /proc/$pid/cwd 2>/dev/null || echo "")
        uid=$(awk '/Uid:/ {print $2}' /proc/$pid/status 2>/dev/null || echo 0)
        gid=$(awk '/Gid:/ {print $2}' /proc/$pid/status 2>/dev/null || echo 0)

        exec_hash="N/A"
        if [[ -f "$proc_path" ]]; then
            last_hash=${process_hash_time[$proc_path]:-0}
            if (( now - last_hash > PROCESS_HASH_TTL )); then
                exec_hash=$(sha256sum "$proc_path" 2>/dev/null | awk '{print $1}')
                process_hash_cache[$proc_path]=$exec_hash
                process_hash_time[$proc_path]=$now
            else
                exec_hash=${process_hash_cache[$proc_path]}
            fi
        fi

        json_data=$(jq -n \
        --arg pid "$pid" \
        --arg ppid "$ppid" \
        --arg user "$user" \
        --arg process "$comm" \
        --arg cmd "$args" \
        --arg path "$proc_path" \
        --arg parent "$parent_name" \
        --arg uid "$uid" \
        --arg gid "$gid" \
        --arg cwd "$cwd" \
        --arg hash "$exec_hash" \
        '{
            pid:($pid|tonumber),
            ppid:($ppid|tonumber),
            user:$user,
            uid:($uid|tonumber),
            gid:($gid|tonumber),
            process_name:$process,
            parent_process:$parent,
            process_path:$path,
            process_hash:$hash,
            working_directory:$cwd,
            command_line:$cmd
        }')
        log_event "INFO" "PROCESS_MONITOR" "process_start" "$json_data"
        seen_processes_map[$proc_key]=$now
    fi
done < <(ps -eo pid,ppid,user,comm,args --no-headers)
}

network_monitor(){
now=$(date +%s)
while read -r state proto rec send local remote details; do
    pid_temp="${details#*pid=}"
    pid="${pid_temp%%,*}"

    [[ -z "$pid" || ! "$pid" =~ ^[0-9]+$ ]] && continue

    src_ip=${local%:*}
    src_port=${local##*:}
    dst_ip=${remote%:*}
    dst_port=${remote##*:}
    [[ "$src_port" =~ ^[0-9]+$ ]] || src_port=0
    [[ "$dst_port" =~ ^[0-9]+$ ]] || dst_port=0

    conn_key="${pid}_${src_ip}_${src_port}_${dst_ip}_${dst_port}_${proto}"

    if (( now - ${seen_network_connections[$conn_key]:-0} > NETWORK_EVENT_TTL )); then
        proc_name="${PID_COMM_CACHE[$pid]:-unknown}"
        proc_path="${PID_PATH_CACHE[$pid]:-unknown}"

        json_data=$(jq -n \
        --arg pid "$pid" \
        --arg process "$proc_name" \
        --arg path "$proc_path" \
        --arg protocol "$proto" \
        --arg sip "$src_ip" \
        --arg sport "$src_port" \
        --arg dip "$dst_ip" \
        --arg dport "$dst_port" \
        --arg state "$state" \
        '{
            pid:($pid|tonumber),
            process_name:$process,
            process_path:$path,
            protocol:$protocol,
            source_ip:$sip,
            source_port:($sport|tonumber),
            destination_ip:$dip,
            destination_port:($dport|tonumber),
            connection_state:$state
        }')
        log_event "INFO" "NETWORK_MONITOR" "network_connection" "$json_data"
        seen_network_connections[$conn_key]=$now
    fi
done < <(ss -antupH)
}

heartbeat(){
    load=$(awk '{print $1}' /proc/loadavg)
    mem_kb=$(free | awk '/Mem:/ {print $3}')

    hb=$(jq -n \
    --arg load "$load" \
    --arg mem "$mem_kb" \
    '{
        cpu_percent: ($load|tonumber),
        memory_kb: ($mem|tonumber)
    }')
    log_event "INFO" "HEARTBEAT" "heartbeat" "$hb"
}

file_monitor &

last_proc=0; last_net=0; last_login=0; last_hb=0

while true; do
    now=$(date +%s)

    if [[ -f "$POLICIES_FILE" ]]; then
        PROCESS_MONITOR_INTERVAL=$(jq -r '.settings.process_monitor_interval // '"$PROCESS_MONITOR_INTERVAL"'' "$POLICIES_FILE")
        NETWORK_EVENT_TTL=$(jq -r '.settings.network_event_ttl // '"$NETWORK_EVENT_TTL"'' "$POLICIES_FILE")

        NEW_HASH_EXTS=$(jq -r '.settings.hash_extensions // empty' "$POLICIES_FILE")
        if [[ -n "$NEW_HASH_EXTS" ]]; then
            HASH_EXTENSIONS="$NEW_HASH_EXTS"
            IFS=' ' read -r -a HASH_EXT_ARRAY <<< "$HASH_EXTENSIONS"
        fi
    fi

    (( now - last_proc >= PROCESS_MONITOR_INTERVAL )) && { process_monitor; last_proc=$now; }
    (( now - last_net >= NETWORK_MONITOR_INTERVAL )) && { network_monitor; last_net=$now; }
    (( now - last_login >= LOGIN_MONITOR_INTERVAL )) && { login_monitor; last_login=$now; }
    (( now - last_hb >= HEARTBEAT_INTERVAL )) && { heartbeat; last_hb=$now; }
    sleep 1
done
