#!/usr/bin/env bash
# =============================================================================
# gre-manager.sh – GRE Tunnel Manager for Truma
# =============================================================================
# Version: 2.1.4 (Fully debugged and improved)
# Changes:
#   - Added guard clause to prevent multiple sourcing
#   - Fixed octal bug in numeric validations (using 10#)
#   - Added iptables persistence (save rules after tunnel creation)
#   - Improved error messages and logging
# =============================================================================

set -euo pipefail

# Guard clause
if [[ "${__gre_manager_loaded:-}" == "true" ]]; then
    return 0
fi
__gre_manager_loaded=true

# Colors (fallback)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'; NC='\033[0m'

# Base functions (fallback if not defined in truma.sh)
if ! declare -f add_log >/dev/null 2>&1; then
    add_log() { echo "[gre] $1"; }
fi
if ! declare -f print_error >/dev/null 2>&1; then
    print_error() { echo -e "${RED}[]${NC} $1"; }
fi
if ! declare -f print_warning >/dev/null 2>&1; then
    print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
fi
if ! declare -f print_info >/dev/null 2>&1; then
    print_info() { echo -e "${BLUE}[i]${NC} $1"; }
fi
if ! declare -f pause_enter >/dev/null 2>&1; then
    pause_enter() { read -r -p "Press ENTER to continue..."; }
fi
if ! declare -f die_soft >/dev/null 2>&1; then
    die_soft() { add_log "ERROR: $1"; pause_enter; }
fi
if ! declare -f trim >/dev/null 2>&1; then
    trim() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$1"; }
fi
if ! declare -f is_int >/dev/null 2>&1; then
    is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }
fi
if ! declare -f valid_octet >/dev/null 2>&1; then
    valid_octet() { [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 0 && 10#$1 <= 255 )); }
fi
if ! declare -f valid_ipv4 >/dev/null 2>&1; then
    valid_ipv4() {
        local ip="$1"
        [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
        IFS='.' read -r a b c d <<<"$ip"
        valid_octet "$a" && valid_octet "$b" && valid_octet "$c" && valid_octet "$d"
    }
fi
if ! declare -f valid_port >/dev/null 2>&1; then
    valid_port() {
        local p="$1"
        is_int "$p" || return 1
        (( 10#$p >= 1 && 10#$p <= 65535 ))
    }
fi
if ! declare -f valid_tunnel_name >/dev/null 2>&1; then
    valid_tunnel_name() {
        local name="$1"
        [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]
    }
fi
if ! declare -f valid_base_network >/dev/null 2>&1; then
    valid_base_network() {
        local net="$1"
        valid_ipv4 "$net" || return 1
        IFS='.' read -r a b c d <<<"$net"
        [[ "$a" == "10" && "$d" == "0" ]]
    }
fi
if ! declare -f valid_mtu >/dev/null 2>&1; then
    valid_mtu() {
        local m="$1"
        [[ "$m" =~ ^[0-9]+$ ]] || return 1
        (( 10#$m >= 576 && 10#$m <= 1600 ))
    }
fi
if ! declare -f ask_until_valid >/dev/null 2>&1; then
    ask_until_valid() {
        local prompt="$1" validator="$2" __var="$3"
        local ans=""
        while true; do
            render
            echo -e "${YELLOW}${prompt}${NC}"
            read -r -e -p "> " ans
            ans="$(trim "$ans")"
            if [[ -z "$ans" ]]; then
                add_log "Empty input. Please try again."
                continue
            fi
            if "$validator" "$ans"; then
                printf -v "$__var" '%s' "$ans"
                add_log "OK: $prompt $ans"
                return 0
            else
                add_log "Invalid: $prompt $ans"
                add_log "Please enter a valid value."
            fi
        done
    }
fi
if ! declare -f ensure_command_exists >/dev/null 2>&1; then
    ensure_command_exists() {
        local cmd="$1"
        if ! command -v "$cmd" &>/dev/null; then
            print_error "Required command '$cmd' not found."
            return 1
        fi
        return 0
    }
fi

# =============================================================================
# Iptables persistence helper (if not defined in truma.sh)
# =============================================================================
if ! declare -f save_iptables_rules >/dev/null 2>&1; then
    save_iptables_rules() {
        if command -v iptables-save &>/dev/null; then
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4 2>/dev/null && \
                print_success "iptables rules saved." || \
                print_warning "Failed to save iptables rules."
            if command -v ip6tables-save &>/dev/null; then
                ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
            fi
        else
            print_warning "iptables-save not found; rules may not persist after reboot."
        fi
    }
fi

# =============================================================================
# GRE helper functions
# =============================================================================
get_tunnel_local_ip_cidr() {
    local name="$1"
    ip -4 -o addr show dev "$name" 2>/dev/null | awk '{print $4}' | head -n1
}

get_peer_ip_from_local_cidr() {
    local cidr="$1"
    local ip="${cidr%/*}"
    IFS='.' read -r a b c d <<<"$ip"
    local peer_d
    if [[ "$d" == "1" ]]; then
        peer_d="2"
    elif [[ "$d" == "2" ]]; then
        peer_d="1"
    else
        peer_d="2"
    fi
    echo "${a}.${b}.${c}.${peer_d}"
}

# =============================================================================
# GRE key generation and validation (32-bit)
# =============================================================================
generate_gre_key() {
    local key
    if [[ -c /dev/urandom ]]; then
        key=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
    else
        key=$(openssl rand -hex 4 2>/dev/null | head -c8) || key=""
    fi
    if [[ -z "$key" ]]; then
        key=$(( (RANDOM << 16) | RANDOM ))
    fi
    echo "$key"
}

validate_gre_key() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 0 && 10#$1 <= 4294967295 ))
}

# =============================================================================
# Main GRE functions
# =============================================================================

gre::create_interactive() {
    # Check dependencies
    ensure_command_exists "ip" || return 1
    ensure_command_exists "iptables" || return 1

    local side
    echo -e "\n${CYAN}${NC}"
    echo -e "${GREEN}  Create GRE Tunnel${NC}"
    echo -e "${CYAN}${NC}"
    echo "Select side:"
    echo "  1) Direct"
    echo "  2) Remote"
    echo
    echo -e "${YELLOW}Choice [1-2] (default 1):${NC}"
    read -r -p "> " side
    side="$(trim "$side")"
    if [[ -z "$side" ]]; then
        side="1"
    fi
    if [[ "$side" != "1" && "$side" != "2" ]]; then
        add_log "Invalid side selected."
        pause_enter
        return 0
    fi
    local side_name
    [[ "$side" == "1" ]] && side_name="Direct" || side_name="Remote"

    local name remote_ip local_ip base_net
    ask_until_valid "Tunnel name:" valid_tunnel_name name

    local_ip=$(ip -4 route get 1 | awk '{print $7; exit}' 2>/dev/null)
    if [[ -z "$local_ip" ]]; then
        local_ip=$(hostname -I | awk '{print $1}')
    fi
    render
    echo "SERVER IP: $local_ip"
    echo -e "${YELLOW}Is this correct? (y/n)${NC}"
    read -r -p "> " confirm
    confirm="$(trim "$confirm")"
    if [[ "$confirm" =~ ^[Nn] ]]; then
        ask_until_valid "Enter correct SERVER IP:" valid_ipv4 local_ip
    else
        add_log "SERVER IP confirmed: $local_ip"
    fi

    ask_until_valid "Remote IP:" valid_ipv4 remote_ip

    ask_until_valid "Base network (10.x.y.0):" valid_base_network base_net

    IFS='.' read -r a b c d <<<"$base_net"
    if [[ "$side" == "1" ]]; then
        local_tun_ip="${a}.${b}.${c}.1"
        peer_tun_ip="${a}.${b}.${c}.2"
    else
        local_tun_ip="${a}.${b}.${c}.2"
        peer_tun_ip="${a}.${b}.${c}.1"
    fi
    add_log "Tunnel IPs: local=$local_tun_ip/30, peer=$peer_tun_ip"

    # Get GRE key (manual or auto-generate)
    echo -e "${YELLOW}GRE key (enter to auto-generate a secure 32-bit key):${NC}"
    read -r -p "> " key
    if [[ -z "$key" ]]; then
        key=$(generate_gre_key)
        echo -e "\n${GREEN} Generated GRE key: ${CYAN}${key}${NC}"
        echo -e "${YELLOW}   (Press Enter to continue)${NC}"
        read -r
    else
        if ! validate_gre_key "$key"; then
            print_error "Invalid key. Must be a number between 0 and 4294967295."
            pause_enter
            return 1
        fi
    fi

    # Ask for MTU
    local mtu
    while true; do
        echo -e "${YELLOW}Enter MTU (576-1600) [default 1472]:${NC}"
        read -r -p "> " mtu_input
        mtu_input="$(trim "$mtu_input")"
        if [[ -z "$mtu_input" ]]; then
            mtu=1472
            break
        elif valid_mtu "$mtu_input"; then
            mtu="$mtu_input"
            break
        else
            echo "Invalid MTU. Must be between 576 and 1600."
        fi
    done

    local unit="${name}.service"
    local path="/etc/systemd/system/${unit}"

    if [[ -f "$path" ]]; then
        add_log "Service already exists: $unit"
        pause_enter
        return 0
    fi

    # Create startup script with iptables rules
    local script_path="/usr/local/bin/gre-tunnel-${name}.sh"
    cat > "$script_path" <<EOF
#!/bin/bash
set -euo pipefail

TUNNEL_NAME="$name"
REMOTE_IP="$remote_ip"
LOCAL_IP="$local_ip"
LOCAL_TUN_IP="$local_tun_ip/30"
MTU="$mtu"
KEY="$key"

case "\$1" in
    start)
        # Create tunnel
        ip tunnel del "\$TUNNEL_NAME" 2>/dev/null || true
        ip tunnel add "\$TUNNEL_NAME" mode gre local "\$LOCAL_IP" remote "\$REMOTE_IP" key "\$KEY"
        ip addr add "\$LOCAL_TUN_IP" dev "\$TUNNEL_NAME"
        ip link set "\$TUNNEL_NAME" mtu "\$MTU"
        ip link set "\$TUNNEL_NAME" up

        # Add iptables rules for forwarding (persistent)
        iptables -C FORWARD -i "\$TUNNEL_NAME" -j ACCEPT 2>/dev/null || iptables -A FORWARD -i "\$TUNNEL_NAME" -j ACCEPT
        iptables -C FORWARD -o "\$TUNNEL_NAME" -j ACCEPT 2>/dev/null || iptables -A FORWARD -o "\$TUNNEL_NAME" -j ACCEPT
        ;;
    stop)
        # Remove iptables rules
        iptables -C FORWARD -i "\$TUNNEL_NAME" -j ACCEPT 2>/dev/null && iptables -D FORWARD -i "\$TUNNEL_NAME" -j ACCEPT
        iptables -C FORWARD -o "\$TUNNEL_NAME" -j ACCEPT 2>/dev/null && iptables -D FORWARD -o "\$TUNNEL_NAME" -j ACCEPT

        # Bring down tunnel
        ip link set "\$TUNNEL_NAME" down 2>/dev/null || true
        ip tunnel del "\$TUNNEL_NAME" 2>/dev/null || true
        ;;
    restart)
        \$0 stop
        sleep 1
        \$0 start
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart}"
        exit 1
        ;;
esac
EOF
    chmod +x "$script_path"

    cat > "$path" <<EOF
[Unit]
Description=GRE Tunnel ${name} to (${remote_ip})
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${script_path} start
ExecStop=${script_path} stop
ExecReload=${script_path} restart

[Install]
WantedBy=multi-user.target
EOF

    add_log "Service created: $unit"
    systemctl daemon-reload
    if systemctl enable --now "${name}.service" >/dev/null 2>&1; then
        add_log "Service started."
    else
        add_log "Service failed to start. Check with: systemctl status ${name}.service"
    fi

    # Save iptables rules to ensure persistence after reboot
    save_iptables_rules

    echo -e "\n${GREEN}${NC}"
    echo -e "${GREEN}  Tunnel '$name' created successfully (${side_name})${NC}"
    echo -e "${GREEN}${NC}"
    echo "  Local tunnel IP  : ${local_tun_ip}/30"
    echo "  Peer tunnel IP   : ${peer_tun_ip}"
    echo "  MTU              : ${mtu}"
    echo "  GRE key          : ${key}"
    echo
    echo -e "${CYAN}---- Tunnel Service Status ----${NC}"
    systemctl --no-pager --full status "${name}.service" 2>&1 | head -12
    pause_enter
}

gre::list_ports() {
    print_info "GRE tunnels do not have built-in port forwarding."
    print_info "Use the Port Management menu to manage HAProxy rules."
    pause_enter
}

gre::add_port_interactive() {
    print_info "GRE tunnels no longer handle port forwarding directly."
    print_info "Please use the Port Management menu to add HAProxy rules."
    pause_enter
}

gre::remove_port_interactive() {
    gre::add_port_interactive
}

gre::remove() {
    local name="$1"
    echo -e "\n${CYAN}${NC}"
    echo -e "${RED}  Uninstall GRE Tunnel${NC}"
    echo -e "${CYAN}${NC}"
    echo "This will remove:"
    echo "  - /etc/systemd/system/${name}.service"
    echo "  - /usr/local/bin/gre-tunnel-${name}.sh"
    echo "  - GRE interface ${name} + routes"
    echo
    local confirm=""
    echo -e "${YELLOW}Confirm deletion? (y/n)${NC}"
    read -r -e -p "> " confirm
    confirm="$(trim "$confirm")"
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        add_log "Uninstall cancelled for $name"
        pause_enter
        return 0
    fi

    # Stop and disable service
    if systemctl list-unit-files 2>/dev/null | grep -q "^${name}\.service"; then
        add_log "Stopping ${name}.service"
        systemctl stop "${name}.service" >/dev/null 2>&1 || true
        systemctl disable "${name}.service" >/dev/null 2>&1 || true
        rm -f "/etc/systemd/system/${name}.service"
        rm -f "/etc/systemd/system/multi-user.target.wants/${name}.service" 2>/dev/null || true
    fi

    # Remove script
    rm -f "/usr/local/bin/gre-tunnel-${name}.sh"

    # Flush and delete tunnel
    if ip link show "$name" &>/dev/null; then
        add_log "Flushing tunnel interface $name"
        # First remove iptables rules (via script)
        if [[ -f "/usr/local/bin/gre-tunnel-${name}.sh" ]]; then
            "/usr/local/bin/gre-tunnel-${name}.sh" stop || true
        fi
        ip route flush dev "$name" 2>/dev/null || true
        ip addr flush dev "$name" 2>/dev/null || true
        ip link set "$name" down 2>/dev/null || true
        ip tunnel del "$name" 2>/dev/null || true
    fi

    # Remove cron jobs
    crontab -l 2>/dev/null | grep -v "/usr/local/bin/truma-restart-${name}.sh" | crontab - 2>/dev/null || true

    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true

    add_log "Uninstall completed for $name"
    pause_enter
}

gre::change_mtu() {
    local name="$1" mtu
    echo -e "\n${CYAN}${NC}"
    echo -e "${GREEN}  Change MTU for GRE Tunnel${NC}"
    echo -e "${CYAN}${NC}"
    ask_until_valid "New MTU (576-1600):" valid_mtu mtu

    add_log "Setting MTU on interface $name to $mtu..."
    if ip link set "$name" mtu "$mtu" 2>/dev/null; then
        add_log "MTU changed on live interface."
    else
        add_log "WARNING: Could not set MTU on live interface (will update service file)."
    fi

    local script="/usr/local/bin/gre-tunnel-${name}.sh"
    if [[ -f "$script" ]]; then
        sed -i.bak "s/^MTU=.*/MTU=\"$mtu\"/" "$script"
        rm -f "$script.bak"
        add_log "Updated script MTU."
    fi

    local unit="/etc/systemd/system/${name}.service"
    if [[ ! -f "$unit" ]]; then
        print_error "Unit file not found: $unit"
        pause_enter
        return 1
    fi

    systemctl daemon-reload
    systemctl restart "${name}.service" >/dev/null 2>&1 || add_log "WARNING: restart failed for ${name}.service"

    add_log "Done: MTU changed to $mtu"
    pause_enter
}

gre::setup_antifilter() {
    print_info "Anti-filter is disabled in this version."
    pause_enter
}
gre::remove_antifilter() {
    print_info "Anti-filter is disabled in this version."
    pause_enter
}

# =============================================================================
# End of file
# =============================================================================