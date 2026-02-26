#!/usr/bin/env bash
# =============================================================================
# mesh-manager.sh – EMC Tunnel Manager (EasyTier) for Truma
# =============================================================================

set -euo pipefail

# Base functions (if not defined in truma.sh)
if ! declare -f add_log >/dev/null 2>&1; then
    add_log() { echo "[emc] $1"; }
fi
if ! declare -f render >/dev/null 2>&1; then
    render() { clear; echo "==== EMC Manager ===="; }
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
    valid_port() { is_int "$1" && (( $1 >= 1 && $1 <= 65535 )); }
fi
if ! declare -f valid_tunnel_name >/dev/null 2>&1; then
    valid_tunnel_name() { [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]; }
fi
if ! declare -f valid_base_network >/dev/null 2>&1; then
    valid_base_network() {
        local net="$1"
        valid_ipv4 "$net" || return 1
        IFS='.' read -r a b c d <<<"$net"
        [[ "$a" == "10" && "$d" == "0" ]]
    }
fi
if ! declare -f _ensure_cmd >/dev/null 2>&1; then
    _ensure_cmd() {
        local cmd="$1" pkg="${2:-$1}"
        if command -v "$cmd" >/dev/null 2>&1; then
            return 0
        fi
        echo "Command '$cmd' not found. Please install '$pkg' manually."
        return 1
    }
fi
if ! declare -f print_step >/dev/null 2>&1; then
    print_step()   { echo -e "${CYAN}[*]${NC} $1"; }
    print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
    print_error()   { echo -e "${RED}[✗]${NC} $1"; }
    print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
    print_info()    { echo -e "${BLUE}[i]${NC} $1"; }
fi

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; NC='\033[0m'

# Global variables
readonly MESH_BIN_DIR="/root/easytier"
readonly MESH_CORE_URL_BASE="https://github.com/Musixal/Easy-Mesh/raw/main/core/v2.0.3"

# Install EasyTier core (architecture based)
mesh::install_core() {
    if [[ -x "$MESH_BIN_DIR/easytier-core" && -x "$MESH_BIN_DIR/easytier-cli" ]]; then
        add_log "EMC core already installed"
        return 0
    fi

    local arch=$(uname -m)
    local url_subdir=""
    case $arch in
        x86_64)  url_subdir="easytier-linux-x86_64" ;;
        aarch64) url_subdir="easytier-linux-arm64" ;;
        armv7l)
            if ldd /bin/ls | grep -q 'armhf'; then
                url_subdir="easytier-linux-armv7hf"
            else
                url_subdir="easytier-linux-armv7"
            fi
            ;;
        *) print_error "Unsupported architecture: $arch"; return 1 ;;
    esac

    mkdir -p "$MESH_BIN_DIR"
    print_step "Downloading EMC core for $arch ..."
    local base_url="${MESH_CORE_URL_BASE}/${url_subdir}"
    if ! curl -Ls "${base_url}/easytier-cli" -o "$MESH_BIN_DIR/easytier-cli"; then
        print_error "Failed to download easytier-cli"
        return 1
    fi
    if ! curl -Ls "${base_url}/easytier-core" -o "$MESH_BIN_DIR/easytier-core"; then
        print_error "Failed to download easytier-core"
        return 1
    fi
    chmod +x "$MESH_BIN_DIR"/easytier-*
    print_success "EMC core installed"
    return 0
}

# Input helpers (if not defined in truma.sh)
if ! declare -f read_required >/dev/null 2>&1; then
    read_required() {
        local p="$1" v="$2" d="${3:-}" val
        while true; do
            echo -e "${YELLOW}${p}${NC}"
            [[ -n "$d" ]] && echo -e "${CYAN}[default: $d]${NC}"
            read -r -p "> " val
            val="$(trim "$val")"
            [[ -z "$val" && -n "$d" ]] && val="$d"
            if [[ -n "$val" ]]; then
                eval "$v='$val'"
                return 0
            fi
            echo "This field is required."
        done
    }
fi
if ! declare -f read_ip >/dev/null 2>&1; then
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
fi
if ! declare -f read_port >/dev/null 2>&1; then
    read_port() {
        local p="$1" v="$2" d="${3:-}" val
        while true; do
            read_required "$p" "$v" "$d"
            val="$(eval echo "\$$v")"
            if valid_port "$val"; then
                return 0
            fi
            echo "Invalid port (1-65535)."
        done
    }
fi
if ! declare -f read_confirm >/dev/null 2>&1; then
    read_confirm() {
        local p="$1" v="$2" d="${3:-y}" val
        while true; do
            echo -e "${YELLOW}${p} (y/n)${NC}"
            [[ -n "$d" ]] && echo -e "${CYAN}[default: $d]${NC}"
            read -r -p "> " val
            val="$(trim "$val")"
            [[ -z "$val" ]] && val="$d"
            case "$val" in
                [Yy]*) eval "$v=true"; return 0 ;;
                [Nn]*) eval "$v=false"; return 0 ;;
                *) echo "Please enter y/n." ;;
            esac
        done
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

# -----------------------------------------------------------------------------
# Main functions
# -----------------------------------------------------------------------------

mesh::create_interactive() {
    local side name local_ip domain port remote_ip network_secret proto encrypt multi ipv6 base_net

    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Create EMC Tunnel${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    
    echo "Select side:"
    echo "  1) Direct"
    echo "  2) Remote"
    read -r -p "Choice [1-2] (default 1): " side
    side="$(trim "$side")"
    if [[ -z "$side" ]]; then
        side="1"
    fi
    if [[ "$side" != "1" && "$side" != "2" ]]; then
        add_log "Invalid side selected."
        pause_enter
        return 0
    fi

    mesh::install_core || return 1

    read_required "Tunnel name:" name
    
    ask_until_valid "Base network (10.x.y.0):" valid_base_network base_net

    IFS='.' read -r a b c d <<<"$base_net"
    if [[ "$side" == "1" ]]; then
        local_ip="${a}.${b}.${c}.1"
    else
        local_ip="${a}.${b}.${c}.2"
    fi
    add_log "Local IP set to: $local_ip"

    read_required "Domain:" domain
    
    read_port "Tunnel port (default 8535):" port "8535"

    read_ip "Remote IP:" remote_ip

    local random_secret
    if command -v openssl >/dev/null 2>&1; then
        random_secret=$(openssl rand -hex 6)
    else
        random_secret="$(date +%s | sha256sum | head -c12)"
    fi
    echo -e "\n${GREEN}Generated network secret: ${CYAN}${random_secret}${NC}"
    read_required "Network secret (must match on all peers):" network_secret "$random_secret"

    echo "Select default protocol:"
    echo "  1) tcp (default)"
    echo "  2) udp"
    echo "  3) ws"
    echo "  4) wss"
    read -r -p "Choice [1-4] (default 1): " proto_choice
    proto_choice="${proto_choice:-1}"
    case $proto_choice in
        2) proto="udp" ;;
        3) proto="ws" ;;
        4) proto="wss" ;;
        *) proto="tcp" ;;
    esac

    read_confirm "Enable encryption?" encrypt "y"
    local enc_opt=""
    [[ "$encrypt" == "false" ]] && enc_opt="--disable-encryption"

    read_confirm "Enable multi-thread?" multi "y"
    local multi_opt=""
    [[ "$multi" == "true" ]] && multi_opt="--multi-thread"

    read_confirm "Enable IPv6?" ipv6 "n"
    local ipv6_opt=""
    [[ "$ipv6" == "false" ]] && ipv6_opt="--disable-ipv6"

    local peers_arg=""
    if [[ -n "$remote_ip" ]]; then
        if [[ "$remote_ip" == *:* ]]; then
            peers_arg="--peers ${proto}://[${remote_ip}]:${port}"
        else
            peers_arg="--peers ${proto}://${remote_ip}:${port}"
        fi
    fi

    local listeners_arg="--listeners ${proto}://[::]:${port} ${proto}://0.0.0.0:${port}"

    local service_file="/etc/systemd/system/mesh-${name}.service"
    cat > "$service_file" <<EOF
[Unit]
Description=EMC Tunnel ${name}
After=network.target

[Service]
ExecStart=$MESH_BIN_DIR/easytier-core -i ${local_ip} ${peers_arg} \\
    --hostname ${domain} --network-secret ${network_secret} \\
    --default-protocol ${proto} ${listeners_arg} ${multi_opt} ${enc_opt} ${ipv6_opt}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    if systemctl enable --now "mesh-${name}.service" 2>&1 | tee -a /var/log/truma.log; then
        print_success "EMC tunnel '$name' created and started!"
    else
        print_error "Failed to start EMC service"
        return 1
    fi

    echo
    echo "Local IP: $local_ip"
    echo "Domain: $domain"
    echo "Network secret: $network_secret"
    echo
    echo -e "${CYAN}---- Tunnel Service Status ----${NC}"
    systemctl --no-pager --full status "mesh-${name}.service" 2>&1 | head -12
    pause_enter
}

mesh::list_peers() {
    local name="$1"
    if [[ ! -x "$MESH_BIN_DIR/easytier-cli" ]]; then
        print_error "easytier-cli not found. Please install core first."
        pause_enter
        return 1
    fi
    echo -e "${CYAN}Peers for EMC tunnel $name:${NC}"
    "$MESH_BIN_DIR/easytier-cli" peer
    pause_enter
}

mesh::list_routes() {
    local name="$1"
    if [[ ! -x "$MESH_BIN_DIR/easytier-cli" ]]; then
        print_error "easytier-cli not found."
        pause_enter
        return 1
    fi
    echo -e "${CYAN}Routes for EMC tunnel $name:${NC}"
    "$MESH_BIN_DIR/easytier-cli" route
    pause_enter
}

mesh::show_secret() {
    local name="$1"
    local service_file="/etc/systemd/system/mesh-${name}.service"
    if [[ -f "$service_file" ]]; then
        local secret
        secret=$(grep -oP '(?<=--network-secret )[^ ]+' "$service_file" 2>/dev/null)
        if [[ -n "$secret" ]]; then
            echo -e "${CYAN}Network secret for $name:${NC} $secret"
        else
            print_error "Secret not found in service file."
        fi
    else
        print_error "Service file not found."
    fi
    pause_enter
}

mesh::remove() {
    local name="$1"
    echo -e "\n${RED}⚠️  Removing EMC tunnel '$name'...${NC}"
    systemctl stop "mesh-${name}.service" 2>/dev/null || true
    systemctl disable "mesh-${name}.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/mesh-${name}.service"

    crontab -l 2>/dev/null | grep -v "mesh-${name}" | crontab - 2>/dev/null || true

    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true

    print_success "EMC tunnel '$name' removed."
    pause_enter
}

# Placeholder functions for compatibility
mesh::list_ports() {
    print_info "EMC tunnels do not have built-in port forwarding. Use HAProxy."
    pause_enter
}
mesh::add_port_interactive() { mesh::list_ports; }
mesh::remove_port_interactive() { mesh::list_ports; }
mesh::change_mtu() {
    print_info "MTU change not supported for EMC."
    pause_enter
}
mesh::change_mode_interactive() {
    print_info "Mode change not applicable for EMC."
    pause_enter
}
mesh::setup_antifilter() {
    print_info "Anti-filter not implemented for EMC."
    pause_enter
}
mesh::remove_antifilter() { mesh::setup_antifilter; }

# =============================================================================
# End of file
# =============================================================================