#!/usr/bin/env bash
# =============================================================================
# gre-manager.sh – GRE Tunnel Manager for Truma
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'; NC='\033[0m'

# Base functions (if not defined in truma.sh)
if ! declare -f add_log >/dev/null 2>&1; then
    add_log() { echo "[gre] $1"; }
fi
if ! declare -f render >/dev/null 2>&1; then
    render() { clear; banner; }
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
    valid_octet() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 0 && $1 <= 255 )); }
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
        (( p >= 1 && p <= 65535 ))
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
        (( m >= 576 && m <= 1600 ))
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
if ! declare -f ensure_iproute_only >/dev/null 2>&1; then
    ensure_iproute_only() {
        add_log "Checking required package: iproute2"
        if command -v ip >/dev/null 2>&1; then
            add_log "iproute2 is already installed."
            return 0
        fi
        add_log "Installing missing package: iproute2"
        apt-get update -y >/dev/null 2>&1
        apt-get install -y iproute2 >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            add_log "iproute2 installed successfully."
            return 0
        else
            add_log "Failed to install iproute2."
            return 1
        fi
    }
fi

# GRE helper functions
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
# Main GRE functions
# =============================================================================

gre::create_interactive() {
    local side
    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Create GRE Tunnel${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
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
    echo -e "${YELLOW}GRE key (enter to auto-generate):${NC}"
    read -r -p "> " key
    if [[ -z "$key" ]]; then
        # استفاده از openssl rand به جای date +%N برای سازگاری بیشتر
        if command -v openssl &>/dev/null; then
            key=$(openssl rand -hex 2 | head -c4)  # 4 کاراکتر هگز = 16 بیت = 0-65535
            key=$((0x$key % 10000))  # تبدیل به عدد 4 رقمی
        else
            # fallback با استفاده از /dev/urandom
            key=$(od -An -N2 -i /dev/urandom | awk '{print $1 % 10000}')
        fi
        echo -e "\n${GREEN}🔧 Generated GRE key: ${CYAN}${key}${NC}"
        echo -e "${YELLOW}   (Press Enter to continue)${NC}"
        read -r
    else
        if ! [[ "$key" =~ ^[0-9]+$ ]] || (( key < 0 || key > 9999 )); then
            print_error "Invalid key. Must be a number between 0 and 9999."
            pause_enter
            return 1
        fi
    fi

    local MTU_VALUE=""

    ensure_iproute_only || { die_soft "Package installation failed (iproute2)."; return 0; }

    local unit="${name}.service"
    local path="/etc/systemd/system/${unit}"

    if [[ -f "$path" ]]; then
        add_log "Service already exists: $unit"
        pause_enter
        return 0
    fi

    local mtu_line=""
    if [[ -n "$MTU_VALUE" ]]; then
        mtu_line="ExecStart=/sbin/ip link set ${name} mtu ${MTU_VALUE}"
    fi

    cat >"$path" <<EOF
[Unit]
Description=GRE Tunnel ${name} to (${remote_ip})
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c "/sbin/ip tunnel del ${name} 2>/dev/null || true"
ExecStart=/sbin/ip tunnel add ${name} mode gre local ${local_ip} remote ${remote_ip} key ${key} nopmtudisc
ExecStart=/sbin/ip addr add ${local_tun_ip}/30 dev ${name}
${mtu_line}
ExecStart=/sbin/ip link set ${name} up
ExecStop=/sbin/ip link set ${name} down
ExecStop=/sbin/ip tunnel del ${name}

[Install]
WantedBy=multi-user.target
EOF

    add_log "Service created: $unit"
    systemctl daemon-reload
    systemctl enable --now "${name}.service" >/dev/null 2>&1 && add_log "Service started."

    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Tunnel '$name' created successfully (${side_name})${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo "  Local tunnel IP  : ${local_tun_ip}/30"
    echo "  Peer tunnel IP   : ${peer_tun_ip}"
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
    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${RED}  Uninstall GRE Tunnel${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo "This will remove:"
    echo "  - /etc/systemd/system/${name}.service"
    echo "  - ALL autostart symlinks (*.wants) for $name"
    echo "  - GRE interface + routes + neighbors + conntrack sessions"
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

    add_log "Stopping ${name}.service"
    systemctl stop "${name}.service" >/dev/null 2>&1 || true
    systemctl disable "${name}.service" >/dev/null 2>&1 || true

    add_log "Removing unit file and symlinks"
    rm -f "/etc/systemd/system/${name}.service"
    for d in /etc/systemd/system/*.wants /etc/systemd/system/*/*.wants; do
        rm -f "$d/${name}.service" >/dev/null 2>&1 || true
    done

    add_log "Flushing tunnel interface"
    ip route flush dev "$name" 2>/dev/null || true
    ip addr flush dev "$name" 2>/dev/null || true
    ip link set "$name" down 2>/dev/null || true
    ip tunnel del "$name" 2>/dev/null || true

    crontab -l 2>/dev/null | grep -v "/usr/local/bin/truma-restart-${name}.sh" | crontab - 2>/dev/null || true
    rm -f "/usr/local/bin/truma-restart-${name}.sh" "/usr/local/bin/truma-dummy-${name}.sh" 2>/dev/null || true
    systemctl stop "truma-dummy-${name}.service" 2>/dev/null || true
    systemctl disable "truma-dummy-${name}.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/truma-dummy-${name}.service" 2>/dev/null || true

    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true

    add_log "Uninstall completed for $name"
    pause_enter
}

gre::change_mtu() {
    local name="$1" mtu
    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Change MTU for GRE Tunnel${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    ask_until_valid "New MTU (576-1600):" valid_mtu mtu

    add_log "Setting MTU on interface $name to $mtu..."
    ip link set "$name" mtu "$mtu" >/dev/null 2>&1 || add_log "WARNING: $name interface not found or not up (will still patch unit)."

    local unit="/etc/systemd/system/${name}.service"
    if [[ ! -f "$unit" ]]; then
        die_soft "Unit file not found: $unit"
        return 0
    fi

    sed -i.bak "/ExecStart=\/sbin\/ip link set ${name} mtu/d" "$unit"
    sed -i "/ExecStart=\/sbin\/ip link set ${name} up/i ExecStart=/sbin/ip link set ${name} mtu ${mtu}" "$unit"

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