#!/bin/bash

#################################
# Resolve paths
#################################
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

#################################
# Load config
#################################
CONFIG_FILE="$ROOT_DIR/config/config.conf"
[[ -f "$CONFIG_FILE" ]] || { echo "[ERROR] Missing config."; exit 1; }
source "$CONFIG_FILE"

#################################
# Defaults
#################################
POLICY_FILE="${POLICY_FILE:-storage/policies.json}"
RULES_FILE="${RULES_FILE:-storage/rules.json}"
AGENTS_FILE="${AGENTS_FILE:-storage/agents.json}"
EVENT_LOG="${EVENT_LOG:-logs/events.log}"
ALERT_LOG="${ALERT_LOG:-logs/alerts.log}"
SERVICE_LOGS_DIR="${SERVICE_LOGS_DIR:-services-logs}"

POLICY_PATH="$ROOT_DIR/$POLICY_FILE"
RULES_PATH="$ROOT_DIR/$RULES_FILE"
AGENTS_PATH="$ROOT_DIR/$AGENTS_FILE"

#################################
# Colors
#################################
black='\033[0;30m'
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
white='\033[0;37m'
purple='\033[0;35m'

bold_black='\033[1;30m'
bold_red='\033[1;31m'
bold_green='\033[1;32m'
bold_yellow='\033[1;33m'
bold_blue='\033[1;34m'
bold_cyan='\033[1;36m'
bold_white='\033[1;37m'
bold_purple='\033[1;35m'

neon_yellow='\033[38;5;226m'
neon_purple='\033[38;5;129m'
neon_blue='\033[38;5;45m'
neon_cyan='\033[38;5;51m'
neon_pink='\033[38;5;201m'
neon_green='\033[38;5;118m'
neon_red='\033[38;5;196m'
magenta='\033[38;5;99m'

red="${bold_red}"
green="${bold_green}"
yellow="${bold_yellow}"
blue="${bold_blue}"
cyan="${neon_cyan}"
magenta="${magenta}"
white="${bold_white}"
nc='\033[0m'
reset='\033[0m'
bold='\033[1m'
dim='\033[0;90m'

#################################
# UI Helpers
#################################
draw_box() {
    echo -e "${cyan}======================================${nc}"
    echo -e "${cyan}  $1${nc}"
    echo -e "${cyan}======================================${nc}"
}

section() {
    echo
    echo -e "${neon_yellow}[ $1 ]${nc}"
}

hint() {
    echo -e "${magenta}$1${nc}"
}

HOME='\033[H'
CL='\033[K'
ERASE='\033[2J'
HIDE='\033[?25l'
SHOW='\033[?25h'

#################################
# Helpers
#################################
safe_jq() {
    jq "$1" "$2" 2>/dev/null
}

#################################
# Port Utilities
#################################
port_in_use() {
    local port="$1"

    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 2
    fi

    if ss -ltnp 2>/dev/null | grep -q ":$port "; then
        return 0
    else
        return 1
    fi
}
kill_port() {
    local port="$1"
    pids=$(ss -ltnp 2>/dev/null | grep ":$port " | grep -o 'pid=[0-9]*' | cut -d= -f2)

    if [[ -n "$pids" ]]; then
        echo -e "${neon_red}[ NET ] Port $port used by: $pids${nc}"
        read -rp "Kill them? (y/n): " c
        [[ ! "$c" =~ ^[Yy]$ ]] && return 1

        for pid in $pids; do
            kill -9 "$pid" 2>/dev/null
            echo -e "${green}[ INFO ] Killed port $port (PID: $pid)${nc}"
        done
    fi
    return 0
}

update_config_port() {
    sed -i "s/^$1=.*/$1=$2/" "$CONFIG_FILE"
}

#################################
# Query Engine Wrapper
#################################
run_query() {
    local logfile="$1"
    shift

    if [[ $# -eq 0 ]]; then
        tail -n 20 "$logfile" | jq -C . 2>/dev/null | less -RFX
    else
        bash "$ROOT_DIR/engine/query.sh" "$@" | jq -C . 2>/dev/null | less -RFX
    fi
}

#################################
# Service status
#################################
service_status() {
    local pid_file="$ROOT_DIR/$SERVICE_LOGS_DIR/$1.pid"
    if [[ -f "$pid_file" ]]; then
        pid=$(cat "$pid_file")
        ps -p "$pid" &>/dev/null && echo -e "${neon_green}● RUNNING${nc} (PID: $pid)" && return
    fi
    echo -e "${neon_red}● DOWN${nc}"
}

#################################
# System info
#################################
system_info() {
    uptime_str=$(uptime -p 2>/dev/null || echo "unknown")
    cpu_load=$(awk '{print $1","$2","$3}' /proc/loadavg 2>/dev/null)
    mem=$(free -h 2>/dev/null | awk '/Mem:/ {print $3 "/" $2}')
    disk=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    net=$(cat /proc/net/dev 2>/dev/null | awk '/eth0|ens|wlan/ {rx+=$2; tx+=$10} END {print rx "/" tx}')
    [[ -z "$net" ]] && net="N/A"
    procs=$(ps -e --no-headers 2>/dev/null | wc -l)
    users=$(who 2>/dev/null | wc -l)

    echo -e "${neon_blue}$(date)${nc} ${CL}"
    echo -e "${cyan}System:${nc} $uptime_str ${CL}"
    echo -e "${cyan}CPU Load:${nc} $cpu_load ${CL}"
    echo -e "${cyan}RAM:${nc} $mem ${CL}"
    echo -e "${cyan}Disk:${nc} $disk ${CL}"
    echo -e "${cyan}Network (RX/TX):${nc} $net ${CL}"
    echo -e "${cyan}Processes:${nc} $procs | Users: $users ${CL}"
}

#################################
# Service control
#################################
stop_services() {
    bash "$ROOT_DIR/core/stopservice.sh"
}

restart_services() {
    echo -e "${neon_yellow}[SIEM] Restarting...${nc}"
    stop_services
    sleep 1
    bash "$ROOT_DIR/SIEM.sh"
    exit 0
}

#################################
# Cleanup 
#################################
cleanup() {
    # 1. Show the cursor again
    echo -ne "${SHOW}"
    # 2. Reset colors just in case
    echo -ne "${nc}"
    # 3. Print exit message
    echo
    echo -e  "${neon_yellow}[SIEM] Shutting Down Black Box dashboard.${nc}"
    echo -e  "${neon_yellow}[INFO] The services are still running in the background.${nc}"
    exit 0
}

#################################
# POLICY MENU 
#################################
policy_menu() {
    clear
    echo -ne "${HIDE}"

    while true
    do
        echo -ne "${HOME}"

        draw_box "POLICY MANAGEMENT"

        EDR=$(jq -r '.global.edr_response // false' "$POLICY_PATH" 2>/dev/null || echo false)
        FW=$(jq -r '.global.firewall_enabled // false' "$POLICY_PATH" 2>/dev/null || echo false)

        echo -e "${neon_yellow}[ CURRENT ]${nc}${CL}"
        
        if [[ "$EDR" == "true" ]]; then
            echo -e " EDR      : ${neon_green}ENABLED${nc}${CL}"
        else
            echo -e " EDR      : ${neon_red}DISABLED${nc}${CL}"
        fi

        if [[ "$FW" == "true" ]]; then
            echo -e " Firewall : ${neon_green}ENABLED${nc}${CL}"
        else
            echo -e " Firewall : ${neon_red}DISABLED${nc}${CL}"
        fi

        echo -e "${neon_yellow}[ OPTIONS ]${nc}${CL}"
        echo -e " 1) View Policy      2) Toggle EDR${CL}"
        echo -e " 3) Toggle Firewall  4) Back${CL}"
        
        read -t 0.01 -n 1000 discard 2>/dev/null

        echo -ne "${CL}\n policy> "

        read -t 1 -n 1 -s pc

        case $pc in
            1)
                echo -ne "${SHOW}"
                clear
                draw_box "FULL POLICY JSON"
                jq -C . "$POLICY_PATH"
                echo -e "\n${neon_yellow}Press [Enter] to return...${nc}"
                read -r
                clear
                echo -ne "${HIDE}"
            ;;
            2)
                jq '.global.edr_response |= not' "$POLICY_PATH" > tmp && mv tmp "$POLICY_PATH"
            ;;
            3)
                jq '.global.firewall_enabled |= not' "$POLICY_PATH" > tmp && mv tmp "$POLICY_PATH"
            ;;
            4|q) 
                clear
                return 
            ;;
        esac
    done
}

#################################
# ADVANCED MENU 
#################################

advanced_menu() {
    echo -ne "${HIDE}"

    while true
    do
        read -t 0.01 -n 1000 discard 2>/dev/null

        ADV_FRAME=$(
            clear
            draw_box "ADVANCED CONFIGURATION"
            system_info

            echo -e "${neon_yellow}[ NETWORK STATUS ]${nc}"
            echo -e " Ingest Port : ${neon_cyan}$LISTEN_PORT${nc}"
            echo -e " Web Port    : ${neon_cyan}$WEB_PORT${nc}"

            echo 
            echo -e "${neon_yellow}[ SERVICE MONITOR ]${nc}"
            echo -e " Ingest Process : $(service_status ingest)"
            echo -e " Parser Process : $(service_status parser)"
            echo -e " Web Process    : $(service_status web)"
             
            echo 
            echo -e "${neon_yellow}[ CONTROL OPTIONS ]${nc}"
            echo -e " 1) Restart Services    2) Stop Services"
            echo -e " 3) Change Ingest Port  4) Change Web Port"
            
            echo -e "\n${neon_yellow}[ MAINTENANCE ]${nc}"
            echo -e " 5) Re-Pack EDR Agent   6) Purge SIEM Logs"

            echo -e "\n${neon_yellow}[ SYSTEM ]${nc}"
            echo -e " 7) Full Shutdown       8) Back to Main"

            echo 
            echo -ne "adv> "
        )

        echo -ne "$ADV_FRAME"

        read -t 1 -n 1 -s adv

        case $adv in
            1) 
                echo -ne "${SHOW}"
                echo -e "\n${neon_yellow}[ AUTH ]${nc} Restart services? (y/n)" 
                read -rp " > " c
                [[ "$c" =~ ^[Yy]$ ]] && restart_services
                echo -ne "${HIDE}"
            ;;
            
            2) 
                echo -ne "${SHOW}"
                echo -e "\n${neon_red}[ SEC  ]${nc} Stop all services? (y/n)"
                read -rp " > " c
                if [[ "$c" =~ ^[Yy]$ ]]; then
                    stop_services 
                    sleep 1
                fi
                echo -ne "${HIDE}"
            ;;

            3|4)
                local label="Ingest"
                local current_p="$LISTEN_PORT"
                [[ "$adv" == "4" ]] && label="Web" && current_p="$WEB_PORT"

                echo -ne "${SHOW}"
                echo -e "\n${neon_blue}[ NET  ]${nc} Changing $label Port (Current: $current_p)"
                echo -e "${neon_cyan}[ HINT ]${nc} Type 'q' or press Enter to cancel."
                read -rp " New Port > " p
                
                if [[ -z "$p" || "$p" == "q" ]]; then
                    echo -e "${neon_yellow}[ CANCEL ]${nc} No changes made."
                    sleep 1
                else
                    port_in_use "$p"
                    res=$?
                    if [[ $res -eq 2 ]]; then
                        echo -e "${neon_red}[ ERR! ]${nc} Invalid port number!"
                        sleep 1
                    elif [[ $res -eq 0 ]]; then
                        echo -e "${neon_red}[ ERR! ]${nc} Port $p is busy!"
                        sleep 1
                    else
                        kill_port "$current_p"
                        if [[ "$adv" == "3" ]]; then
                            update_config_port LISTEN_PORT "$p"
                            LISTEN_PORT="$p"
                        else
                            update_config_port WEB_PORT "$p"
                            WEB_PORT="$p"
                        fi
                        echo -e "${neon_green}[ OK ]${nc} Port updated to $p."
                        sleep 1
                    fi
                fi
                echo -ne "${HIDE}"
            ;;

            5)
                echo -ne "${SHOW}"
                echo -e "\n${neon_blue}[ MAINT ]${nc} Re-packaging EDR agent..."
                bash "$ROOT_DIR/core/prep-deployment.sh"
                if [[ $? -ne 0 ]]; then
                    echo -e "${neon_red}[ ERR! ]${nc} Failed to create EDR package."
                else
                    echo -e "${neon_green}[ OK ]${nc} Agent package rebuilt at $ROOT_DIR/storage/agent_package.tar.gz"
                fi

                sleep 1.5
                echo -ne "${HIDE}"
            ;;

            6) # PURGE LOGS
                echo -ne "${SHOW}"
                echo -e "\n${neon_red}[ WARN ]${nc} Permanent deletion: Wipe all SIEM telemetry? (y/n)"
                read -rp " > " c
                if [[ "$c" =~ ^[Yy]$ ]]; then
                    > "$ROOT_DIR/$EVENT_LOG"
                    > "$ROOT_DIR/$ALERT_LOG"
                    # Remove the processed helper file if it exists
                    rm -f "$ROOT_DIR/${EVENT_LOG}.processed" 2>/dev/null
                    echo -e "${neon_green}[ OK ]${nc} All logs truncated."
                    sleep 1
                fi
                echo -ne "${HIDE}"
            ;;

            7)
                echo -ne "${SHOW}"
                echo -e "\n${neon_red}[ SEC  ]${nc} Full Shutdown? (y/n)"
                read -rp " > " confirmation
                if [[ "$confirmation" =~ ^[Yy]$ ]]; then
                    stop_services
                    sleep 1
                    cleanup
                fi
                echo -ne "${HIDE}"
            ;;

            8|q) 
                clear
                return 
            ;;
        esac
    done
}
#################################
# MAIN LOOP
#################################
trap cleanup INT TERM

echo -ne "${HIDE}"

while true; do
    FRAME=$(
        clear
        draw_box "BLACK BOX SIEM"
        system_info

        section "STATUS"
        echo -e " Ingest : ${neon_cyan}$LISTEN_PORT${nc}"
        echo -e " Web    : ${neon_cyan}$WEB_PORT${nc}"

        section "SERVICES"
        echo -e " Ingest : $(service_status ingest)  "
        echo -e " Parser : $(service_status parser)  "
        echo -e " Web    : $(service_status web)"

        section "ACTIONS"
        echo -e "${bold} 1)${nc}Alerts   ${bold} 2)${nc}Events   ${bold} 3)${nc}Policies"
        echo -e "${bold} 4)${nc}Live     ${bold} 5)${nc}Advanced ${bold} 6)${nc}Agents"
        echo -e "${bold} 7)${nc}Exit"
        echo 
    )
    
    echo -ne "$FRAME"
    echo -ne "\n${bold}siem>${nc} "

    read -t 1 -n 1 -s choice

    case $choice in
        1)
            echo -ne "${SHOW}"; clear
            draw_box "ALERTS SEARCH"
            read -rp "Query > " q
            [[ "$q" == "q" || "$q" == "exit" ]] && { clear; echo -ne "${HIDE}"; continue; }
            clear
            if [[ -z "$q" ]]; then
                tail -n 20 "$ROOT_DIR/$ALERT_LOG" | jq -C . 2>/dev/null | less -RFX
            else
                bash "$ROOT_DIR/engine/query.sh" "$q" | jq -C . 2>/dev/null | less -RFX
            fi
            echo -e "\n${neon_cyan}--- Press Enter to return ---${nc}"
            read -r; clear; echo -ne "${HIDE}"
            ;;
        2)
            trend=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
            chars=(" " "▂" "▃" "▄" "▅" "▆" "▇" "█")
            LAST_COUNT=$(wc -l < "$ROOT_DIR/$EVENT_LOG" 2>/dev/null || echo 0)
            unset QUERY RES_COUNT PREVIEW_DATA
            
            while true; do
                CURRENT_TOTAL=$(wc -l < "$ROOT_DIR/$EVENT_LOG" 2>/dev/null || echo 0)
                NEW_LOGS=$(( CURRENT_TOTAL - LAST_COUNT ))
                [[ $NEW_LOGS -lt 0 ]] && NEW_LOGS=0 
                trend=("${trend[@]:1}" "$NEW_LOGS")
                
                sparkline=""
                for val in "${trend[@]}"; do
                    idx=$(( val > 7 ? 7 : val ))
                    if [ "$val" -eq 0 ]; then sparkline+="${blue}${chars[0]}${nc}"
                    elif [ "$val" -lt 3 ]; then sparkline+="${neon_green}${chars[$idx]}${nc}"
                    else sparkline+="${neon_red}${chars[$idx]}${nc}"; fi
                done

                [[ -n "$QUERY" && -s "/tmp/siem_res" ]] && SOURCE_FILE="/tmp/siem_res" || SOURCE_FILE="$ROOT_DIR/$EVENT_LOG"


                if [[ "$CURRENT_TOTAL" -ne "$LAST_COUNT" || -z "$PREVIEW_DATA" ]]; then
                    RECENT_BUFFER=$(tail -n 100 "$SOURCE_FILE" 2>/dev/null)
                    PREVIEW_DATA=$(echo "$RECENT_BUFFER" | tail -n 10 | jq -r -c '
                        .timestamp[11:19] as $ts | 
                        (.level | ascii_upcase | .[0:4]) as $lvl |
                        (.module | .[0:8]) as $mod | 
                        (.event_type | .[0:15]) as $et |
                        ((.data.process_name // .data.file_path // .data.destination_ip // .data.action // "system") | .[0:27]) as $obj |
                        "\($ts)|\($lvl)|\($mod)|\($et)|\($obj)"' 2>/dev/null)
                    LAST_COUNT=$CURRENT_TOTAL
                fi

                EVENT_FRAME=$(
                    clear
                    echo -e "${neon_cyan}============================================================================${nc}"
                    echo -e " [ ${white}SEARCH: ${QUERY:-*}${neon_cyan} ]  RESULTS: ${white}${RES_COUNT:-$CURRENT_TOTAL}${neon_cyan}  |  SOURCE: ${white}${SOURCE_FILE##*/}${neon_cyan} "
                    echo -e "${neon_cyan}============================================================================${nc}"
                    echo -e " VOLUME: ${white}${CURRENT_TOTAL}${nc} | TICK: ${neon_green}+${NEW_LOGS}${nc} | TREND: [ ${sparkline} ] "
                    
                    echo -e "\n${bold} [ RECENT PREVIEW (Last 10) ]${nc}"
                    echo -e "    TIME    | LVL  | MODULE     |   EVENT TYPE     |    OBJECT/DATA "
                    echo -e "  --------------------------------------------------------------------------"

                    if [[ -z "$PREVIEW_DATA" ]]; then
                        echo -e "  (No results matching query)"
                    else
                        echo "$PREVIEW_DATA" | awk -F'|' '{
                          printf "  %-9s | %-4s |  %-7s  | %-16s | %-18s\n", $1, $2, $3, $4, $5
                        }'
                    fi
                    echo -ne "\n ${white}Hotkeys: [s] Search | [c] Clear | [p] FULL Field List | [q] Quit${nc} \n"
                )
                echo -ne "$EVENT_FRAME"
                echo -ne " ${bold}siem(events)>${nc} "
                
                if read -t 0.8 -n 1 -s char; then
                    case "$char" in
                        s|S)
                            echo -ne "${SHOW}"; echo -ne "\r${CL}${neon_yellow}Query > ${nc}"; read -r INPUT_QUERY; echo -ne "${HIDE}"
                            if [[ -n "$INPUT_QUERY" ]]; then
                                QUERY="$INPUT_QUERY"
                                bash "$ROOT_DIR/engine/query.sh" "$QUERY" > /tmp/siem_res
                                RES_COUNT=$(wc -l < /tmp/siem_res)
                                clear; jq -C . /tmp/siem_res | less -R
                            fi
                            ;;
                        c|C) unset QUERY RES_COUNT; rm -f /tmp/siem_res 2>/dev/null; PREVIEW_DATA="" ;;
                        p|P)
                            clear
                            if [[ -n "$QUERY" && -s "/tmp/siem_res" ]]; then
                                TARGET="/tmp/siem_res"
                                TITLE="FILTER: $QUERY"
                            else
                                TARGET="$ROOT_DIR/$EVENT_LOG"
                                TITLE="GLOBAL LOGS"
                            fi
                            echo -e "${neon_yellow}Analyzing fields for: ${white}$TITLE${neon_yellow}... Please wait.${nc}"
                            RAW_DATA=$(cat "$TARGET" 2>/dev/null | jq -r 'paths(scalars) | join(".")' 2>/dev/null | sort | uniq -c | sort -nr)
                            if [[ -z "$RAW_DATA" ]]; then
                                echo -e "${neon_red}No data to analyze.${nc}"; sleep 1; continue
                            fi
                            TABLE_HEADER="${neon_blue}╔══════════════════════════════════════════════════════════════════════╦═══════╗${nc}\n"
                            TABLE_HEADER+="${neon_blue}║${nc}  ${neon_cyan}FIELD PATH (JSON Key Hierarchy)${nc}                                    ${neon_blue}║${nc} ${neon_cyan}COUNT${nc} ${neon_blue}║${nc}\n"
                            TABLE_HEADER+="${neon_blue}╠══════════════════════════════════════════════════════════════════════╬═══════╣${nc}"
                            ROWS=$(echo "$RAW_DATA" | awk -v cyan="$neon_cyan" -v green="$neon_green" -v yellow="$neon_yellow" -v red="$neon_red" -v blue="$neon_blue" -v dim="\033[0;90m" -v nc="$nc" '
                            {
                                count=$1; path=$2;
                                c_color = green; if(count > 100) c_color = yellow; if(count > 500) c_color = red;
                                if(length(path) > 60) path = substr(path, 1, 57) "...";
                                padlen = 66 - length(path);
                                padding = ""; for(i=0; i<padlen; i++) padding = padding ".";
                                printf "%s║%s  %s%s %s%s%s ║ %s%5d %s║%s\n", blue, nc, cyan, path, dim, padding, blue, c_color, count, blue, nc;
                            }')
                            FOOTER="${neon_blue}╚══════════════════════════════════════════════════════════════════════╩═══════╝${nc}"
                            echo -e "${magenta}FIELD DISCOVERY: ${white}$TITLE${nc}\n$TABLE_HEADER\n$ROWS\n$FOOTER" | less -RX
                            clear
                            ;;
                        q|Q) break ;; 
                    esac
                fi
            done
            clear
            ;;
        3) echo -ne "${SHOW}"; policy_menu; clear; echo -ne "${HIDE}" ;;
        4)
            clear
            echo -ne "${SHOW}"
            draw_box "LIVE CRITICAL ALERTS"
            hint " [ Press Ctrl+C to Return to Menu ] "
            echo

            tail -F "$ROOT_DIR/$ALERT_LOG" | jq --unbuffered -C . 2>/dev/null &
            TAIL_PID=$!

            trap 'kill $TAIL_PID 2>/dev/null; break' INT

            while ps -p $TAIL_PID > /dev/null; do
                sleep 0.5
            done

            trap cleanup INT TERM
            
            clear
            echo -ne "${HIDE}"
            ;;
        5) echo -ne "${SHOW}"; advanced_menu; clear; echo -ne "${HIDE}" ;;
        
        6)
        bash "$ROOT_DIR/cli/agent-mgmt.sh"
        clear
         ;;
        
        7|q) cleanup ;;
    esac
done
