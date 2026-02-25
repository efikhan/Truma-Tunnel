#!/usr/bin/env bash
# =============================================================================
# gre-manager.sh – GRE Tunnel Engine (Fully compatible with Truma v2)
# Style: Beautiful menus like Paqet (yellow prompts, > input), no Change Local IP, no MTU prompt.
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'; NC='\033[0m'

# -----------------------------------------------------------------------------
# Base functions (if not defined in truma.sh)
# -----------------------------------------------------------------------------
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
if ! declare -f ask_ports >/dev/null 2>&1; then
    ask_ports() {
        local prompt="Forward ports (comma-separated):"
        local raw=""
        while true; do
            render
            echo -e "${YELLOW}${prompt}${NC}"
            read -r -e -p "> " raw
            raw="$(trim "$raw")"
            raw="${raw// /}"

            if [[ -z "$raw" ]]; then
                add_log "Empty ports. Please try again."
                continue
            fi

            local -a ports=()
            local ok=1
            IFS=',' read -r -a parts <<<"$raw"
            for part in "${parts[@]}"; do
                if valid_port "$part"; then
                    ports+=("$part")
                else
                    ok=0
                    break
                fi
            done

            if ((ok==0)); then
                add_log "Invalid ports: $raw"
                add_log "Enter comma-separated numbers only, e.g., 80,443,2053"
                continue
            fi

            PORT_LIST=($(printf "%s\n" "${ports[@]}" | awk '!seen[$0]++' | sort -n))
            add_log "Ports accepted: ${PORT_LIST[*]}"
            return 0
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
if ! declare -f ensure_packages >/dev/null 2>&1; then
    ensure_packages() {
        add_log "Checking required packages: iproute2, haproxy"
        local missing=()
        command -v ip >/dev/null 2>&1 || missing+=("iproute2")
        command -v haproxy >/dev/null 2>&1 || missing+=("haproxy")

        if ((${#missing[@]}==0)); then
            add_log "All required packages are installed."
            return 0
        fi

        add_log "Installing missing packages: ${missing[*]}"
        apt-get update -y >/dev/null 2>&1
        apt-get install -y "${missing[@]}" >/dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            add_log "Packages installed successfully."
            return 0
        else
            add_log "Failed to install packages."
            return 1
        fi
    }
fi

# -----------------------------------------------------------------------------
# GRE helper functions
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# HAProxy functions (full support)
# -----------------------------------------------------------------------------
haproxy_unit_exists() {
    systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -qx 'haproxy.service'
}

haproxy_ensure_override() {
    local override_dir="/etc/systemd/system/haproxy.service.d"
    local override_file="${override_dir}/override.conf"

    if [[ ! -f "$override_file" ]]; then
        add_log "Creating HAProxy systemd override for conf.d support..."
        mkdir -p "$override_dir"
        cat > "$override_file" <<'EOF'
[Service]
Environment="CONFIG=/etc/haproxy/haproxy.cfg"
Environment="PIDFILE=/run/haproxy.pid"
Environment="EXTRAOPTS=-S /run/haproxy-master.sock"
ExecStart=
ExecStart=/usr/sbin/haproxy -Ws -f $CONFIG -f /etc/haproxy/conf.d/ -p $PIDFILE $EXTRAOPTS
ExecReload=
ExecReload=/usr/sbin/haproxy -Ws -f $CONFIG -f /etc/haproxy/conf.d/ -c -q $EXTRAOPTS
EOF
        systemctl daemon-reload
        systemctl restart haproxy 2>/dev/null || true
        add_log "HAProxy override created and service restarted."
    else
        add_log "HAProxy override already exists."
    fi
}

haproxy_write_main_cfg() {
    add_log "Rebuilding /etc/haproxy/haproxy.cfg"
    rm -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1 || true
    cat >/etc/haproxy/haproxy.cfg <<'EOF'
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 200000

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client  1m
    timeout server  1m
EOF
}

haproxy_write_tunnel_cfg() {
    local name="$1" target_ip="$2"
    shift 2
    local -a ports=("$@")

    mkdir -p /etc/haproxy/conf.d >/dev/null 2>&1 || true
    local cfg="/etc/haproxy/conf.d/${name}.cfg"

    if [[ -f "$cfg" ]]; then
        add_log "ERROR: ${name}.cfg already exists."
        return 2
    fi

    add_log "Creating HAProxy config: $cfg"
    : >"$cfg" || return 1

    for p in "${ports[@]}"; do
        cat >>"$cfg" <<EOF
frontend ${name}_fe_${p}
    bind 0.0.0.0:${p}
    default_backend ${name}_be_${p}

backend ${name}_be_${p}
    option tcp-check
    server ${name}_b_${p} ${target_ip}:${p} check

EOF
    done
    return 0
}

haproxy_validate() {
    local tmp_log
    tmp_log="$(mktemp)"
    if haproxy -c -f /etc/haproxy/haproxy.cfg -f /etc/haproxy/conf.d/ >"$tmp_log" 2>&1; then
        add_log "HAProxy config validation passed."
        rm -f "$tmp_log"
        return 0
    else
        add_log "HAProxy config validation FAILED. Errors:"
        while IFS= read -r line; do
            add_log "  $line"
        done <"$tmp_log"
        rm -f "$tmp_log"
        return 1
    fi
}

haproxy_apply_and_show() {
    if ! systemctl is-active haproxy >/dev/null 2>&1; then
        add_log "Starting haproxy service..."
        systemctl enable haproxy --now 2>/dev/null || true
    fi
    haproxy_ensure_override
    systemctl restart haproxy >/dev/null 2>&1 || true
    render
    echo "---- STATUS (haproxy.service) ----"
    systemctl status haproxy --no-pager 2>&1 | sed -n '1,18p'
    echo "---------------------------------"
}

haproxy_add_ports_to_tunnel_cfg() {
    local name="$1" target_ip="$2"
    shift 2
    local -a ports=("$@")
    local cfg="/etc/haproxy/conf.d/${name}.cfg"

    if [[ ! -f "$cfg" ]]; then
        add_log "ERROR: Not found: $cfg"
        return 1
    fi

    add_log "Editing HAProxy config: $cfg"
    local p added=0 skipped=0
    for p in "${ports[@]}"; do
        if grep -qE "^frontend[[:space:]]+${name}_fe_${p}\b" "$cfg" 2>/dev/null; then
            add_log "Skip (exists): ${name} port ${p}"
            ((skipped++))
            continue
        fi

        cat >>"$cfg" <<EOF

frontend ${name}_fe_${p}
    bind 0.0.0.0:${p}
    default_backend ${name}_be_${p}

backend ${name}_be_${p}
    option tcp-check
    server ${name}_b_${p} ${target_ip}:${p} check
EOF
        add_log "Added: ${name} port ${p} -> ${target_ip}:${p}"
        ((added++))
    done

    add_log "Done. Added=${added}, Skipped=${skipped}"
    return 0
}

# =============================================================================
# Main GRE functions (beautiful menus like Paqet)
# =============================================================================

# -----------------------------------------------------------------------------
# Create new tunnel (no MTU prompt)
# -----------------------------------------------------------------------------
gre::create_interactive() {
    local side
    echo -e "\n${CYAN}${NC}"
    echo -e "${GREEN}  Create GRE Tunnel${NC}"
    echo -e "${CYAN}${NC}"
    echo "Select side:"
    echo "  1) Iran (with HAProxy)"
    echo "  2) Kharej (without HAProxy)"
    echo
    echo -e "${YELLOW}Choice [1-2]:${NC}"
    read -r -p "> " side
    side="$(trim "$side")"
    if [[ "$side" != "1" && "$side" != "2" ]]; then
        add_log "Invalid side selected."
        pause_enter
        return 0
    fi

    local name remote_ip local_ip base_net
    ask_until_valid "Tunnel name (letters, numbers, _ - only):" valid_tunnel_name name

    local_ip=$(ip -4 route get 1 | awk '{print $7; exit}' 2>/dev/null)
    if [[ -z "$local_ip" ]]; then
        local_ip=$(hostname -I | awk '{print $1}')
    fi
    render
    echo "Detected your local IP: $local_ip"
    echo -e "${YELLOW}Is this correct? (y/n)${NC}"
    read -r -p "> " confirm
    confirm="$(trim "$confirm")"
    if [[ "$confirm" =~ ^[Nn] ]]; then
        ask_until_valid "Enter correct local IP:" valid_ipv4 local_ip
    else
        add_log "Local IP confirmed: $local_ip"
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

    local key=$(($(date +%s%N | cut -b1-6) % 10000))
    echo -e "\n${GREEN} Generated GRE key: ${CYAN}${key}${NC}"
    echo -e "${YELLOW}   (Press Enter to continue)${NC}"
    read -r

    # MTU not asked, always default (none)
    local MTU_VALUE=""

    if [[ "$side" == "1" ]]; then
        ensure_packages || { die_soft "Package installation failed."; return 0; }
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable haproxy --now 2>/dev/null || true
        haproxy_ensure_override
    else
        ensure_iproute_only || { die_soft "Package installation failed (iproute2)."; return 0; }
    fi

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

    if [[ "$side" == "1" ]]; then
        PORT_LIST=()
        ask_ports
        add_log "Writing HAProxy config for $name..."
        haproxy_write_tunnel_cfg "$name" "$peer_tun_ip" "${PORT_LIST[@]}"
        local hrc=$?
        if [[ $hrc -eq 2 ]]; then
            die_soft "${name}.cfg already exists."
            return 0
        elif [[ $hrc -ne 0 ]]; then
            die_soft "Failed writing HAProxy config."
            return 0
        fi

        haproxy_write_main_cfg

        if command -v haproxy >/dev/null 2>&1; then
            if ! haproxy_validate; then
                die_soft "HAProxy config validation failed."
                return 0
            fi
        fi

        haproxy_apply_and_show || { die_soft "Failed applying HAProxy systemd override."; return 0; }

        echo -e "\n${GREEN}${NC}"
        echo -e "${GREEN}  Tunnel '$name' created successfully (Iran side)${NC}"
        echo -e "${GREEN}${NC}"
        echo "  Local tunnel IP  : ${local_tun_ip}/30"
        echo "  Peer tunnel IP   : ${peer_tun_ip}"
        echo "  Forwarded ports  : ${PORT_LIST[*]}"
    else
        echo -e "\n${GREEN}${NC}"
        echo -e "${GREEN}  Tunnel '$name' created successfully (Kharej side)${NC}"
        echo -e "${GREEN}${NC}"
        echo "  Local tunnel IP  : ${local_tun_ip}/30"
        echo "  Peer tunnel IP   : ${peer_tun_ip}"
    fi

    echo
    echo -e "${CYAN}---- Tunnel Service Status ----${NC}"
    systemctl --no-pager --full status "${name}.service" 2>&1 | head -12
    pause_enter
}

# -----------------------------------------------------------------------------
# List forwarded ports
# -----------------------------------------------------------------------------
gre::list_ports() {
    local name="$1"
    local cfg="/etc/haproxy/conf.d/${name}.cfg"
    if [[ ! -f "$cfg" ]]; then
        print_info "No HAProxy config found for tunnel '$name'"
        return 0
    fi

    echo "Forwarded ports for GRE tunnel '$name':"
    local ports=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^frontend[[:space:]]+${name}_fe_([0-9]+) ]]; then
            ports+=("${BASH_REMATCH[1]}")
        fi
    done < "$cfg"

    if [[ ${#ports[@]} -eq 0 ]]; then
        echo "  (no ports configured)"
    else
        for p in "${ports[@]}"; do
            echo "  - $p"
        done
    fi
}

# -----------------------------------------------------------------------------
# Add port to tunnel
# -----------------------------------------------------------------------------
gre::add_port_interactive() {
    local name="$1"
    echo -e "\n${CYAN}${NC}"
    echo -e "${GREEN}  Add Port to GRE Tunnel${NC}"
    echo -e "${CYAN}${NC}"
    add_log "Selected: add tunnel port"

    local cidr
    cidr="$(get_tunnel_local_ip_cidr "$name")"
    if [[ -z "$cidr" ]]; then
        die_soft "Could not detect IP on $name. Is it up and has an IP?"
        return 0
    fi

    local peer_ip
    peer_ip="$(get_peer_ip_from_local_cidr "$cidr")"
    add_log "Detected: $name local=$cidr | peer=$peer_ip"

    PORT_LIST=()
    ask_ports

    haproxy_add_ports_to_tunnel_cfg "$name" "$peer_ip" "${PORT_LIST[@]}" || { die_soft "Failed editing ${name}.cfg"; return 0; }

    if command -v haproxy >/dev/null 2>&1; then
        if ! haproxy_validate; then
            die_soft "HAProxy config validation failed."
            return 0
        fi
    fi

    if systemctl is-active haproxy >/dev/null 2>&1; then
        add_log "Restarting HAProxy..."
        systemctl restart haproxy >/dev/null 2>&1 || true
        add_log "HAProxy restarted."
    else
        add_log "WARNING: haproxy.service not active; skipping restart."
    fi

    echo -e "\n${GREEN}${NC}"
    echo -e "${GREEN}  Ports added to $name successfully${NC}"
    echo -e "${GREEN}${NC}"
    echo "  Local CIDR : ${cidr}"
    echo "  Peer IP    : ${peer_ip}"
    echo "  Ports added: ${PORT_LIST[*]}"
    echo
    echo -e "${CYAN}---- HAProxy Service Status ----${NC}"
    systemctl status haproxy --no-pager 2>&1 | head -12
    pause_enter
}

# -----------------------------------------------------------------------------
# Remove a port from tunnel
# -----------------------------------------------------------------------------
gre::remove_port_interactive() {
    local name="$1"
    echo -e "\n${CYAN}${NC}"
    echo -e "${GREEN}  Remove Port from GRE Tunnel${NC}"
    echo -e "${CYAN}${NC}"
    gre::list_ports "$name"
    echo ""
    echo -e "${YELLOW}Enter port to remove:${NC}"
    read -r -p "> " port
    port="$(trim "$port")"
    if [[ -z "$port" ]] || ! valid_port "$port"; then
        print_error "Invalid port"
        pause_enter
        return 1
    fi

    local cfg="/etc/haproxy/conf.d/${name}.cfg"
    if [[ ! -f "$cfg" ]]; then
        print_error "HAProxy config for '$name' not found"
        pause_enter
        return 1
    fi

    # Extract current ports
    local ports=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^frontend[[:space:]]+${name}_fe_([0-9]+) ]]; then
            ports+=("${BASH_REMATCH[1]}")
        fi
    done < "$cfg"

    local found=0 new_ports=()
    for p in "${ports[@]}"; do
        if [[ "$p" == "$port" ]]; then
            found=1
        else
            new_ports+=("$p")
        fi
    done

    if [[ $found -eq 0 ]]; then
        print_error "Port $port not found"
        pause_enter
        return 1
    fi

    # Extract target_ip from config (backend server)
    local target_ip
    target_ip=$(awk -v name="$name" '/^backend '"${name}"'_be_/ { in_backend=1 } in_backend && /^ *server / { split($3, a, ":"); print a[1]; exit }' "$cfg")
    if [[ -z "$target_ip" ]]; then
        target_ip=$(awk '/^ *server / { split($3, a, ":"); print a[1]; exit }' "$cfg")
    fi

    # Rewrite config with new ports
    local tmp
    tmp=$(mktemp)
    for p in "${new_ports[@]}"; do
        cat >>"$tmp" <<EOF
frontend ${name}_fe_${p}
    bind 0.0.0.0:${p}
    default_backend ${name}_be_${p}

backend ${name}_be_${p}
    option tcp-check
    server ${name}_b_${p} ${target_ip}:${p} check

EOF
    done

    if haproxy -c -f "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$cfg"
        add_log "Removed port $port from $name"
        if systemctl is-active haproxy >/dev/null 2>&1; then
            systemctl restart haproxy >/dev/null 2>&1 || true
        fi
        print_success "Port $port removed."
    else
        print_error "New config validation failed"
        rm -f "$tmp"
    fi
    pause_enter
}

# -----------------------------------------------------------------------------
# Complete tunnel removal
# -----------------------------------------------------------------------------
gre::remove() {
    local name="$1"
    echo -e "\n${CYAN}${NC}"
    echo -e "${RED}  Uninstall GRE Tunnel${NC}"
    echo -e "${CYAN}${NC}"
    echo "This will remove:"
    echo "  - /etc/systemd/system/${name}.service"
    echo "  - ALL autostart symlinks (*.wants) for $name"
    echo "  - /etc/haproxy/conf.d/${name}.cfg (if exists)"
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

    add_log "Removing HAProxy config for $name"
    rm -f "/etc/haproxy/conf.d/${name}.cfg" >/dev/null 2>&1 || true

    # Remove anti-filter components (with truma name)
    crontab -l 2>/dev/null | grep -v "/usr/local/bin/truma-restart-${name}.sh" | crontab - 2>/dev/null || true
    rm -f "/usr/local/bin/truma-restart-${name}.sh" "/usr/local/bin/truma-dummy-${name}.sh" 2>/dev/null || true
    systemctl stop "truma-dummy-${name}.service" 2>/dev/null || true
    systemctl disable "truma-dummy-${name}.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/truma-dummy-${name}.service" 2>/dev/null || true

    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true

    if systemctl list-unit-files --no-legend 2>/dev/null | grep -q haproxy.service; then
        if command -v haproxy >/dev/null 2>&1; then
            haproxy_validate
        fi
        systemctl restart haproxy >/dev/null 2>&1 || true
    fi

    add_log "Uninstall completed for $name"
    pause_enter
}

# -----------------------------------------------------------------------------
# Change MTU (only from main menu)
# -----------------------------------------------------------------------------
gre::change_mtu() {
    local name="$1" mtu
    echo -e "\n${CYAN}${NC}"
    echo -e "${GREEN}  Change MTU for GRE Tunnel${NC}"
    echo -e "${CYAN}${NC}"
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

# -----------------------------------------------------------------------------
# Anti-filter functions (disabled, only for compatibility with truma.sh)
# -----------------------------------------------------------------------------
gre::setup_antifilter() {
    print_info "Anti-filter is disabled in this version."
    pause_enter
}
gre::remove_antifilter() {
    print_info "Anti-filter is disabled in this version."
    pause_enter
}

# -----------------------------------------------------------------------------
# End of file – change_local_ip_interactive completely removed
# -----------------------------------------------------------------------------