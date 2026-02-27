#!/usr/bin/env bash
# =============================================================================
# haproxy-manager.sh – Centralized HAProxy rule manager for Truma
# =============================================================================
# Version: 2.1.4 (Fully debugged and improved)
# Changes:
#   - Added guard clause to prevent multiple sourcing
#   - Fixed octal bug in valid_port (using 10#)
#   - Improved port collision detection with ss/netstat
#   - Added comprehensive error messages
# =============================================================================

set -euo pipefail

# Guard clause
if [[ "${__haproxy_manager_loaded:-}" == "true" ]]; then
    return 0
fi
__haproxy_manager_loaded=true

# -----------------------------------------------------------------------------
# Base functions (fallback if not defined in truma.sh)
# -----------------------------------------------------------------------------
if ! declare -f print_step >/dev/null 2>&1; then
    print_step()   { echo -e "\033[0;36m[*]\033[0m $1"; }
    print_success() { echo -e "\033[0;32m[✓]\033[0m $1"; }
    print_error()   { echo -e "\033[0;31m[✗]\033[0m $1"; }
    print_warning() { echo -e "\033[1;33m[!]\033[0m $1"; }
    print_info()    { echo -e "\033[0;34m[i]\033[0m $1"; }
fi
if ! declare -f pause_enter >/dev/null 2>&1; then
    pause_enter() { read -r -p "Press ENTER to continue..."; }
fi
if ! declare -f trim >/dev/null 2>&1; then
    trim() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$1"; }
fi
if ! declare -f valid_port >/dev/null 2>&1; then
    valid_port() {
        [[ "$1" =~ ^[0-9]+$ ]] || return 1
        if (( 10#$1 >= 1 && 10#$1 <= 65535 )); then
            # Check if port is already in use
            if command -v ss &>/dev/null; then
                if ss -tuln 2>/dev/null | grep -q ":$1 "; then
                    print_error "Port $1 is already in use by another process."
                    return 1
                fi
            elif command -v netstat &>/dev/null; then
                if netstat -tuln 2>/dev/null | grep -q ":$1 "; then
                    print_error "Port $1 is already in use by another process."
                    return 1
                fi
            fi
            return 0
        else
            return 1
        fi
    }
fi
if ! declare -f valid_ipv4 >/dev/null 2>&1; then
    valid_ipv4() {
        [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
        IFS='.' read -r a b c d <<<"$1"
        (( 10#$a <= 255 && 10#$b <= 255 && 10#$c <= 255 && 10#$d <= 255 ))
    }
fi
if ! declare -f _ensure_cmd >/dev/null 2>&1; then
    _ensure_cmd() {
        local cmd="$1" pkg="${2:-$1}"
        if command -v "$cmd" >/dev/null 2>&1; then
            return 0
        fi
        echo "Command '$cmd' not found. Please install '$pkg' manually." >&2
        return 1
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
                [Yy]*) printf -v "$v" "true"; return 0 ;;
                [Nn]*) printf -v "$v" "false"; return 0 ;;
                *) echo "Please enter y/n." ;;
            esac
        done
    }
fi

# Colors (if not already defined)
: "${RED:=\033[0;31m}" "${GREEN:=\033[0;32m}" "${YELLOW:=\033[1;33m}"
: "${CYAN:=\033[0;36m}" "${BLUE:=\033[0;34m}" "${MAGENTA:=\033[0;35m}"
: "${WHITE:=\033[1;37m}" "${NC:=\033[0m}"

# -----------------------------------------------------------------------------
# Configurable paths (with defaults)
# -----------------------------------------------------------------------------
HAPROXY_CFG="${HAPROXY_CFG:-/etc/haproxy/haproxy.cfg}"
HAPROXY_CONFD="${HAPROXY_CONFD:-/etc/haproxy/conf.d}"
HAPROXY_OVERRIDE_DIR="${HAPROXY_OVERRIDE_DIR:-/etc/systemd/system/haproxy.service.d}"
HAPROXY_OVERRIDE_FILE="${HAPROXY_OVERRIDE_DIR}/override.conf"

# -----------------------------------------------------------------------------
# Multi-distro package manager support
# -----------------------------------------------------------------------------
install_haproxy() {
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y haproxy
    elif command -v yum &>/dev/null; then
        yum install -y haproxy
    elif command -v dnf &>/dev/null; then
        dnf install -y haproxy
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm haproxy
    elif command -v apk &>/dev/null; then
        apk add --no-cache haproxy
    else
        print_error "No supported package manager found. Please install HAProxy manually."
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Port conflict detection (system-wide) – enhanced
# -----------------------------------------------------------------------------
check_port_available() {
    local port="$1"
    local exclude_file="${2:-}"
    # Check system-wide listening ports
    if command -v ss &>/dev/null; then
        if ss -tuln 2>/dev/null | grep -q ":$port "; then
            print_error "Port $port is already in use by another process."
            return 1
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            print_error "Port $port is already in use by another process."
            return 1
        fi
    fi
    # Check existing HAProxy rules (skip if it's the same file)
    if [[ -d "$HAPROXY_CONFD" ]]; then
        for f in "$HAPROXY_CONFD"/rule_*.cfg; do
            [[ -f "$f" ]] || continue
            [[ -n "$exclude_file" && "$f" == "$exclude_file" ]] && continue
            if grep -q "bind.*:$port" "$f"; then
                print_error "Port $port already defined in $(basename "$f")."
                return 1
            fi
        done
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Install HAProxy if needed and ensure valid main config
# -----------------------------------------------------------------------------
haproxy::install() {
    if ! command -v haproxy &>/dev/null; then
        print_step "Installing HAProxy..."
        if ! install_haproxy; then
            return 1
        fi
        systemctl enable haproxy --now
        print_success "HAProxy installed and started."
    fi

    mkdir -p "$HAPROXY_CONFD"

    # Validate or create main config
    if [[ -f "$HAPROXY_CFG" ]]; then
        if ! haproxy -c -f "$HAPROXY_CFG" &>/dev/null; then
            print_warning "Existing HAProxy config is invalid. Overwriting with default."
            haproxy::write_main_cfg
        fi
    else
        haproxy::write_main_cfg
    fi

    # Ensure systemd override for conf.d support (only for systemd)
    if command -v systemctl &>/dev/null; then
        if [[ ! -f "$HAPROXY_OVERRIDE_FILE" ]]; then
            mkdir -p "$HAPROXY_OVERRIDE_DIR"
            cat > "$HAPROXY_OVERRIDE_FILE" <<EOF
[Service]
ExecStart=
ExecStart=/usr/sbin/haproxy -Ws -f $HAPROXY_CFG -f $HAPROXY_CONFD -p /run/haproxy.pid
EOF
            systemctl daemon-reload
        fi
    else
        print_warning "systemd not detected. Please ensure HAProxy includes $HAPROXY_CONFD in its config."
    fi
}

# -----------------------------------------------------------------------------
# Write main config (global/defaults) – TCP mode only
# -----------------------------------------------------------------------------
haproxy::write_main_cfg() {
    cat > "$HAPROXY_CFG" <<'EOF'
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms
EOF
}

# -----------------------------------------------------------------------------
# Add a port forward rule
# -----------------------------------------------------------------------------
haproxy::add_rule() {
    local bind_port="$1" target_ip="$2" target_port="$3" desc="${4:-}"
    if ! valid_port "$bind_port"; then
        print_error "Invalid bind port: $bind_port"
        return 1
    fi
    if ! valid_port "$target_port"; then
        print_error "Invalid target port: $target_port"
        return 1
    fi
    if ! valid_ipv4 "$target_ip"; then
        print_error "Invalid target IP: $target_ip"
        return 1
    fi

    haproxy::install

    local rule_file="${HAPROXY_CONFD}/rule_${bind_port}.cfg"

    # Check port availability (unless overwriting the same file)
    if ! check_port_available "$bind_port" "$rule_file"; then
        return 1
    fi

    if [[ -f "$rule_file" ]]; then
        print_warning "Rule for port $bind_port already exists."
        if [[ $NONINTERACTIVE -eq 0 ]]; then
            read_confirm "Overwrite existing rule?" confirm "n"
            if [[ "$confirm" != true ]]; then
                print_info "Rule not added."
                return 0
            fi
        else
            if [[ "${FORCE:-0}" -ne 1 ]]; then
                print_error "Rule exists and FORCE not set. Aborting."
                return 1
            fi
        fi
    fi

    # Sanitize description: remove newlines and carriage returns
    local desc_safe
    desc_safe="${desc//$'\n'/}"
    desc_safe="${desc_safe//$'\r'/}"
    desc_safe="${desc_safe//#/}"  # Remove # to avoid comment injection

    # Create file with secure permissions
    umask 077
    {
        echo "# ${desc_safe:-Forward port $bind_port to $target_ip:$target_port}"
        echo "frontend fe_${bind_port}"
        echo "    bind *:${bind_port}"
        echo "    default_backend be_${bind_port}"
        echo ""
        echo "backend be_${bind_port}"
        echo "    server srv_${bind_port} ${target_ip}:${target_port} check"
    } > "$rule_file"
    chmod 600 "$rule_file"
    chown root:root "$rule_file"

    print_success "Rule added for port $bind_port → $target_ip:$target_port"
    haproxy::apply
}

# -----------------------------------------------------------------------------
# Remove a rule by bind port
# -----------------------------------------------------------------------------
haproxy::remove_rule() {
    local bind_port="$1"
    local rule_file="${HAPROXY_CONFD}/rule_${bind_port}.cfg"
    if [[ ! -f "$rule_file" ]]; then
        print_error "Rule for port $bind_port not found."
        return 1
    fi
    rm -f "$rule_file"
    print_success "Rule for port $bind_port removed."
    haproxy::apply
}

# -----------------------------------------------------------------------------
# List all active rules (with robust extraction)
# -----------------------------------------------------------------------------
haproxy::list_rules() {
    echo -e "${CYAN}Active HAProxy rules:${NC}"
    local count=0
    for f in "$HAPROXY_CONFD"/rule_*.cfg; do
        [[ -f "$f" ]] || continue
        count=$((count+1))
        local filename port
        filename=$(basename "$f")
        # Use bash regex for safer extraction
        if [[ "$filename" =~ ^rule_([0-9]+)\.cfg$ ]]; then
            port="${BASH_REMATCH[1]}"
        else
            print_warning "Skipping file with invalid name: $filename"
            continue
        fi
        # Ensure port is numeric
        if ! valid_port "$port" 2>/dev/null; then
            print_warning "Invalid port number in file: $filename"
            continue
        fi
        local target
        target=$(grep -E '^[[:space:]]*server' "$f" | awk '{print $3}' | head -1)
        echo "  $port → $target"
    done
    if [[ $count -eq 0 ]]; then
        echo "  (no rules)"
    fi
}

# -----------------------------------------------------------------------------
# Apply changes (validate and reload/start)
# -----------------------------------------------------------------------------
haproxy::apply() {
    # Validate configuration
    if haproxy -c -f "$HAPROXY_CFG" -f "$HAPROXY_CONFD" &>/dev/null; then
        if command -v systemctl &>/dev/null; then
            # Improved reload/start logic
            if systemctl is-active --quiet haproxy; then
                if systemctl reload haproxy; then
                    print_success "HAProxy reloaded."
                else
                    print_warning "Reload failed; attempting restart."
                    systemctl restart haproxy && print_success "HAProxy restarted."
                fi
            else
                if systemctl start haproxy; then
                    print_success "HAProxy started."
                else
                    print_error "Failed to start HAProxy."
                    return 1
                fi
            fi
        else
            # Non-systemd fallback
            if command -v service &>/dev/null; then
                service haproxy restart
            else
                print_warning "Please restart HAProxy manually."
            fi
        fi
    else
        print_error "Configuration invalid. Not applied."
        haproxy -c -f "$HAPROXY_CFG" -f "$HAPROXY_CONFD"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Remove all rules
# -----------------------------------------------------------------------------
haproxy::remove_all() {
    rm -f "$HAPROXY_CONFD"/rule_*.cfg
    print_success "All rules removed."
    haproxy::apply
}

# -----------------------------------------------------------------------------
# Show HAProxy service status
# -----------------------------------------------------------------------------
haproxy::status() {
    if command -v systemctl &>/dev/null; then
        systemctl status haproxy --no-pager 2>&1 | head -20
    elif command -v service &>/dev/null; then
        service haproxy status
    else
        print_error "Cannot determine HAProxy status."
    fi
}

# =============================================================================
# End of file
# =============================================================================