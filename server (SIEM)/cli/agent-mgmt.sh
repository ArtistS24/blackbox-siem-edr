#!/bin/bash

#################################
# Resolve paths
#################################
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
CONFIG_FILE="$ROOT_DIR/config/config.conf"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

MY_IP=$(hostname -I | awk '{print $1}')
PROTECTED_PORTS=("$LISTEN_PORT" "$WEB_PORT" "22")

red='\033[1;31m'; green='\033[1;32m'; yellow='\033[1;33m'; blue='\033[1;34m'
cyan='\033[1;36m'; white='\033[1;37m'; magenta='\033[1;35m'; nc='\033[0m'
bold='\033[1m'; dim='\033[0;90m'; b_red='\033[41;37m'

HOME='\033[H'; CL='\033[K'; HIDE='\033[?25l'; SHOW='\033[?25h'

AGENTS_PATH="$ROOT_DIR/$AGENTS_FILE"
RULES_PATH="$ROOT_DIR/$RULES_FILE"
POLICY_PATH="$ROOT_DIR/$POLICY_FILE"
FW_PATH="$ROOT_DIR/storage/firewall.json"
INSTALLER_WEB_PATH="EDR/blackbox-installer.sh"

#################################
# UI HELPERS
#################################
draw_box() {
    echo -e "${cyan}============================================================================${nc}"
    echo -e "  ${bold}$1${nc}"
    echo -e "${cyan}============================================================================${nc}"
}

draw_rule_card() {
    local id="$1" sev="$2" name="$3" match="$4" val="$5" mitre="$6"
    case "$sev" in
        CRITICAL) s_col="${red}"; head="[!!!] CRITICAL DETECTION" ;;
        HIGH)     s_col="${yellow}"; head="[!!]  HIGH SEVERITY" ;;
        MEDIUM)   s_col="${blue}"; head="[!]   MEDIUM ALERT" ;;
        *)        s_col="${green}"; head="[i]   LOW/INFO" ;;
    esac
    echo -e "  ${s_col}┌── [ ID: $id ] ─ $head ──────────────────────────┐${nc}"
    printf "  ${s_col}│${nc}  ${bold}%-14s:${nc} %-48s ${s_col}│${nc}\n" "RULE NAME" "${name:0:45}"
    printf "  ${s_col}│${nc}  ${bold}%-14s:${nc} %-15s = %-30s ${s_col}│${nc}\n" "MATCH" "$match" "${val:0:28}"
    printf "  ${s_col}│${nc}  ${bold}%-14s:${nc} %-48s ${s_col}│${nc}\n" "MITRE ID" "$mitre"
    echo -e "  ${s_col}└──────────────────────────────────────────────────────────────────┘${nc}"
}

draw_fw_card() {
    local id="$1" action="$2" dir="$3" target="$4" proto="$5"
    [[ "$action" == "DROP" ]] && c_col="${red}" || c_col="${green}"
    [[ "$dir" == "in" ]] && dir_txt="INBOUND (Ingress)" || dir_txt="OUTBOUND (Egress)"
    echo -e "  ${c_col}┌── [ FW-ID: $id ] ─ $action ──────────────────────────────────────┐${nc}"
    printf "  ${c_col}│${nc}  ${bold}%-14s:${nc} %-48s ${c_col}│${nc}\n" "DIRECTION" "$dir_txt"
    printf "  ${c_col}│${nc}  ${bold}%-14s:${nc} %-48s ${c_col}│${nc}\n" "TARGET" "$target"
    printf "  ${c_col}│${nc}  ${bold}%-14s:${nc} %-48s ${c_col}│${nc}\n" "PROTOCOL" "${proto^^}"
    echo -e "  ${c_col}└──────────────────────────────────────────────────────────────────┘${nc}"
}

#################################
# VALIDATION & ESCAPE LOGIC
#################################
safe_read() {
    local prompt_msg="$1"
    local input_val
    echo -ne " ${yellow}>> $prompt_msg (or 'q' to cancel):${nc} "
    read -r input_val
    if [[ "$input_val" == "q" || "$input_val" == "quit" ]]; then return 1; fi
    REPLY="$input_val"; return 0
}

validate_ip() {
    if [[ "$1" == "$MY_IP" || "$1" == "127.0.0.1" ]]; then
        echo -e "\n${b_red} SECURITY ALERT ${nc} Access denied: You cannot block the SIEM IP."
        return 1
    fi
    [[ ! $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && { echo -e "\n${red}[ERR] Invalid IP.${nc}"; return 1; }
    return 0
}

validate_port() {
    for p in "${PROTECTED_PORTS[@]}"; do
        [[ "$1" == "$p" ]] && { echo -e "\n${b_red} SECURITY ALERT ${nc} Port $1 is reserved for SIEM."; return 1; }
    done
    [[ ! "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 65535 ] && { echo -e "\n${red}[ERR] Invalid Port.${nc}"; return 1; }
    return 0
}

#################################
# ENHANCED CHEAT SHEETS
#################################
show_rule_cheat_sheet() {
    local page=1
    while true; do
        clear; draw_box "EDR DETECTION & HUNTING GUIDE"
        if [[ $page -eq 1 ]]; then
            echo -e " ${magenta}MATCHING STRATEGIES${nc}"
            echo -e " • ${bold}process_name${nc} : Matches the 'comm' field of a process."
            echo -e "   ${dim}Use this for binary-specific blocking (e.g. 'nmap', 'ncat', 'python3').${nc}"
            echo -e " • ${bold}command_line${nc} : Matches substrings within the full execution string."
            echo -e "   ${dim}Use this for behavior (e.g. 'base64 --decode', 'memdump', '/etc/shadow').${nc}"
            echo -e "\n ${magenta}SEVERITY GUIDELINES${nc}"
            echo -e " - ${red}CRITICAL${nc} : Immediate malicious action. Triggers ${bold}Auto-Kill${nc} on EDR."
            echo -e " - ${yellow}HIGH${nc}     : Significant anomaly (e.g. sensitive file access)."
            echo -e " - ${blue}MEDIUM${nc}   : Suspicious tool usage in non-standard context."
            echo -e " - ${green}LOW${nc}      : Behavioral tracking for historical correlation."
        else
            echo -e " ${magenta}PRACTICAL EXAMPLES${nc}"
            echo -e " ${blue}[ Reverse Shell ]${nc} Type: command_line | Value: /bin/bash -i"
            echo -e " ${blue}[ Persistence ]${nc}   Type: command_line | Value: /var/spool/cron"
            echo -e " ${blue}[ Lateral Mov ]${nc}   Type: process_name | Value: scp"
            echo -e " ${blue}[ Recon ]${nc}         Type: process_name | Value: whoami"
            echo -e "\n ${yellow}How to deploy:${nc} Add the rule here, then wait 60s for agent sync."
        fi
        echo -ne "\n [1/2] Pages | [q] Back: "; read -n 1 -s k
        [[ "$k" == "q" ]] && break; page=$k
    done
}

show_fw_cheat_sheet() {
    clear; draw_box "NETWORK DEFENSE & FIREWALL GUIDE"
    echo -e " ${magenta}TRAFFIC DIRECTIONS${nc}"
    echo -e " • ${bold}IN (Inbound)${nc}  : World -> Machine. Stop external attackers here."
    echo -e " • ${bold}OUT (Outbound)${nc}: Machine -> World. Stop data leaks & C2 callbacks here."
    echo -e "\n ${magenta}COMMON MALICIOUS TARGETS${nc}"
    echo -e " - ${bold}Port 4444${nc} : Standard Metasploit/Payload port. Block OUTBOUND."
    echo -e " - ${bold}Port 6667${nc} : Common IRC Botnet C2. Block OUTBOUND."
    echo -e " - ${bold}Port 80/443${nc}: Block specific malicious IPs INBOUND."
    echo -e "\n ${red}SAFEGUARD:${nc} The system automatically whitelists your SIEM IP ($MY_IP)"
    echo -e "            and Ingestion Ports ($LISTEN_PORT, $WEB_PORT)."
    echo -e "\n Press any key to return..."; read -n 1 -s
}

show_engine_cheat_sheet() {
    local p=1
    while true; do
        clear; draw_box "ENGINE TUNING & PERFORMANCE IMPACT"
        if [[ $p -eq 1 ]]; then
            echo -e " ${magenta}PAGE 1: FILE MONITORING${nc}"
            echo -e " • ${bold}Watch Dirs${nc}    : Folders scanned for Create/Modify/Delete."
            echo -e " • ${bold}Watch Dirs${nc}    : Folders scanned for Create/Modify/Delete."
            echo -e " • ${bold}Scan Int${nc}      : Delay between folder scans. Lower = More CPU usage."
            echo -e " • ${bold}File Event TTL${nc}: Ignores multiple rapid changes to one file."
            echo -e " • ${bold}Max Hash Size${nc} : Prevents the EDR from lagging on huge 500MB+ files."
            echo -e " • ${bold}Hash Exts${nc}     : Limits hashing to dangerous types (.sh, .elf, .exe)."
        else
            echo -e " ${magenta}PAGE 2: PROCESS & NETWORK${nc}"
            echo -e " • ${bold}Proc Interval${nc}: Frequency of the process tree scan (Standard: 2s)."
            echo -e " • ${bold}Proc Hash TTL${nc}: How long a process binary hash is remembered."
            echo -e " • ${bold}Net Event TTL${nc}: Prevents logging the same open connection twice."
            echo -e "\n ${yellow}PERFORMANCE TIP:${nc} Increasing TTLs (Time-To-Live) significantly"
            echo -e "                  reduces agent CPU and SIEM log storage noise."
        fi
        echo -ne "\n [1/2] Pages | [q] Back: "; read -n 1 -s k
        [[ "$k" == "q" ]] && break; p=$k
    done
}

#################################
# 1. LIVE HUD MONITOR
#################################
monitor_agents() {
    clear; echo -ne "${HIDE}"
    while true; do
        FRAME=$(
            echo -ne "${HOME}"
            draw_box "ENDPOINT TELEMETRY HUB"
            printf "  ${bold}%-15s | %-8s | %-12s | %-6s | %-8s | %-12s${nc}\n" "HOSTNAME" "ID" "STATUS" "CPU" "MEM" "LAST PULSE"
            echo -e "  --------------------------------------------------------------------------"
            if [[ ! -f "$AGENTS_PATH" ]]; then echo -e "\n  ${red}[!] agents.json missing${nc}"
            else
                now=$(date -u +%s)
                jq -r '.agents[] | "\(.hostname)|\(.agent_id)|\(.last_seen)|\(.cpu_percent // 0)|\(.memory_kb // 0)"' "$AGENTS_PATH" 2>/dev/null | while IFS='|' read -r host id last cpu mem; do
                    last_ts=$(date -u -d "$last" +%s 2>/dev/null || echo 0)
                    diff=$(( now - last_ts ))
                    [[ $diff -le 45 ]] && status="${green}● HEALTHY${nc}" || status="${red}● OFFLINE${nc}"
                    mem_mb=$(( mem / 1024 ))
                    printf "  %-15s | %-8s | %-21s | %-5s%% | %-6s MB | %ss ago\n" "$host" "$id" "$status" "$cpu" "$mem_mb" "$diff"
                done
            fi
            echo -e "\n ${dim}[q] to return to Agent Menu${nc}"
        )
        echo -ne "$FRAME"
        read -t 2 -n 1 -s key
        [[ "$key" == "q" || "$key" == "Q" ]] && break
    done
    echo -ne "${SHOW}"
}

enroll_agent() {
    bash "$ROOT_DIR/core/prep-deployment.sh" 1>/dev/null 2>&1
    clear; draw_box "ENROLL NEW ENDPOINT"
    URL="http://$MY_IP:$WEB_PORT"
    echo -e "\n ${yellow}RUN ON REMOTE MACHINE (AS ROOT):${nc}"
    echo -e " --------------------------------------------------------------------------"
    echo -e " ${white}${bold}curl -s $URL/$INSTALLER_WEB_PATH | sudo bash -s -- $URL${nc}"
    echo -e " --------------------------------------------------------------------------"
    echo ""
    read -rp " Press [Enter] to return..."
}

#################################
# 2. DETECTION RULES
#################################
manage_rules() {
    local PAGE=0; local LIMIT=5 
    while true; do
        clear; draw_box "EDR DETECTION RULES CONSOLE"
        local RAW_DATA=$(jq -c '.process_rules' "$RULES_PATH" 2>/dev/null)
        local TOTAL=$(echo "$RAW_DATA" | jq 'length')
        echo -e "  Active Rules: $TOTAL | Page: $((PAGE + 1))\n"
        local START=$((PAGE * LIMIT))
        local ITEMS=$(echo "$RAW_DATA" | jq -c "to_entries | .[$START:$((START + LIMIT))]")
        
        if [[ "$TOTAL" -eq 0 ]]; then echo -e "\n             ${dim}( No rules defined )${nc}\n"
        else
            echo "$ITEMS" | jq -r '.[] | "\(.key)|\(.value.severity)|\(.value.name)|\(.value.match)|\(.value.value)|\(.value.mitre)"' | while IFS='|' read -r id sev name match val mitre; do
                draw_rule_card "$id" "$sev" "$name" "$match" "$val" "$mitre"; echo ""
            done
        fi
        echo -e "--------------------------------------------------------------------------"
        echo -e " ${bold}[a]${nc} Add   ${bold}[d]${nc} Delete   ${bold}[n/p]${nc} Page   ${bold}[h]${nc} Help   ${bold}[q]${nc} Back"
        echo -ne "\n rule-console> "; read -n 1 cmd; echo
        case $cmd in
            h|H) show_rule_cheat_sheet ;;
            a|A) echo -ne "${SHOW}\n"
                safe_read "Rule Name" || continue; rname="$REPLY"
                safe_read "Match Type (1:name, 2:cmd)" || continue; [[ "$REPLY" == "1" ]] && mtype="process_name" || mtype="command_line"
                safe_read "Value to match" || continue; rval="$REPLY"
                safe_read "Severity (LOW/MEDIUM/HIGH/CRITICAL)" || continue; rsev="$REPLY"
                safe_read "MITRE ID" || continue; rmitre="$REPLY"
                jq --arg name "$rname" --arg match "$mtype" --arg val "$rval" --arg mitre "$rmitre" --arg sev "$rsev" \
                '.process_rules += [{name: $name, match: $match, value: $val, mitre: $mitre, severity: $sev}]' "$RULES_PATH" > /tmp/r.tmp && mv /tmp/r.tmp "$RULES_PATH"
                echo -ne "${HIDE}" ;;
            d|D) echo -ne "\n Enter ID to delete: "; read -r rid
                [[ -n "$rid" && "$rid" != "q" ]] && jq "del(.process_rules[$rid])" "$RULES_PATH" > /tmp/r.tmp && mv /tmp/r.tmp "$RULES_PATH" ;;
            n|N) (( (PAGE + 1) * LIMIT < TOTAL )) && ((PAGE++)) ;;
            p|P) [[ $PAGE -gt 0 ]] && ((PAGE--)) ;;
            q|Q) return ;;
        esac
    done
}

#################################
# 3. FIREWALL CONSOLE
#################################
manage_firewall() {
    local PAGE=0; local LIMIT=5
    while true; do
        clear; draw_box "NETWORK FIREWALL CONSOLE"
        [[ ! -f "$FW_PATH" ]] && echo '{"default_input":"ACCEPT","default_output":"ACCEPT","rules":[]}' > "$FW_PATH"
        local RAW_DATA=$(jq -c '.rules' "$FW_PATH" 2>/dev/null)
        local TOTAL=$(echo "$RAW_DATA" | jq 'length')
        echo -e "  Active Blocks: $TOTAL | Page: $((PAGE + 1))\n"
        local START=$((PAGE * LIMIT))
        local ITEMS=$(echo "$RAW_DATA" | jq -c "to_entries | .[$START:$((START + LIMIT))]")
        
        if [[ "$TOTAL" -eq 0 ]]; then echo -e "\n             ${dim}( No firewall rules )${nc}\n"
        else
            echo "$ITEMS" | jq -r '.[] | "\(.key)|\(.value.action)|\(.value.direction)|\(.value.ip // .value.port)|\(.value.protocol)"' | while IFS='|' read -r id act dir target proto; do
                draw_fw_card "$id" "$act" "$dir" "$target" "$proto"; echo ""
            done
        fi
        echo -e "--------------------------------------------------------------------------"
        echo -e " ${bold}[a]${nc} Block IP   ${bold}[o]${nc} Block Port   ${bold}[d]${nc} Delete   ${bold}[n/p]${nc} Page   ${bold}[h]${nc} Help   ${bold}[q]${nc} Back"
        echo -ne "\n fw-console> "; read -n 1 cmd; echo
        case $cmd in
            h|H) show_fw_cheat_sheet ;;
            a|A) echo -ne "${SHOW}\n"
                safe_read "IP Address" || continue; fip="$REPLY"; validate_ip "$fip" || { sleep 3; continue; }
                safe_read "Direction (in/out)" || continue; fdir="$REPLY"
                jq --arg ip "$fip" --arg dir "$fdir" '.rules += [{direction: $dir, action: "DROP", ip: $ip, protocol: "tcp"}]' "$FW_PATH" > /tmp/f.tmp && mv /tmp/f.tmp "$FW_PATH"
                echo -ne "${HIDE}" ;;
            o|O) echo -ne "${SHOW}\n"
                safe_read "Port Number" || continue; fport="$REPLY"; validate_port "$fport" || { sleep 3; continue; }
                safe_read "Direction (in/out)" || continue; fdir="$REPLY"
                jq --arg port "$fport" --arg dir "$fdir" '.rules += [{direction: $dir, action: "DROP", port: $port, protocol: "tcp"}]' "$FW_PATH" > /tmp/f.tmp && mv /tmp/f.tmp "$FW_PATH"
                echo -ne "${HIDE}" ;;
            d|D) echo -ne "\n ID to remove: "; read -r fid; [[ -n "$fid" && "$fid" != "q" ]] && jq "del(.rules[$fid])" "$FW_PATH" > /tmp/f.tmp && mv /tmp/f.tmp "$FW_PATH" ;;
            n|N) (( (PAGE + 1) * LIMIT < TOTAL )) && ((PAGE++)) ;;
            p|P) [[ $PAGE -gt 0 ]] && ((PAGE--)) ;;
            q|Q) return ;;
        esac
    done
}

#################################
# ENGINE SETTINGS
#################################
edit_list_param() {
    local label="$1" key="$2"; local cur=$(jq -r ".settings.$key" "$POLICY_PATH")
    clear; draw_box "EDIT: $label"
    echo -e " Current: ${white}$cur${nc}\n --------------------------------------------------------------------------"
    echo -e " ${bold}[a]${nc} Append    ${bold}[r]${nc} Remove    ${bold}[s]${nc} Overwrite    ${bold}[q]${nc} Cancel"
    echo -ne "\n action> "; read -n 1 act; echo
    case $act in
        a|A) safe_read "Add item(s)" || return; new=$(echo "$cur $REPLY" | xargs) ;;
        r|R) safe_read "Remove item" || return; new=$(echo "$cur" | sed -e "s/\b$REPLY\b//g" | xargs) ;;
        s|S) safe_read "Set value" || return; new="$REPLY" ;;
        *) return ;;
    esac
    [[ -n "${new:-}" ]] && jq --arg v "$new" ".settings.$key = \$v" "$POLICY_PATH" > t.tmp && mv t.tmp "$POLICY_PATH"
}

edit_num_param() {
    local label="$1" key="$2" suffix="$3"; local cur=$(jq -r ".settings.$key" "$POLICY_PATH")
    clear; draw_box "EDIT: $label"
    echo -e " Current: ${white}${cur}${suffix}${nc}\n --------------------------------------------------------------------------"
    safe_read "New numeric value" || return
    [[ "$REPLY" =~ ^[0-9.]+$ ]] && jq --arg v "$REPLY" ".settings.$key = (\$v|tonumber)" "$POLICY_PATH" > t.tmp && mv t.tmp "$POLICY_PATH"
}

manage_settings() {
    while true; do
        clear; draw_box "GLOBAL ENGINE CONFIGURATION"
        local DIRS=$(jq -r '.settings.watch_dirs' "$POLICY_PATH"); local F_INT=$(jq -r '.settings.file_monitor_interval' "$POLICY_PATH")
        local H_MAX=$(jq -r '.settings.max_hash_size_mb' "$POLICY_PATH"); local EXTS=$(jq -r '.settings.hash_extensions' "$POLICY_PATH")
        local P_INT=$(jq -r '.settings.process_monitor_interval' "$POLICY_PATH"); local N_TTL=$(jq -r '.settings.network_event_ttl' "$POLICY_PATH")
        local FE_TTL=$(jq -r '.settings.file_event_ttl' "$POLICY_PATH"); local FH_TTL=$(jq -r '.settings.file_hash_ttl' "$POLICY_PATH")
        local PH_TTL=$(jq -r '.settings.process_hash_ttl' "$POLICY_PATH")

        echo -ne "\n ${magenta}[ FILE SYSTEM ]${nc}"
        echo -e "  1) Watch Dirs: ${dim}$DIRS${nc}"
        echo -e "  2) Scan Int:   ${dim}${F_INT}s${nc}"
        echo -e "  3) Event TTL:  ${dim}${FE_TTL}s${nc}"
        echo -ne "\n ${magenta}[ HASHING & PERFORMANCE ]${nc}"
        echo -e "  4) Hash Exts:  ${dim}$EXTS${nc}"
        echo -e "  5) Max Size:   ${dim}${H_MAX} MB${nc}"
        echo -e "  6) Cache TTL:  ${dim}${FH_TTL}s${nc}"
        echo -ne "\n ${magenta}[ PROCESS & NETWORK ]${nc}"
        echo -e "  7) Proc Scan:  ${dim}${P_INT}s${nc}"
        echo -e "  8) Proc TTL:   ${dim}${PH_TTL}s${nc}"
        echo -e "  9) Net TTL:    ${dim}${N_TTL}s${nc}"
        
        echo -ne "\n [1-9] Edit | [h] Help | [q] Back: "; read -n 1 sel; echo
        case $sel in
            h|H) show_engine_cheat_sheet ;;
            1) edit_list_param "Watch Dirs" "watch_dirs" ;; 2) edit_num_param "Scan Interval" "file_monitor_interval" "s" ;;
            3) edit_num_param "File Event TTL" "file_event_ttl" "s" ;; 4) edit_list_param "Hash Exts" "hash_extensions" ;;
            5) edit_num_param "Max Size" "max_hash_size_mb" "MB" ;; 6) edit_num_param "File Hash TTL" "file_hash_ttl" "s" ;;
            7) edit_num_param "Proc Interval" "process_monitor_interval" "s" ;; 8) edit_num_param "Proc Hash TTL" "process_hash_ttl" "s" ;;
            9) edit_num_param "Net TTL" "network_event_ttl" "s" ;; q|Q) return ;;
        esac
    done
}

#################################
# MAIN MENU
#################################
while true; do
    clear; draw_box "BLACK BOX SIEM - AGENT MANAGER"
    echo -e " Managed: $(jq '.agents | length' "$AGENTS_PATH" 2>/dev/null || echo 0) | Rules: $(jq '.process_rules | length' "$RULES_PATH" 2>/dev/null || echo 0)"
    echo -e "\n ${bold}[ OPERATIONS ]${nc}\n  1) Live Telemetry HUD\n  2) Enroll New Endpoint\n\n ${bold}[ POLICIES ]${nc}\n  3) EDR Rules\n  4) Firewall\n  5) Engine Params\n\n  6) Back to HUD"
    echo -ne "\n siem(agents)> "; read -n 1 choice
    case $choice in
        1) monitor_agents ;; 2) enroll_agent ;; 3) manage_rules ;;
        4) manage_firewall ;; 5) manage_settings ;; 6|q) exit 0 ;;
    esac
done
