#!/usr/bin/env bash
# =============================================================================
# paqet.sh – Paqet Engine (v1.0.0-alpha.17 compatible)
# Refactored with simple read functions (like GRE) and beautiful menus.
# Fixed: readonly variables now checked before declaration.
# Fixed: list_ports now correctly extracts ports from YAML.
# Improved: remove function deletes everything thoroughly (like manual commands).
# Now supports both paqet-* and paqet@* service names.
# =============================================================================

set -euo pipefail

: "${MIN_MTU:=576}"
: "${MAX_MTU_GLOBAL:=9000}"
: "${MAX_TUNNEL_NAME_LEN:=64}"
: "${NONINTERACTIVE:=0}"
export NONINTERACTIVE

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

if ! declare -p PAQET_BIN &>/dev/null; then
    readonly PAQET_BIN="/usr/local/bin/paqet"
fi
if ! declare -p PAQET_CONFIG_DIR &>/dev/null; then
    readonly PAQET_CONFIG_DIR="/etc/paqet-tunnel/instances"
fi
if ! declare -p PAQET_SYSTEMD_DIR &>/dev/null; then
    readonly PAQET_SYSTEMD_DIR="/etc/systemd/system"
fi
if ! declare -p PAQET_FW_DIR &>/dev/null; then
    readonly PAQET_FW_DIR="/etc/paqet-tunnel/firewall"
fi
if ! declare -p PAQET_DATA_DIR &>/dev/null; then
    readonly PAQET_DATA_DIR="/var/lib/paqet-tunnel"
fi
if ! declare -p PAQET_LOG_FILE &>/dev/null; then
    readonly PAQET_LOG_FILE="/var/log/paqet-tunnel.log"
fi
if ! declare -p BUNDLED_BIN_DIR &>/dev/null; then
    readonly BUNDLED_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/bin" 2>/dev/null && pwd || echo "/dev/null")"
fi

PAQET_DEBUG=${PAQET_DEBUG:-0}
FORCE=${FORCE:-0}

mkdir -p "$(dirname "$PAQET_LOG_FILE")" "$PAQET_CONFIG_DIR" "$PAQET_FW_DIR" "$PAQET_DATA_DIR"
touch "$PAQET_LOG_FILE" 2>/dev/null || true

trim() {
    local v="$*"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    printf '%s' "$v"
}
is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }

if ! declare -f valid_mtu_global >/dev/null 2>&1; then
    valid_mtu_global() {
        local m="$1"
        is_int "$m" || return 1
        (( m >= MIN_MTU && m <= MAX_MTU_GLOBAL ))
    }
fi
if ! declare -f valid_port >/dev/null 2>&1; then
    valid_port() { is_int "$1" && (( $1 >= 1 && $1 <= 65535 )); }
fi
if ! declare -f valid_mac >/dev/null 2>&1; then
    valid_mac() { [[ "$1" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; }
fi
if ! declare -f valid_ipv4 >/dev/null 2>&1; then
    valid_ipv4() {
        [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
        IFS='.' read -r a b c d <<<"$1"
        ((a<=255 && b<=255 && c<=255 && d<=255))
    }
fi

_dbg() {
    if [[ "${PAQET_DEBUG}" == "1" ]]; then
        printf "[paqet-debug] %s\n" "$1" >&2
    fi
    printf "[paqet] %s - DEBUG: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$PAQET_LOG_FILE"
}
_paqet::log()  { printf "[paqet] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$PAQET_LOG_FILE"; }
_paqet::info() { printf "%s\n" "$1" >&2; _paqet::log "$1"; }
_paqet::error(){ printf "ERROR: %s\n" "$1" >&2; printf "[paqet] %s - ERROR: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$PAQET_LOG_FILE"; return 1; }
_paqet::ensure_root(){ [[ $EUID -eq 0 ]] || { _paqet::error "Root required."; return 1; }; }

_paqet::detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *)       echo "$arch" ;;
    esac
}
_paqet::get_default_interface() {
    ip route | awk '/default/ {print $5; exit}' || echo "eth0"
}
_paqet::get_gateway_ip() {
    ip route | awk '/default/ {print $3; exit}' || true
}
_paqet::get_gateway_mac() {
    local gateway_ip=$(_paqet::get_gateway_ip)
    [[ -z "$gateway_ip" ]] && return 1
    local mac
    mac=$(ip neigh show "$gateway_ip" 2>/dev/null | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -1)
    if [[ -z "$mac" ]] && command -v arp >/dev/null; then
        mac=$(arp -n "$gateway_ip" 2>/dev/null | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -1)
    fi
    printf '%s' "$mac"
}
get_local_ip() {
    ip -4 route get 1 2>/dev/null | awk '{print $7; exit}' || hostname -I | awk '{print $1}'
}

_paqet::save_iptables() {
    if command -v iptables-save &>/dev/null; then
        if [ -d /etc/iptables ]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        elif [ -f /etc/sysconfig/iptables ]; then
            iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
        fi
    fi
}

paqet::install() {
    _paqet::ensure_root || return 1
    if [[ -x "$PAQET_BIN" && "${FORCE:-0}" -ne 1 ]]; then
        _paqet::log "paqet already installed: $PAQET_BIN"
        return 0
    fi

    local arch=$(_paqet::detect_arch)
    local bundled="${BUNDLED_BIN_DIR}/paqet-linux-${arch}"
    if [[ -x "$bundled" ]]; then
        install -m 0755 "$bundled" "$PAQET_BIN"
        _paqet::log "Installed paqet from bundled binary."
        return 0
    fi

    local version="1.0.0-alpha.17"
    local asset="paqet-linux-${arch}-v${version}.tar.gz"
    local url="https://github.com/hanselime/paqet/releases/download/v${version}/${asset}"

    local archivedir="/root/paqet"
    if [[ -d "$archivedir" ]]; then
        local archive_file
        archive_file=$(ls -1 "$archivedir"/*.tar.gz 2>/dev/null | head -1 || true)
        if [[ -n "$archive_file" && -f "$archive_file" ]]; then
            mkdir -p /tmp/paqet-extract
            if tar -xzf "$archive_file" -C /tmp/paqet-extract 2>/dev/null; then
                local bin_path
                bin_path=$(find /tmp/paqet-extract -type f -name "paqet" -print -quit 2>/dev/null)
                if [[ -n "$bin_path" ]]; then
                    chmod +x "$bin_path"
                    mv "$bin_path" "$PAQET_BIN"
                    rm -rf /tmp/paqet-extract
                    _paqet::log "Installed from local archive: $archive_file"
                    return 0
                fi
            fi
            rm -rf /tmp/paqet-extract
        fi
    fi

    _paqet::log "Downloading paqet v${version}..."
    if ! curl -fsSL --max-time 20 -o /tmp/paqet.tar.gz "$url"; then
        _paqet::error "Download failed. Provide a local binary in repo/bin or /root/paqet/"
        return 1
    fi

    mkdir -p /tmp/paqet-extract
    if ! tar -xzf /tmp/paqet.tar.gz -C /tmp/paqet-extract; then
        _paqet::error "Extraction failed."
        rm -f /tmp/paqet.tar.gz
        return 1
    fi

    local binary
    binary=$(find /tmp/paqet-extract -type f -name "paqet" -print -quit 2>/dev/null)
    [[ -z "$binary" ]] && binary=$(find /tmp/paqet-extract -type f -executable -name "*paqet*" -print -quit 2>/dev/null)

    if [[ -z "$binary" ]]; then
        _paqet::error "Binary not found in archive."
        ls -lR /tmp/paqet-extract >&2
        return 1
    fi

    chmod +x "$binary"
    mv "$binary" "$PAQET_BIN"
    rm -rf /tmp/paqet*
    _paqet::log "paqet v${version} installed successfully."
    return 0
}

paqet::generate_key() { openssl rand -hex 32; }

paqet::write_config() {
    local name="$1" role="$2" remote_ip="$3" port="$4" key="$5" mtu="$6"
    local mode="$7" public_ip="${8:-}" router_mac="${9:-}"
    shift 9
    local -a forwarded_ports=("$@")

    [[ -n "$name" && -n "$role" && -n "$port" && -n "$key" && -n "$mtu" && -n "$mode" ]] || {
        _paqet::error "Missing required parameters for write_config"
        return 1
    }

    if [[ "$role" == "client" ]]; then
        [[ -n "$remote_ip" ]] || { _paqet::error "Client requires remote_ip."; return 1; }
    else
        [[ -n "$public_ip" ]] || { _paqet::error "Server requires public_ip."; return 1; }
        [[ -n "$router_mac" ]] || { _paqet::error "Server requires router_mac."; return 1; }
    fi

    mkdir -p "$PAQET_CONFIG_DIR"
    local config_file="${PAQET_CONFIG_DIR}/${name}.yaml"

    local iface=$(_paqet::get_default_interface)
    [[ -n "$iface" ]] || { _paqet::error "Could not detect default interface."; return 1; }

    local local_ip=""
    if [[ "$role" == "client" ]]; then
        local_ip=$(get_local_ip)
        [[ -n "$local_ip" ]] || { _paqet::error "Could not detect local IP."; return 1; }
    fi

    {
        echo "role: ${role}"
        echo "log:"
        echo "  level: info"

        if [[ "$role" == "client" && ${#forwarded_ports[@]} -gt 0 ]]; then
            echo "forward:"
            for p in "${forwarded_ports[@]}"; do
                echo "  - listen: \"0.0.0.0:${p}\""
                echo "    target: \"127.0.0.1:${p}\""
                echo "    protocol: tcp"
            done
        fi

        echo "network:"
        echo "  interface: \"${iface}\""
        echo "  ipv4:"
        if [[ "$role" == "client" ]]; then
            echo "    addr: \"${local_ip}:0\""
        else
            echo "    addr: \"${public_ip}:${port}\""
        fi
        if [[ -n "$router_mac" ]]; then
            echo "    router_mac: \"${router_mac}\""
        fi
        echo "  tcp:"
        echo "    local_flag: [\"PA\"]"
        echo "    remote_flag: [\"PA\"]"

        if [[ "$role" == "client" ]]; then
            echo "server:"
            echo "  addr: \"${remote_ip}:${port}\""
        else
            echo "listen:"
            echo "  addr: \"0.0.0.0:${port}\""
        fi

        echo "transport:"
        echo "  protocol: kcp"
        echo "  conn: 2"
        echo "  kcp:"
        echo "    mode: \"${mode}\""
        echo "    block: \"aes\""
        echo "    key: \"${key}\""
        echo "    mtu: ${mtu}"
        echo "    dshard: 10"
        echo "    pshard: 3"
    } > "$config_file"

    _paqet::log "Config for '$name' written: $config_file"
    return 0
}

paqet::create_service() {
    local name="$1"
    local service_name="paqet-${name}"
    local service_file="${PAQET_SYSTEMD_DIR}/${service_name}.service"
    local config_file="${PAQET_CONFIG_DIR}/${name}.yaml"

    [[ -f "$config_file" ]] || { _paqet::error "Config file for '$name' not found."; return 1; }
    mkdir -p "$PAQET_DATA_DIR"

    local tmp
    tmp=$(mktemp) || { _paqet::error "mktemp failed"; return 1; }
    cat >"$tmp" <<EOF
[Unit]
Description=Paqet Tunnel Instance ${name}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/bin/mkdir -p ${PAQET_DATA_DIR}
ExecStart=${PAQET_BIN} run -c "${config_file}"
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=120
StartLimitBurst=5
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
StandardOutput=journal
StandardError=journal
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
ReadWritePaths=${PAQET_DATA_DIR}
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN

[Install]
WantedBy=multi-user.target
EOF

    install -m 0644 "$tmp" "$service_file" || {
        _paqet::error "Failed to install unit file"
        rm -f "$tmp"
        return 1
    }
    rm -f "$tmp"

    systemctl daemon-reload
    if systemctl enable --now "$service_name" 2>&1 | tee -a "$PAQET_LOG_FILE"; then
        _paqet::log "Service created and started: $service_name"
        return 0
    else
        _paqet::error "Failed to enable/start service $service_name"
        return 1
    fi
}

paqet::create_firewall_service() {
    local name="$1" role="$2" target_ip="$3" port="$4"
    mkdir -p "$PAQET_FW_DIR"
    local fw_script="${PAQET_FW_DIR}/fw-${name}.sh"
    local fw_service_name="paqet-fw-${name}"
    local fw_service_file="${PAQET_SYSTEMD_DIR}/${fw_service_name}.service"

    cat > "$fw_script" <<EOF
#!/bin/bash
case "\$1" in
    start)
        if [[ "${role}" == "client" ]]; then
            iptables -t raw -C OUTPUT -p tcp -d ${target_ip} --dport ${port} -j NOTRACK 2>/dev/null || iptables -t raw -A OUTPUT -p tcp -d ${target_ip} --dport ${port} -j NOTRACK
            iptables -t raw -C PREROUTING -p tcp -s ${target_ip} --sport ${port} -j NOTRACK 2>/dev/null || iptables -t raw -A PREROUTING -p tcp -s ${target_ip} --sport ${port} -j NOTRACK
            iptables -t mangle -C PREROUTING -p tcp -s ${target_ip} --sport ${port} --tcp-flags RST RST -j DROP 2>/dev/null || iptables -t mangle -A PREROUTING -p tcp -s ${target_ip} --sport ${port} --tcp-flags RST RST -j DROP
        else
            iptables -t raw -C PREROUTING -p tcp --dport ${port} -j NOTRACK 2>/dev/null || iptables -t raw -A PREROUTING -p tcp --dport ${port} -j NOTRACK
            iptables -t raw -C OUTPUT -p tcp --sport ${port} -j NOTRACK 2>/dev/null || iptables -t raw -A OUTPUT -p tcp --sport ${port} -j NOTRACK
            iptables -t mangle -C OUTPUT -p tcp --sport ${port} --tcp-flags RST RST -j DROP 2>/dev/null || iptables -t mangle -A OUTPUT -p tcp --sport ${port} --tcp-flags RST RST -j DROP
            iptables -t mangle -C PREROUTING -p tcp --dport ${port} --tcp-flags RST RST -j DROP 2>/dev/null || iptables -t mangle -A PREROUTING -p tcp --dport ${port} --tcp-flags RST RST -j DROP
        fi
        ;;
    stop)
        if [[ "${role}" == "client" ]]; then
            iptables -t raw -C OUTPUT -p tcp -d ${target_ip} --dport ${port} -j NOTRACK 2>/dev/null && iptables -t raw -D OUTPUT -p tcp -d ${target_ip} --dport ${port} -j NOTRACK
            iptables -t raw -C PREROUTING -p tcp -s ${target_ip} --sport ${port} -j NOTRACK 2>/dev/null && iptables -t raw -D PREROUTING -p tcp -s ${target_ip} --sport ${port} -j NOTRACK
            iptables -t mangle -C PREROUTING -p tcp -s ${target_ip} --sport ${port} --tcp-flags RST RST -j DROP 2>/dev/null && iptables -t mangle -D PREROUTING -p tcp -s ${target_ip} --sport ${port} --tcp-flags RST RST -j DROP
        else
            iptables -t raw -C PREROUTING -p tcp --dport ${port} -j NOTRACK 2>/dev/null && iptables -t raw -D PREROUTING -p tcp --dport ${port} -j NOTRACK
            iptables -t raw -C OUTPUT -p tcp --sport ${port} -j NOTRACK 2>/dev/null && iptables -t raw -D OUTPUT -p tcp --sport ${port} -j NOTRACK
            iptables -t mangle -C OUTPUT -p tcp --sport ${port} --tcp-flags RST RST -j DROP 2>/dev/null && iptables -t mangle -D OUTPUT -p tcp --sport ${port} --tcp-flags RST RST -j DROP
            iptables -t mangle -C PREROUTING -p tcp --dport ${port} --tcp-flags RST RST -j DROP 2>/dev/null && iptables -t mangle -D PREROUTING -p tcp --dport ${port} --tcp-flags RST RST -j DROP
        fi
        ;;
    *)
        echo "Usage: \$0 {start|stop}"; exit 1 ;;
esac
EOF

    chmod +x "$fw_script"

    cat > "$fw_service_file" <<EOF
[Unit]
Description=Firewall rules for Paqet tunnel ${name}
BindsTo=paqet-${name}.service
After=paqet-${name}.service
PartOf=paqet-${name}.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${fw_script} start
ExecStop=${fw_script} stop

[Install]
WantedBy=paqet-${name}.service
EOF

    systemctl daemon-reload
    systemctl enable --now "$fw_service_name" 2>/dev/null || true
    _paqet::save_iptables
    _paqet::log "Firewall service created: ${fw_service_file}"
    return 0
}

paqet::start() {
    local name="$1"
    _ensure_cmd systemctl systemd 2>/dev/null || return 1
    systemctl start "paqet-${name}.service" && _paqet::log "Tunnel '${name}' started." || _paqet::error "Failed to start '${name}'."
}
paqet::stop() {
    local name="$1"
    _ensure_cmd systemctl systemd 2>/dev/null || return 1
    systemctl stop "paqet-${name}.service" && _paqet::log "Tunnel '${name}' stopped." || _paqet::error "Failed to stop '${name}'."
}
paqet::restart() {
    local name="$1"
    _ensure_cmd systemctl systemd 2>/dev/null || return 1
    systemctl restart "paqet-${name}.service" && _paqet::log "Tunnel '${name}' restarted." || _paqet::error "Failed to restart '${name}'."
}
paqet::status() {
    local name="$1"
    _ensure_cmd systemctl systemd 2>/dev/null || return 1
    systemctl status "paqet-${name}.service" --no-pager -l
}

# =============================================================================
# Improved add_ports: uses grep -oP to extract existing ports, then rebuilds forward section.
# =============================================================================
paqet::add_ports() {
    local name="$1"; shift
    local -a new_ports=("$@")
    local config_file="${PAQET_CONFIG_DIR}/${name}.yaml"

    [[ -f "$config_file" ]] || { _paqet::error "Config file for $name not found."; return 1; }

    local role
    role=$(grep "^role:" "$config_file" | awk '{print $2}' | tr -d '"')
    [[ "$role" == "client" ]] || { _paqet::error "Only client tunnels can forward ports."; return 1; }

    # Extract existing ports using grep -oP (more robust)
    local current_ports=()
    while IFS= read -r port; do
        current_ports+=("$port")
    done < <(grep -oP 'listen: "\d+\.\d+\.\d+\.\d+:\K\d+' "$config_file")

    local all_ports=("${current_ports[@]}" "${new_ports[@]}")
    local unique_ports=(); local seen=""
    for port in "${all_ports[@]}"; do
        if [[ ! " $seen " =~ " $port " ]]; then
            unique_ports+=("$port")
            seen="$seen $port"
        fi
    done

    local forward_block="forward:"
    for port in "${unique_ports[@]}"; do
        forward_block+=$'\n'"  - listen: \"0.0.0.0:${port}\""
        forward_block+=$'\n'"    target: \"127.0.0.1:${port}\""
        forward_block+=$'\n'"    protocol: tcp"
    done

    local tmp_file="${config_file}.tmp"
    if grep -q "^forward:" "$config_file"; then
        awk -v new_forward="$forward_block" '
            /^forward:/ { in_forward=1; print new_forward; next }
            in_forward && /^[^[:space:]]/ { in_forward=0 }
            !in_forward { print }
        ' "$config_file" > "$tmp_file"
    else
        cp "$config_file" "$tmp_file"
        echo "" >> "$tmp_file"
        echo "$forward_block" >> "$tmp_file"
    fi

    if [[ ! -s "$tmp_file" ]]; then
        _paqet::error "Generated config is empty. Aborting."
        rm -f "$tmp_file"
        return 1
    fi

    mv "$tmp_file" "$config_file"
    _paqet::log "Forward ports updated: ${unique_ports[*]}"

    if systemctl restart "paqet-${name}.service" 2>&1 | tee -a "$PAQET_LOG_FILE"; then
        _paqet::log "Service restarted successfully."
        return 0
    else
        _paqet::error "Failed to restart service after adding ports."
        journalctl -u "paqet-${name}.service" -n 10 --no-pager >&2
        return 1
    fi
}

paqet::add_port_interactive() {
    local name="$1"
    if [[ -z "$name" ]]; then _paqet::error "Usage: paqet::add_port_interactive <name>"; return 1; fi
    echo -e "${CYAN}Enter ports to add (comma-separated):${NC}"
    read -r -p "> " ports_input
    IFS=',' read -r -a ports <<< "$ports_input"
    for i in "${!ports[@]}"; do ports[$i]="$(trim "${ports[$i]}")"; done
    paqet::add_ports "$name" "${ports[@]}"
}

# =============================================================================
# Fixed list_ports: uses grep -oP
# =============================================================================
paqet::list_ports() {
    local name="$1"
    local config_file="${PAQET_CONFIG_DIR}/${name}.yaml"
    [[ -f "$config_file" ]] || { _paqet::error "Config file not found: $config_file"; return 1; }

    local role
    role=$(grep "^role:" "$config_file" | awk '{print $2}' | tr -d '"')
    if [[ "$role" != "client" ]]; then
        echo "No forwarded ports (server mode)."
        return 0
    fi

    echo -e "${CYAN}Forwarded ports for $name:${NC}"
    local ports_found=0
    while IFS= read -r port; do
        echo "  - $port"
        ports_found=1
    done < <(grep -oP 'listen: "\d+\.\d+\.\d+\.\d+:\K\d+' "$config_file")

    if [[ $ports_found -eq 0 ]]; then
        echo "  (no ports configured)"
    fi
    return 0
}

# =============================================================================
# Fixed remove_port: uses grep -oP to get current ports
# =============================================================================
paqet::remove_port() {
    local name="$1" port_to_remove="$2"
    local config_file="${PAQET_CONFIG_DIR}/${name}.yaml"
    [[ -f "$config_file" ]] || { _paqet::error "Config file not found: $config_file"; return 1; }

    local role
    role=$(grep "^role:" "$config_file" | awk '{print $2}' | tr -d '"')
    [[ "$role" == "client" ]] || { _paqet::error "Only client tunnels can forward ports."; return 1; }

    local current_ports=()
    while IFS= read -r port; do
        current_ports+=("$port")
    done < <(grep -oP 'listen: "\d+\.\d+\.\d+\.\d+:\K\d+' "$config_file")

    local new_ports=()
    local found=0
    for p in "${current_ports[@]}"; do
        if [[ "$p" == "$port_to_remove" ]]; then
            found=1
            continue
        fi
        new_ports+=("$p")
    done

    if [[ $found -eq 0 ]]; then
        _paqet::error "Port $port_to_remove not found in config."
        return 1
    fi

    local forward_block="forward:"
    for p in "${new_ports[@]}"; do
        forward_block+=$'\n'"  - listen: \"0.0.0.0:${p}\""
        forward_block+=$'\n'"    target: \"127.0.0.1:${p}\""
        forward_block+=$'\n'"    protocol: tcp"
    done

    local tmp_file="${config_file}.tmp"
    awk -v new_forward="$forward_block" '
        /^forward:/ { in_forward=1; print new_forward; next }
        in_forward && /^[^[:space:]]/ { in_forward=0 }
        !in_forward { print }
    ' "$config_file" > "$tmp_file" || { rm -f "$tmp_file"; _paqet::error "Failed to edit config"; return 1; }

    mv "$tmp_file" "$config_file"
    _paqet::log "Removed port $port_to_remove from $name"

    if systemctl restart "paqet-${name}.service" 2>&1 | tee -a "$PAQET_LOG_FILE"; then
        _paqet::log "Service restarted after port removal."
        return 0
    else
        _paqet::error "Failed to restart service after port removal."
        return 1
    fi
}

paqet::remove_port_interactive() {
    local name="$1"
    paqet::list_ports "$name" || return 1
    echo ""
    echo -e "${CYAN}Enter port to remove:${NC}"
    read -r -p "> " port
    port="$(trim "$port")"
    if [[ -z "$port" ]] || ! valid_port "$port"; then
        _paqet::error "Invalid port."
        return 1
    fi
    paqet::remove_port "$name" "$port"
}

paqet::change_mode() {
    local name="$1" new_mode="$2"
    local config_file="${PAQET_CONFIG_DIR}/${name}.yaml"
    [[ -f "$config_file" ]] || { _paqet::error "Config file not found: $config_file"; return 1; }

    if grep -q '^[[:space:]]*mode:' "$config_file"; then
        sed -i.bak -E "s/^([[:space:]]*mode:)[[:space:]]*\".*\"/\1 \"$new_mode\"/" "$config_file"
    else
        _paqet::error "No mode line found in config."
        return 1
    fi

    _paqet::log "Changed mode of $name to $new_mode"

    if systemctl restart "paqet-${name}.service" 2>&1 | tee -a "$PAQET_LOG_FILE"; then
        _paqet::log "Service restarted after mode change."
        return 0
    else
        _paqet::error "Failed to restart service after mode change."
        return 1
    fi
}

paqet::change_mode_interactive() {
    local name="$1"
    echo -e "\n${CYAN}Select new KCP mode:${NC}"
    echo "  1) fast   – Balanced speed, low latency"
    echo "  2) fast2  – Higher speed, lower latency (recommended)"
    echo "  3) fast3  – Maximum speed, aggressive, may be unstable"
    echo "  4) normal – Conservative, like TCP"
    echo "  5) manual – Advanced manual settings"
    read -r -p "Choice [1-5]: " mode_choice
    mode_choice="$(trim "$mode_choice")"

    local new_mode=""
    case "$mode_choice" in
        1) new_mode="fast" ;;
        2) new_mode="fast2" ;;
        3) new_mode="fast3" ;;
        4) new_mode="normal" ;;
        5) new_mode="manual" ;;
        *) _paqet::error "Invalid choice."; return 1 ;;
    esac

    paqet::change_mode "$name" "$new_mode"
}

paqet::change_mtu() {
    local name="$1" mtu="$2"
    if ! valid_mtu_global "$mtu"; then
        _paqet::error "Invalid MTU value (must be $MIN_MTU-$MAX_MTU_GLOBAL)"
        return 1
    fi
    local config_file="${PAQET_CONFIG_DIR}/${name}.yaml"
    [[ -f "$config_file" ]] || { _paqet::error "Config not found: $config_file"; return 1; }

    sed -i.bak -E "s/^([[:space:]]*mtu:)[[:space:]]*[0-9]+/\1 $mtu/" "$config_file" || {
        _paqet::error "Failed to update MTU in $config_file"
        return 1
    }

    _paqet::log "MTU for '$name' set to $mtu (config updated: $config_file)"
    if paqet::restart "$name"; then
        _paqet::log "Service restarted after MTU change."
    else
        _paqet::error "Failed to restart service after MTU change."
        return 1
    fi
}

# =============================================================================
# Improved remove: deletes everything related to the tunnel (like manual commands)
# Now supports both paqet-* and paqet@* service names.
# =============================================================================
paqet::remove() {
    local name="$1"
    _paqet::log "Removing tunnel '$name'..."
    _ensure_cmd systemctl systemd 2>/dev/null || return 1

    # Stop and disable firewall service (if exists)
    if systemctl list-unit-files 2>/dev/null | grep -q "paqet-fw-${name}\.service"; then
        systemctl stop "paqet-fw-${name}.service" 2>/dev/null || true
        systemctl disable "paqet-fw-${name}.service" 2>/dev/null || true
        rm -f "${PAQET_SYSTEMD_DIR}/paqet-fw-${name}.service"
    fi

    # Stop and disable main service (paqet-${name} or paqet@${name})
    if systemctl list-unit-files 2>/dev/null | grep -q "paqet-${name}\.service"; then
        systemctl stop "paqet-${name}.service" 2>/dev/null || true
        systemctl disable "paqet-${name}.service" 2>/dev/null || true
        rm -f "${PAQET_SYSTEMD_DIR}/paqet-${name}.service"
    fi
    if systemctl list-unit-files 2>/dev/null | grep -q "paqet@${name}\.service"; then
        systemctl stop "paqet@${name}.service" 2>/dev/null || true
        systemctl disable "paqet@${name}.service" 2>/dev/null || true
        rm -f "${PAQET_SYSTEMD_DIR}/paqet@${name}.service"
    fi

    # Remove config and firewall script
    rm -f "${PAQET_CONFIG_DIR}/${name}.yaml"
    rm -f "${PAQET_FW_DIR}/fw-${name}.sh"

    # Remove any leftover .bak files
    rm -f "${PAQET_CONFIG_DIR}/${name}.yaml.bak" 2>/dev/null || true

    # Remove potential anti-filter cron jobs (changed sepehr to truma)
    if crontab -l 2>/dev/null | grep -q "truma-restart-${name}.sh"; then
        crontab -l 2>/dev/null | grep -v "truma-restart-${name}.sh" | crontab -
    fi
    rm -f "/usr/local/bin/truma-restart-${name}.sh" 2>/dev/null || true
    rm -f "/usr/local/bin/truma-dummy-${name}.sh" 2>/dev/null || true
    systemctl stop "truma-dummy-${name}.service" 2>/dev/null || true
    systemctl disable "truma-dummy-${name}.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/truma-dummy-${name}.service" 2>/dev/null || true

    # Reload systemd and reset failed
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true

    _paqet::log "Tunnel '$name' completely removed."
    return 0
}

paqet::create_interactive() {
    _paqet::ensure_root || return 1
    _dbg "Starting create_interactive()"

    local side name role remote_ip port key mtu mode router_mac fwd_input
    local -a fwdarr

    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Create Paqet Tunnel${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo "Select side:"
    echo "  1) Iran (client)"
    echo "  2) Kharej (server)"
    read -r -p "Choice [1-2]: " side_choice
    side_choice="$(trim "$side_choice")"
    case "$side_choice" in
        1) role="client" ;;
        2) role="server" ;;
        *) _paqet::error "Invalid side."; pause_enter; return 0 ;;
    esac

    while true; do
        read_required "Enter tunnel name (letters, numbers, _, - only):" name
        if valid_tunnel_name "$name"; then
            break
        fi
        print_error "Invalid tunnel name. Allowed characters: a-z, A-Z, 0-9, _, -"
    done

    if [[ "$role" == "client" ]]; then
        read_ip "Enter remote server IP (paqet server):" remote_ip
    else
        remote_ip=""
    fi

    read_port "Enter tunnel port (e.g. 2095):" port "2095"

    echo -e "${YELLOW}Encryption key (enter to auto-generate):${NC}"
    read -r -p "> " key
    if [[ -z "$key" ]]; then
        key=$(paqet::generate_key)
        echo -e "\n${GREEN}🔐 Generated encryption key: ${CYAN}${key}${NC}"
        echo -e "${YELLOW}   (Press Enter to continue)${NC}"
        read -r
    fi

    read_mtu "Enter MTU (576-9000) [default 1280]:" mtu "1280"
    if ! valid_mtu_global "$mtu"; then
        _paqet::info "Invalid MTU, using 1280"
        mtu=1280
    fi

    echo -e "\n${CYAN}KCP Mode Selection:${NC}"
    echo "  1) fast   – Balanced speed, low latency"
    echo "  2) fast2  – Higher speed, lower latency (recommended)"
    echo "  3) fast3  – Maximum speed, aggressive, may be unstable"
    echo "  4) normal – Conservative, like TCP"
    echo "  5) manual – Advanced manual settings"
    read -r -p "Choice [1-5] (default 2): " mode
    mode="${mode:-2}"
    case "$mode" in
        1|fast) mode="fast" ;;
        2|fast2) mode="fast2" ;;
        3|fast3) mode="fast3" ;;
        4|normal) mode="normal" ;;
        5|manual) mode="manual" ;;
        *) mode="fast2" ;;
    esac

    router_mac=$(_paqet::get_gateway_mac || true)
    if [[ -z "$router_mac" ]]; then
        read_mac "Enter gateway MAC address (aa:bb:cc:dd:ee:ff):" router_mac
    else
        echo -e "${GREEN}Detected gateway MAC: $router_mac${NC}"
    fi

    if [[ "$role" == "client" ]]; then
        read_ports "Enter forwarded ports (comma-separated) or leave empty:" fwd_input ""
        if [[ -n "$fwd_input" ]]; then
            IFS=',' read -r -a fwdarr <<<"$fwd_input"
            for i in "${!fwdarr[@]}"; do fwdarr[$i]="$(trim "${fwdarr[$i]}")"; done
        fi
    fi

    _dbg "Checking dependencies..."
    _ensure_cmd curl || return 1
    _ensure_cmd openssl openssl || return 1
    _ensure_cmd ip iproute2 || return 1
    paqet::install || { _paqet::error "Failed to install paqet binary"; return 1; }

    if [[ "$role" == "server" ]]; then
        local public_ip
        public_ip=$(curl -fsS --max-time 5 https://ifconfig.co 2>/dev/null || true)
        if [[ -z "$public_ip" ]]; then
            public_ip=$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)
        fi
        if [[ -n "$public_ip" ]]; then
            echo -e "${GREEN}Detected public IP: $public_ip${NC}"
            read_confirm "Use this IP?" use_pub "y"
            if [[ "$use_pub" != true ]]; then
                read_ip "Enter public IP for server:" public_ip
            fi
        else
            read_ip "Enter public IP for server:" public_ip
        fi

        paqet::write_config "$name" "$role" "" "$port" "$key" "$mtu" "$mode" "$public_ip" "$router_mac" "${fwdarr[@]}" || return 1
    else
        paqet::write_config "$name" "$role" "$remote_ip" "$port" "$key" "$mtu" "$mode" "" "$router_mac" "${fwdarr[@]}" || return 1
    fi

    paqet::create_service "$name" || return 1
    paqet::create_firewall_service "$name" "$role" "$remote_ip" "$port" || _paqet::log "Firewall script may have issues"
    paqet::start "$name" || { _paqet::error "Failed to start service"; journalctl -u "paqet-${name}.service" -n 50 --no-pager >&2; return 1; }

    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  🔐 Encryption Key: ${CYAN}${key}${NC}"
    if [[ "$role" == "server" ]]; then
        echo -e "${YELLOW}  (Save this key – you'll need it for client configuration)${NC}"
    else
        echo -e "${YELLOW}  (This key should match the server's key)${NC}"
    fi
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}\n"

    _paqet::info "✅ Tunnel '$name' created and started successfully!"
    echo -e "\033[0;32mService status (first 20 lines):\033[0m"
    systemctl --no-pager --full status "paqet-${name}.service" | sed -n '1,20p'
    echo -e "\033[0;36mLogs: journalctl -u paqet-${name}.service -f\033[0m"

    return 0
}

paqet::setup_antifilter() { _paqet::info "Anti-filter not implemented for paqet."; }
paqet::remove_antifilter(){ _paqet::info "Anti-filter not implemented for paqet."; }

# EOF