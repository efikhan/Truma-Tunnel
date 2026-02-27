#!/usr/bin/env bash
# =============================================================================
# haproxy-manager.sh – Centralized HAProxy rule manager for Truma
# =============================================================================

set -euo pipefail

# Base functions (if not defined in truma.sh)
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
    valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }
fi
if ! declare -f valid_ipv4 >/dev/null 2>&1; then
    valid_ipv4() {
        [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
        IFS='.' read -r a b c d <<<"$1"
        ((a<=255 && b<=255 && c<=255 && d<=255))
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

# Paths
readonly HAPROXY_CFG="/etc/haproxy/haproxy.cfg"
readonly HAPROXY_CONFD="/etc/haproxy/conf.d"
readonly HAPROXY_OVERRIDE_DIR="/etc/systemd/system/haproxy.service.d"
readonly HAPROXY_OVERRIDE_FILE="${HAPROXY_OVERRIDE_DIR}/override.conf"

# Install HAProxy if needed and ensure valid main config
haproxy::install() {
    if ! command -v haproxy &>/dev/null; then
        print_step "Installing HAProxy..."
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y haproxy >/dev/null 2>&1
        elif command -v yum &>/dev/null; then
            yum install -y haproxy >/dev/null 2>&1
        elif command -v dnf &>/dev/null; then
            dnf install -y haproxy >/dev/null 2>&1
        else
            print_error "No supported package manager found. Please install HAProxy manually."
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

    # Ensure systemd override for conf.d support
    if [[ ! -f "$HAPROXY_OVERRIDE_FILE" ]]; then
        mkdir -p "$HAPROXY_OVERRIDE_DIR"
        cat > "$HAPROXY_OVERRIDE_FILE" <<EOF
[Service]
ExecStart=
ExecStart=/usr/sbin/haproxy -Ws -f $HAPROXY_CFG -f $HAPROXY_CONFD -p /run/haproxy.pid
EOF
        systemctl daemon-reload
    fi
}

# Write main config (global/defaults) – TCP mode only
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

# Add a port forward rule
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
    if [[ -f "$rule_file" ]]; then
        print_warning "Rule for port $bind_port already exists. Overwriting."
    fi

    {
        echo "# ${desc:-Forward port $bind_port to $target_ip:$target_port}"
        echo "frontend fe_${bind_port}"
        echo "    bind *:${bind_port}"
        echo "    default_backend be_${bind_port}"
        echo ""
        echo "backend be_${bind_port}"
        echo "    server srv_${bind_port} ${target_ip}:${target_port} check"
    } > "$rule_file"

    print_success "Rule added for port $bind_port → $target_ip:$target_port"
    haproxy::apply
}

# Remove a rule by bind port
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

# List all active rules
haproxy::list_rules() {
    echo -e "${CYAN}Active HAProxy rules:${NC}"
    local count=0
    for f in "$HAPROXY_CONFD"/rule_*.cfg; do
        [[ -f "$f" ]] || continue
        count=$((count+1))
        local port
        port=$(basename "$f" | sed 's/rule_\(.*\)\.cfg/\1/')
        local target
        target=$(grep -E '^[[:space:]]*server' "$f" | awk '{print $3}' | head -1)
        echo "  $port → $target"
    done
    if [[ $count -eq 0 ]]; then
        echo "  (no rules)"
    fi
}

# Apply changes (validate and reload)
haproxy::apply() {
    if haproxy -c -f "$HAPROXY_CFG" -f "$HAPROXY_CONFD" &>/dev/null; then
        if systemctl reload haproxy &>/dev/null; then
            print_success "HAProxy reloaded."
        else
            # اگر reload ممکن نبود (مثلاً سرویس فعال نبود)، try start
            if systemctl start haproxy &>/dev/null; then
                print_success "HAProxy started."
            else
                print_error "Failed to start/reload HAProxy."
                return 1
            fi
        fi
    else
        print_error "Configuration invalid. Not applied."
        haproxy -c -f "$HAPROXY_CFG" -f "$HAPROXY_CONFD"
        return 1
    fi
}

# Remove all rules
haproxy::remove_all() {
    rm -f "$HAPROXY_CONFD"/rule_*.cfg
    print_success "All rules removed."
    haproxy::apply
}

# Show HAProxy service status
haproxy::status() {
    systemctl status haproxy --no-pager 2>&1 | head -20
}

# =============================================================================
# End of file
# =============================================================================