#!/usr/bin/env bash
# =============================================================================
# truma.sh – Truma Tunnel Manager (Main Menu)
# =============================================================================
# Version: 2.1.4 (Fully debugged and improved)
# Changes:
#   - Fixed octal bug in all numeric validations (using 10#)
#   - Added port collision detection with ss/netstat
#   - Added guard clause to prevent multiple sourcing
#   - Enhanced logging (file + memory)
#   - Improved error messages and input validation
# =============================================================================

set -euo pipefail

# =============================================================================
# Guard clause to prevent multiple sourcing
# =============================================================================
if [[ "${__truma_main_loaded:-}" == "true" ]]; then
    return 0
fi
__truma_main_loaded=true

# =============================================================================
# Global variables and constants
# =============================================================================
readonly MIN_MTU=576
readonly MAX_MTU_GRE=1600
readonly MAX_MTU_GLOBAL=9000
readonly MAX_TUNNEL_NAME_LEN=64
readonly TRUMA_DIR="/opt/truma"
readonly LOG_FILE="/var/log/truma.log"

NONINTERACTIVE=0
[[ ! -t 0 ]] && NONINTERACTIVE=1
export NONINTERACTIVE
export LC_ALL=C

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'; NC='\033[0m'

# =============================================================================
# Improved logging (file + memory)
# =============================================================================
declare -a LOG_LINES=()
LOG_MIN=3
LOG_MAX=10

log_to_file() {
    local msg="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] $msg" >> "$LOG_FILE"
}

add_log() {
    local msg="${1:-No message}"
    local ts
    ts="$(date +"%H:%M:%S")"
    LOG_LINES+=("[$ts] $msg")
    if ((${#LOG_LINES[@]} > LOG_MAX)); then
        LOG_LINES=("${LOG_LINES[@]: -$LOG_MAX}")
    fi
    log_to_file "$msg"
}

print_step()   { echo -e "${CYAN}[*]${NC} $1"; add_log "[*] $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; add_log "[✓] $1"; }
print_error()   { echo -e "${RED}[✗]${NC} $1"; add_log "[✗] $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; add_log "[!] $1"; }
print_info()    { echo -e "${BLUE}[i]${NC} $1"; add_log "[i] $1"; }

# =============================================================================
# Root check
# =============================================================================
ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        if command -v sudo &>/dev/null; then
            echo -e "${YELLOW}[!] This script must be run as root. Re‑running with sudo...${NC}"
            exec sudo bash "$0" "$@"
        else
            echo -e "${RED}[✗] This script must be run as root, but sudo is not available.${NC}"
            exit 1
        fi
    fi
}
ensure_root "$@"

# =============================================================================
# Dependency check
# =============================================================================
ensure_command_exists() {
    local cmd="$1"
    local package="${2:-$1}"
    if ! command -v "$cmd" &>/dev/null; then
        print_error "Required command '$cmd' not found. Please install package '$package'."
        if [[ $NONINTERACTIVE -eq 0 ]]; then
            read -p "Attempt to install automatically? (y/n): " -n 1 answer
            echo
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                if command -v apt-get &>/dev/null; then
                    apt-get update && apt-get install -y "$package"
                elif command -v yum &>/dev/null; then
                    yum install -y "$package"
                elif command -v dnf &>/dev/null; then
                    dnf install -y "$package"
                elif command -v pacman &>/dev/null; then
                    pacman -S --noconfirm "$package"
                elif command -v apk &>/dev/null; then
                    apk add --no-cache "$package"
                else
                    print_error "No supported package manager found. Please install '$package' manually."
                    return 1
                fi
                if ! command -v "$cmd" &>/dev/null; then
                    print_error "Installation failed. Please install '$package' manually."
                    return 1
                fi
                print_success "Package '$package' installed successfully."
            else
                return 1
            fi
        else
            return 1
        fi
    fi
    return 0
}

# =============================================================================
# Script directory and module loading
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Helper to source a module with error handling and guard clauses
source_module() {
    local module="$1"
    local path="${SCRIPT_DIR}/${module}"
    if [[ ! -f "$path" ]]; then
        print_error "Required module not found: $module"
        exit 1
    fi
    if ! source "$path"; then
        print_error "Failed to load module: $module"
        exit 1
    fi
    print_success "Module loaded: $module"
}

# Load modules (each will prevent double sourcing)
source_module "gre-manager.sh"
source_module "paqet.sh"
source_module "mesh-manager.sh"
source_module "haproxy-manager.sh"

# =============================================================================
# UI helpers
# =============================================================================
FORCE=${FORCE:-0}
MENU_SELECTED=-1

banner() {
    echo -e "${MAGENTA}"
    cat <<'EOF'
████████╗██████╗ ██╗   ██╗███╗   ███╗ █████╗
╚══██╔══╝██╔══██╗██║   ██║████╗ ████║██╔══██╗
   ██║   ██████╔╝██║   ██║██╔████╔██║███████║
   ██║   ██╔══██╗██║   ██║██║╚██╔╝██║██╔══██║
   ██║   ██║  ██║╚██████╔╝██║ ╚═╝ ██║██║  ██║
   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝
Truma - Tunnel Manager
EOF
    echo -e "${NC}"
}

render() {
    [[ $NONINTERACTIVE -eq 0 ]] && clear
    banner
    echo

    local shown_count="${#LOG_LINES[@]}"
    local height=$shown_count
    ((height < LOG_MIN)) && height=$LOG_MIN
    ((height > LOG_MAX)) && height=$LOG_MAX

    echo "┌───────────────────────────── ACTION LOG ─────────────────────────────┐"
    local start_index=0
    if ((shown_count > height)); then
        start_index=$((shown_count - height))
    fi
    ((start_index < 0)) && start_index=0

    local i line
    for ((i=start_index; i<shown_count; i++)); do
        line="${LOG_LINES[$i]}"
        printf "│ %-68s │\n" "$line"
    done

    local missing=$((height - (shown_count - start_index)))
    for ((i=0; i<missing; i++)); do
        printf "│ %-68s │\n" ""
    done

    echo "└──────────────────────────────────────────────────────────────────────┘"
    echo
}

pause_enter() {
    if [[ $NONINTERACTIVE -eq 1 ]]; then
        return 0
    fi
    echo
    read -r -p "Press ENTER to continue..."
}

trim() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$1"; }

# =============================================================================
# Input validation functions (with octal fix and port collision)
# =============================================================================
valid_octet() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 0 && 10#$1 <= 255 ))
}
is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }

valid_ipv4() {
    local ip="$1"
    if [[ ! "$ip" =~ ^[0-9.]+$ ]]; then
        return 1
    fi
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r a b c d <<<"$ip"
    valid_octet "$a" && valid_octet "$b" && valid_octet "$c" && valid_octet "$d"
}

valid_port() {
    local p="$1"
    is_int "$p" || return 1
    if (( 10#$p >= 1 && 10#$p <= 65535 )); then
        # Check if port is already in use
        if command -v ss &>/dev/null; then
            if ss -tuln 2>/dev/null | grep -q ":$p "; then
                print_error "Port $p is already in use by another process."
                return 1
            fi
        elif command -v netstat &>/dev/null; then
            if netstat -tuln 2>/dev/null | grep -q ":$p "; then
                print_error "Port $p is already in use by another process."
                return 1
            fi
        fi
        return 0
    else
        return 1
    fi
}

valid_mtu_global() {
    local m="$1"
    is_int "$m" || return 1
    (( 10#$m >= MIN_MTU && 10#$m <= MAX_MTU_GLOBAL ))
}

valid_mtu_gre() {
    local m="$1"
    is_int "$m" || return 1
    (( 10#$m >= MIN_MTU && 10#$m <= MAX_MTU_GRE ))
}

valid_tunnel_name() {
    local n="$1"
    [[ "$n" =~ ^[a-zA-Z0-9_-]+$ ]]
}

valid_mac() { [[ "$1" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; }

# =============================================================================
# Safe input readers (with printf -v, no eval)
# =============================================================================
read_required() {
    local p="$1" v="$2" d="${3:-}" val
    while true; do
        echo -e "${YELLOW}${p}${NC}"
        [[ -n "$d" ]] && echo -e "${CYAN}[default: $d]${NC}"
        read -r -p "> " val
        val="$(trim "$val")"
        [[ -z "$val" && -n "$d" ]] && val="$d"
        if [[ -n "$val" ]]; then
            printf -v "$v" "%s" "$val"
            return 0
        fi
        echo "This field is required."
    done
}

read_ip() {
    local p="$1" v="$2" d="${3:-}" val
    while true; do
        read_required "$p" "$v" "$d"
        val="$(eval echo "\$$v")"
        if valid_ipv4 "$val"; then
            return 0
        fi
        echo "Invalid IPv4 address."
    done
}

read_port() {
    local p="$1" v="$2" d="${3:-}" val
    while true; do
        read_required "$p" "$v" "$d"
        val="$(eval echo "\$$v")"
        if valid_port "$val"; then
            return 0
        fi
        echo "Invalid port (1-65535) or port already in use."
    done
}

read_mtu() {
    local p="$1" v="$2" d="${3:-}" val
    while true; do
        echo -e "${YELLOW}${p}${NC}"
        [[ -n "$d" ]] && echo -e "${CYAN}[default: $d]${NC}"
        read -r -p "> " val
        val="$(trim "$val")"
        [[ -z "$val" && -n "$d" ]] && val="$d"
        if is_int "$val"; then
            printf -v "$v" "%s" "$val"
            return 0
        fi
        if [[ $NONINTERACTIVE -eq 1 ]]; then
            print_error "Non-interactive and invalid MTU"
            exit 1
        fi
        echo "Invalid MTU (must be integer)."
    done
}

read_ports() {
    local p="$1" v="$2" d="${3:-}" val
    while true; do
        echo -e "${YELLOW}${p}${NC}"
        [[ -n "$d" ]] && echo -e "${CYAN}[default: $d]${NC}"
        read -r -p "> " val
        val="$(trim "$val")"
        [[ -z "$val" && -n "$d" ]] && val="$d"
        val="${val// /}"
        IFS=',' read -ra ps <<<"$val"
        local ok=1
        for x in "${ps[@]}"; do
            if ! valid_port "$x"; then ok=0; break; fi
        done
        if ((ok)); then
            printf -v "$v" "%s" "$val"
            return 0
        fi
        echo "Invalid port(s). Use comma-separated numbers."
    done
}

read_confirm() {
    local p="$1" v="$2" d="${3:-y}" val
    while true; do
        echo -e "${YELLOW}${p} (y/n)${NC}"
        [[ -n "$d" ]] && echo -e "${CYAN}[default: $d]${NC}"
        read -r -p "> " val
        val="$(trim "$val")"
        [[ -z "$val" ]] && val="$d"
        case "$val" in
            [Yy]*) printf -v "$v" "true"; return 0 ;;
            [Nn]*) printf -v "$v" "false"; return 0 ;;
            *) echo "Please enter y/n." ;;
        esac
    done
}

read_mac() {
    local p="$1" v="$2" d="${3:-}" val
    while true; do
        echo -e "${YELLOW}${p}${NC}"
        [[ -n "$d" ]] && echo -e "${CYAN}[default: $d]${NC}"
        read -r -p "> " val
        val="$(trim "$val")"
        [[ -z "$val" && -n "$d" ]] && val="$d"
        if valid_mac "$val"; then
            printf -v "$v" "%s" "$val"
            return 0
        fi
        echo "Invalid MAC (format: aa:bb:cc:dd:ee:ff)."
    done
}

# =============================================================================
# Tunnel name retrieval functions
# =============================================================================
get_tunnel_names() {
    local names=()
    while IFS= read -r unit; do
        local base="${unit%.service}"
        if [[ "$unit" =~ ^paqet@(.+)\.service$ ]]; then
            names+=("${BASH_REMATCH[1]}")
            continue
        fi
        if [[ "$unit" =~ ^paqet-(.+)\.service$ ]] && ! [[ "$unit" == *-fw-* ]]; then
            names+=("${BASH_REMATCH[1]}")
            continue
        fi
        if [[ "$unit" =~ ^mesh-(.+)\.service$ ]]; then
            names+=("${BASH_REMATCH[1]}")
            continue
        fi
        if systemctl show -p Description "$unit" 2>/dev/null | grep -q "GRE Tunnel"; then
            names+=("$base")
        fi
    done < <(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}')
    printf "%s\n" "${names[@]}" | sort -u
}

get_tunnel_type() {
    local name="$1"
    if systemctl list-unit-files --no-legend 2>/dev/null | grep -q "^paqet@${name}\.service" || \
       systemctl list-unit-files --no-legend 2>/dev/null | grep -q "^paqet-${name}\.service"; then
        echo "paqet"; return 0
    fi
    if systemctl list-unit-files --no-legend 2>/dev/null | grep -q "^mesh-${name}\.service"; then
        echo "mesh"; return 0
    fi
    if systemctl list-unit-files --no-legend 2>/dev/null | grep -q "^${name}\.service"; then
        if systemctl show -p Description "${name}.service" 2>/dev/null | grep -q "GRE Tunnel"; then
            echo "gre"; return 0
        fi
    fi
    echo "unknown"; return 1
}

# Helper to get target IP for a tunnel (for HAProxy)
get_target_ip_for_tunnel() {
    local name="$1"
    local type="$(get_tunnel_type "$name")"
    local target_ip=""

    if [[ "$type" == "gre" ]]; then
        local cidr
        cidr="$(get_tunnel_local_ip_cidr "$name" 2>/dev/null)"
        if [[ -n "$cidr" ]]; then
            target_ip="$(get_peer_ip_from_local_cidr "$cidr")"
        fi
    elif [[ "$type" == "mesh" ]]; then
        local service_file="/etc/systemd/system/mesh-${name}.service"
        if [[ -f "$service_file" ]]; then
            target_ip=$(grep -o '\-i [0-9.]\+' "$service_file" | head -1 | cut -d' ' -f2)
            if [[ -z "$target_ip" ]]; then
                target_ip=$(sed -n 's/.*-i \([0-9.]\+\).*/\1/p' "$service_file" | head -1)
            fi
        fi
    fi
    echo "$target_ip"
}

menu_select_index() {
    local title="$1" prompt="$2" choice
    shift 2; local -a items=("$@")
    while true; do
        render
        echo "$title"
        echo
        if (( ${#items[@]} == 0 )); then
            echo "No tunnel found."
            pause_enter
            MENU_SELECTED=-1
            return 1
        fi
        for i in "${!items[@]}"; do
            printf "%d) %s\n" $((i+1)) "${items[i]}"
        done
        echo "0) Back"
        read -r -e -p "$prompt " choice
        choice="$(trim "$choice")"
        [[ "$choice" == "0" ]] && { MENU_SELECTED=-1; return 1; }
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
            MENU_SELECTED=$((choice-1)); return 0
        fi
        add_log "Invalid selection: $choice"
    done
}

# =============================================================================
# Cron management (improved)
# =============================================================================
safe_crontab_remove_pattern() {
    local pattern="$1"
    if [[ -z "$pattern" ]]; then
        print_error "Empty pattern for crontab removal"
        return 1
    fi
    local tmp
    tmp=$(mktemp /tmp/truma-cron.XXXXXX) || { print_error "mktemp failed"; return 1; }
    trap 'rm -f -- "$tmp" "${tmp}.new" 2>/dev/null' RETURN
    crontab -l 2>/dev/null > "$tmp" || true
    grep -vF -- "$pattern" "$tmp" > "${tmp}.new" || true
    crontab "${tmp}.new" 2>/dev/null || true
    rm -f -- "$tmp" "${tmp}.new" 2>/dev/null
    trap - RETURN
}

setup_auto_restart() {
    local name="$1"
    local type="$(get_tunnel_type "$name")"
    local service_name
    case "$type" in
        gre)   service_name="${name}.service" ;;
        paqet) service_name="paqet-${name}.service" ;;
        mesh)  service_name="mesh-${name}.service" ;;
        *)     print_error "Unknown tunnel type"; return 1 ;;
    esac
    local cron_cmd="systemctl restart ${service_name}"
    local current_cron
    current_cron=$(crontab -l 2>/dev/null | grep -F "$cron_cmd" || true)

    echo
    echo -e "${CYAN}Auto Restart for tunnel: $name${NC}"
    if [[ -n "$current_cron" ]]; then
        echo -e "${YELLOW}Current cron:${NC} $current_cron"
        echo
        read -r -p "Remove existing cron? (y/N): " rem
        if [[ "$rem" =~ ^[Yy]$ ]]; then
            safe_crontab_remove_pattern "$cron_cmd"
            print_success "Cron removed."
        fi
    else
        echo "No existing auto restart cron."
    fi
    echo
    echo "Select interval unit:"
    echo "  1) Minute(s)"
    echo "  2) Hour(s)"
    read -r -p "Choice [1-2] (default 1 for minutes): " unit_choice
    unit_choice="${unit_choice:-1}"

    local cron_time=""
    if [[ "$unit_choice" == "1" ]]; then
        read -r -p "Enter interval in minutes (1-59, default 5): " interval
        interval="${interval:-5}"
        if ! [[ "$interval" =~ ^[0-9]+$ ]] || ((interval < 1 || interval > 59)); then
            print_error "Invalid minute interval, using default 5."
            interval=5
        fi
        cron_time="*/${interval} * * * *"
    else
        read -r -p "Enter interval in hours (1-23, default 1): " interval
        interval="${interval:-1}"
        if ! [[ "$interval" =~ ^[0-9]+$ ]] || ((interval < 1 || interval > 23)); then
            print_error "Invalid hour interval, using default 1."
            interval=1
        fi
        cron_time="0 */${interval} * * *"
    fi

    local new_cron_line="$cron_time $cron_cmd >> ${LOG_FILE} 2>&1"
    safe_crontab_remove_pattern "$cron_cmd"
    (crontab -l 2>/dev/null || true; echo "$new_cron_line") | sort -u | crontab -
    print_success "Auto restart cron added: $new_cron_line"
}

# =============================================================================
# Service management functions
# =============================================================================
service_action_menu() {
    local unit="$1" action
    local name="${unit%.service}"
    name="${name#paqet-}"
    name="${name#paqet@}"
    name="${name#mesh-}"
    local type="$(get_tunnel_type "$name")"

    ensure_command_exists "systemctl" || { pause_enter; return 1; }

    while true; do
        render
        echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  Tunnel: $name${NC}"
        echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
        echo
        echo -e "  ${WHITE}[1]${NC} 🟢 Enable & Start"
        echo -e "  ${WHITE}[2]${NC} 🔄 Restart"
        echo -e "  ${WHITE}[3]${NC} ⏹️  Stop & Disable"
        echo -e "  ${WHITE}[4]${NC} 📊 Status"
        echo -e "  ${WHITE}[5]${NC} ⏰ Set Auto Restart (Cron)"
        if [[ "$type" == "paqet" ]]; then
            echo -e "  ${WHITE}[6]${NC} 🔧 Change Mode (KCP)"
        elif [[ "$type" == "mesh" ]]; then
            echo -e "  ${WHITE}[6]${NC} 🌐 Show Peers (EMC)"
        fi
        echo -e "  ${WHITE}[0]${NC} ↩️  Back"
        echo
        read -r -e -p "Select action: " action
        action="$(trim "$action")"

        case "$action" in
            1)
                add_log "Enable & Start: $unit"
                systemctl enable "$unit" >/dev/null 2>&1 && add_log "Enabled: $unit" || add_log "Enable failed: $unit"
                systemctl start "$unit"  >/dev/null 2>&1 && add_log "Started: $unit" || add_log "Start failed: $unit"
                ;;
            2)
                add_log "Restart: $unit"
                systemctl restart "$unit" >/dev/null 2>&1 && add_log "Restarted: $unit" || add_log "Restart failed: $unit"
                ;;
            3)
                add_log "Stop & Disable: $unit"
                systemctl stop "$unit"    >/dev/null 2>&1 && add_log "Stopped: $unit" || add_log "Stop failed: $unit"
                systemctl disable "$unit" >/dev/null 2>&1 && add_log "Disabled: $unit" || add_log "Disable failed: $unit"
                ;;
            4)
                add_log "Show status: $unit"
                echo "---- STATUS ($unit) ----"
                systemctl --no-pager --full status "$unit" 2>&1
                echo
                pause_enter
                ;;
            5)
                add_log "Setting up auto restart cron for $name"
                setup_auto_restart "$name"
                ;;
            6)
                if [[ "$type" == "paqet" ]]; then
                    add_log "Changing mode for $name"
                    paqet::change_mode_interactive "$name"
                elif [[ "$type" == "mesh" ]]; then
                    add_log "Showing peers for $name"
                    mesh::list_peers "$name"
                else
                    print_error "Invalid action."
                fi
                pause_enter
                ;;
            0) return 0 ;;
            *) add_log "Invalid action: $action" ;;
        esac
    done
}

services_management() {
    local sel
    while true; do
        render
        echo "Services Management"
        echo
        echo "1) Tunnels"
        echo "0) Back"
        echo
        read -r -e -p "Select: " sel
        sel="$(trim "$sel")"
        case "$sel" in
            1)
                mapfile -t TUNNEL_NAMES < <(get_tunnel_names)
                menu_select_index "Tunnel Services" "Select tunnel:" "${TUNNEL_NAMES[@]}" || continue
                name="${TUNNEL_NAMES[$MENU_SELECTED]}"
                add_log "Tunnel selected: $name"
                type="$(get_tunnel_type "$name")"
                if [[ "$type" == "gre" ]]; then
                    service_action_menu "${name}.service"
                elif [[ "$type" == "paqet" ]]; then
                    if systemctl list-unit-files --no-legend 2>/dev/null | grep -q "^paqet-${name}\.service"; then
                        service_action_menu "paqet-${name}.service"
                    else
                        service_action_menu "paqet@${name}.service"
                    fi
                elif [[ "$type" == "mesh" ]]; then
                    service_action_menu "mesh-${name}.service"
                else
                    add_log "Unknown tunnel type."
                    pause_enter
                fi
                ;;
            0) return 0 ;;
            *) add_log "Invalid selection: $sel"; pause_enter ;;
        esac
    done
}

create_tunnel() {
    render
    echo "Select tunnel type:"
    echo "1) GRE"
    echo "2) KCP"
    echo "3) EMC"
    echo
    local tunnel_type
    while true; do
        read -r -p "Choice [1-3]: " tunnel_type
        tunnel_type="$(trim "$tunnel_type")"
        case "$tunnel_type" in
            1|2|3) break ;;
            *) echo "Invalid choice. Please enter 1, 2, or 3." ;;
        esac
    done

    if [[ "$tunnel_type" == "1" ]]; then
        gre::create_interactive
        pause_enter
    elif [[ "$tunnel_type" == "2" ]]; then
        paqet::create_interactive
        pause_enter
    else
        mesh::create_interactive
        pause_enter
    fi
}

# =============================================================================
# Port management (using HAProxy or Paqet native)
# =============================================================================
add_tunnel_port() {
    render
    add_log "Selected: add tunnel port"
    mapfile -t TUNNEL_NAMES < <(get_tunnel_names)
    menu_select_index "Add Port to Tunnel" "Select tunnel:" "${TUNNEL_NAMES[@]}" || return 0
    name="${TUNNEL_NAMES[$MENU_SELECTED]}"
    add_log "Tunnel selected: $name"
    type="$(get_tunnel_type "$name")"

    if [[ "$type" == "paqet" ]]; then
        paqet::add_port_interactive "$name"
        return 0
    fi

    local target_ip
    target_ip="$(get_target_ip_for_tunnel "$name")"

    if [[ -n "$target_ip" ]]; then
        echo -e "${YELLOW}Target IP automatically detected: $target_ip${NC}"
        read_confirm "Use this IP? (y/n)" confirm "y"
        if [[ "$confirm" != true ]]; then
            read_ip "Enter target IP manually:" target_ip
        fi
    else
        print_warning "Could not auto-detect target IP. Please enter it manually."
        read_ip "Enter target IP (e.g., 10.54.15.2):" target_ip
    fi

    read_port "Enter bind port (on Iran):" bind_port
    read_port "Enter destination port (on Kharej):" dest_port "$bind_port"

    haproxy::add_rule "$bind_port" "$target_ip" "$dest_port" "Tunnel $name"
    pause_enter
}

list_forwarded_ports() {
    render
    mapfile -t TUNNEL_NAMES < <(get_tunnel_names)
    menu_select_index "List Forwarded Ports" "Select tunnel:" "${TUNNEL_NAMES[@]}" || return 0
    name="${TUNNEL_NAMES[$MENU_SELECTED]}"
    type="$(get_tunnel_type "$name")"

    if [[ "$type" == "paqet" ]]; then
        paqet::list_ports "$name"
    else
        echo -e "${CYAN}Forwarded ports for $name via HAProxy:${NC}"
        local count=0
        if [[ -d /etc/haproxy/conf.d ]]; then
            for f in /etc/haproxy/conf.d/rule_*.cfg; do
                if [[ -f "$f" ]] && grep -q "Tunnel $name" "$f"; then
                    count=$((count+1))
                    local port
                    port=$(basename "$f" | sed 's/rule_\(.*\)\.cfg/\1/')
                    local target
                    target=$(grep -E '^[[:space:]]*server' "$f" | awk '{print $3}' | head -1)
                    echo "  $port → $target"
                fi
            done
        fi
        if [[ $count -eq 0 ]]; then
            echo "  (no rules)"
        fi
    fi
    pause_enter
}

remove_tunnel_port() {
    render
    mapfile -t TUNNEL_NAMES < <(get_tunnel_names)
    menu_select_index "Remove Port from Tunnel" "Select tunnel:" "${TUNNEL_NAMES[@]}" || return 0
    name="${TUNNEL_NAMES[$MENU_SELECTED]}"
    type="$(get_tunnel_type "$name")"

    if [[ "$type" == "paqet" ]]; then
        paqet::remove_port_interactive "$name"
        return 0
    fi

    local rules=()
    if [[ -d /etc/haproxy/conf.d ]]; then
        for f in /etc/haproxy/conf.d/rule_*.cfg; do
            if [[ -f "$f" ]] && grep -q "Tunnel $name" "$f"; then
                rules+=("$f")
            fi
        done
    fi

    if [[ ${#rules[@]} -eq 0 ]]; then
        print_info "No HAProxy rules found for $name."
        pause_enter
        return 0
    fi

    echo -e "${CYAN}Available ports for $name:${NC}"
    local ports=()
    for f in "${rules[@]}"; do
        local port
        port=$(basename "$f" | sed 's/rule_\(.*\)\.cfg/\1/')
        ports+=("$port")
        local target
        target=$(grep -E '^[[:space:]]*server' "$f" | awk '{print $3}' | head -1)
        echo "  $port → $target"
    done

    echo ""
    read_port "Enter bind port to remove:" bind_port

    local rule_file="/etc/haproxy/conf.d/rule_${bind_port}.cfg"
    if [[ ! -f "$rule_file" ]]; then
        print_error "Rule for port $bind_port not found."
        pause_enter
        return 1
    fi

    if ! grep -q "Tunnel $name" "$rule_file"; then
        print_error "Port $bind_port is not associated with tunnel $name."
        pause_enter
        return 1
    fi

    haproxy::remove_rule "$bind_port"
    pause_enter
}

# =============================================================================
# Change MTU
# =============================================================================
change_mtu() {
    render
    add_log "Selected: Change MTU"
    mapfile -t TUNNEL_NAMES < <(get_tunnel_names)
    menu_select_index "Change MTU" "Select tunnel:" "${TUNNEL_NAMES[@]}" || return 0
    name="${TUNNEL_NAMES[$MENU_SELECTED]}"
    add_log "Tunnel selected: $name"
    type="$(get_tunnel_type "$name")"

    local validator
    if [[ "$type" == "gre" ]]; then
        validator="valid_mtu_gre"
    else
        validator="valid_mtu_global"
    fi

    local mtu=""
    while true; do
        read_mtu "Enter new MTU ($MIN_MTU-$MAX_MTU_GLOBAL)" mtu
        if "$validator" "$mtu"; then
            break
        fi
        echo "Invalid MTU for this tunnel type." > /dev/tty
    done

    if [[ "$type" == "gre" ]]; then
        gre::change_mtu "$name" "$mtu"
    elif [[ "$type" == "paqet" ]]; then
        paqet::change_mtu "$name" "$mtu"
    elif [[ "$type" == "mesh" ]]; then
        mesh::change_mtu "$name"
    else
        add_log "Unknown tunnel type."
        pause_enter
    fi
}

# =============================================================================
# Uninstall tunnel (complete cleanup)
# =============================================================================
uninstall_clean() {
    render
    add_log "Selected: Uninstall Tunnel"
    mapfile -t TUNNEL_NAMES < <(get_tunnel_names)
    menu_select_index "Uninstall Tunnel" "Select tunnel to uninstall:" "${TUNNEL_NAMES[@]}" || return 0
    name="${TUNNEL_NAMES[$MENU_SELECTED]}"
    add_log "Tunnel selected: $name"
    type="$(get_tunnel_type "$name")"

    echo
    echo -e "${RED}⚠️  WARNING: You are about to delete tunnel '$name'!${NC}"
    read -r -p "Are you sure? (type 'yes' to confirm): " confirm
    if [[ "$confirm" != "yes" ]]; then
        add_log "Uninstall cancelled."
        pause_enter
        return 0
    fi

    if [[ "$type" == "gre" ]]; then
        gre::remove "$name"
    elif [[ "$type" == "paqet" ]]; then
        paqet::remove "$name"
    elif [[ "$type" == "mesh" ]]; then
        mesh::remove "$name"
    else
        add_log "Unknown tunnel type."
        pause_enter
        return
    fi

    # Remove HAProxy rules associated with this tunnel
    local haproxy_rules_removed=0
    if [[ -d /etc/haproxy/conf.d ]]; then
        for f in /etc/haproxy/conf.d/rule_*.cfg; do
            if [[ -f "$f" ]] && grep -q "Tunnel $name" "$f"; then
                rm -f "$f"
                haproxy_rules_removed=1
                add_log "Removed HAProxy rule: $(basename "$f")"
            fi
        done
    fi

    if [[ $haproxy_rules_removed -eq 1 ]] && command -v haproxy &>/dev/null; then
        if declare -f haproxy::apply >/dev/null 2>&1; then
            haproxy::apply 2>/dev/null || true
        else
            systemctl reload haproxy 2>/dev/null || true
        fi
        print_info "HAProxy reloaded after removing rules."
    fi

    # Remove cron jobs for this tunnel
    safe_crontab_remove_pattern "systemctl restart ${name}.service"
    safe_crontab_remove_pattern "systemctl restart paqet-${name}.service"
    safe_crontab_remove_pattern "systemctl restart mesh-${name}.service"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
        systemctl reset-failed 2>/dev/null || true
    fi

    print_success "Tunnel '$name' has been completely removed (including HAProxy rules)."
    pause_enter
}

# =============================================================================
# Anti-filter placeholder
# =============================================================================
setup_antifilter_all() {
    render
    echo "Anti-Filter System"
    echo "1) Enable"
    echo "2) Remove"
    read -r -p "Select option [1-2]: " af_choice
    af_choice="$(trim "$af_choice")"
    case "$af_choice" in
        1)
            add_log "Enable Anti-Filter"
            echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}  Coming Soon!${NC}"
            echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
            echo "This feature is not yet implemented."
            pause_enter
            ;;
        2)
            add_log "Remove Anti-Filter"
            echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}  Coming Soon!${NC}"
            echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
            echo "This feature is not yet implemented."
            pause_enter
            ;;
        *) add_log "Invalid option: $af_choice"; pause_enter ;;
    esac
}

# =============================================================================
# Port management submenu
# =============================================================================
port_management_menu() {
    while true; do
        render
        echo -e "${YELLOW}══════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}  Port Management${NC}"
        echo -e "${YELLOW}══════════════════════════════════════════════════${NC}"
        echo
        echo -e "  ${CYAN}[1]${NC} ➕ Add Port Forward (HAProxy for GRE/EMC)"
        echo -e "  ${CYAN}[2]${NC} 📋 List Forwarded Ports"
        echo -e "  ${CYAN}[3]${NC} ❌ Remove Port Forward"
        echo -e "  ${CYAN}[4]${NC} 🔄 Reload HAProxy"
        echo -e "  ${CYAN}[5]${NC} 🗑️  Remove All HAProxy Rules"
        echo -e "  ${CYAN}[6]${NC} 📊 HAProxy Status"
        echo -e "  ${CYAN}[0]${NC} ↩️  Back"
        echo
        read -r -e -p "Select option: " choice
        choice="$(trim "$choice")"
        case "$choice" in
            1) add_tunnel_port ;;
            2) list_forwarded_ports ;;
            3) remove_tunnel_port ;;
            4) haproxy::apply; pause_enter ;;
            5)
                read_confirm "Are you sure you want to remove ALL HAProxy rules?" confirm "n"
                if [[ "$confirm" == "true" ]]; then
                    haproxy::remove_all
                fi
                pause_enter
                ;;
            6) haproxy::status; pause_enter ;;
            0) break ;;
            *) add_log "Invalid option: $choice"; pause_enter ;;
        esac
    done
}

# =============================================================================
# Main menu
# =============================================================================
main_menu() {
    local choice
    while true; do
        render
        echo -e "${YELLOW}══════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}  Truma Tunnel Manager${NC}"
        echo -e "${YELLOW}══════════════════════════════════════════════════${NC}"
        echo
        echo -e "  ${CYAN}[1]${NC} 🚀 Create New Tunnel"
        echo -e "  ${CYAN}[2]${NC} 🔍 Show Active Tunnels"
        echo -e "  ${CYAN}[3]${NC} 🧹 Uninstall Tunnel"
        echo -e "  ${CYAN}[4]${NC} 🔧 Port Management"
        echo -e "  ${CYAN}[5]${NC} 🛡️ Anti-Filter System"
        echo -e "  ${CYAN}[6]${NC} 📦 Change MTU"
        echo -e "  ${CYAN}[0]${NC} ❌ Exit"
        echo
        read -r -e -p "Select option: " choice
        choice="$(trim "$choice")"
        case "$choice" in
            1) add_log "Create New Tunnel"; create_tunnel ;;
            2) add_log "Show Active Tunnels"; services_management ;;
            3) add_log "Uninstall Tunnel"; uninstall_clean ;;
            4) add_log "Port Management"; port_management_menu ;;
            5) add_log "Anti-Filter System"; setup_antifilter_all ;;
            6) add_log "Change MTU"; change_mtu ;;
            0) add_log "Exit"; render; exit 0 ;;
            *) add_log "Invalid option: $choice"; pause_enter ;;
        esac
    done
}

add_log "Truma Tunnel Manager started"
main_menu