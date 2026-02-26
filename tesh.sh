#!/usr/bin/env bash
# =============================================================================
# Iran Server Optimizer + Truma Tunnel Manager – All-in-One Installer
# =============================================================================
# This script asks whether the server is inside Iran, applies optimizations if
# yes, then installs Truma and launches its menu automatically.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Colors (aligned with Truma)
# -----------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BLUE='\033[0;34m'
WHITE='\033[1;37m'; NC='\033[0m'

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------
print_banner() {
    echo -e "${MAGENTA}"
    cat << "EOF"
╔═╗╦═╗╔═╗╔═╗╔╦╗╔═╗  ╔╦╗╔═╗╦╔╗╔╔═╗╦═╗╔╦╗╔═╗
║  ╠╦╝║╣ ╠═╣ ║ ║╣    ║ ║╣ ║║║║║ ╦╠╦╝ ║ ║╣ 
╚═╝╩╚═╚═╝╩ ╩ ╩ ╚═╝   ╩ ╚═╝╩╝╚╝╚═╝╩╚═ ╩ ╚═╝
   بهینه‌ساز ایران + نصب خودکار Truma
EOF
    echo -e "${NC}"
}

print_step()   { echo -e "${CYAN}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error()   { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_info()    { echo -e "${BLUE}[i]${NC} $1"; }

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /var/log/truma-install.log 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Package helpers
# -----------------------------------------------------------------------------
install_pkg() {
    local pkg="$1"
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq "$pkg"
    elif command -v yum &>/dev/null; then
        yum install -y -q "$pkg"
    elif command -v dnf &>/dev/null; then
        dnf install -y -q "$pkg"
    else
        return 1
    fi
    return 0
}

ensure_cmd() {
    local cmd="$1"; shift
    local candidates=("$@")
    if command -v "$cmd" &>/dev/null; then
        return 0
    fi
    for pkg in "${candidates[@]}"; do
        if install_pkg "$pkg"; then
            if command -v "$cmd" &>/dev/null; then
                print_success "Installed $pkg (provides $cmd)"
                return 0
            fi
        fi
    done
    print_error "Failed to install $cmd. Please install ${candidates[*]} manually."
    return 1
}

backup_file() {
    local src="$1"
    local dst="$src.backup.$(date +%s)"
    if [[ -f "$src" ]]; then
        cp -a "$src" "$dst" && print_info "Backed up: $dst"
    fi
}

# -----------------------------------------------------------------------------
# Optimizer functions (auto mode – no prompts)
# -----------------------------------------------------------------------------
disable_ipv6() {
    print_step "Disabling IPv6 (prefer IPv4)..."
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
    cat > /etc/sysctl.d/99-ipv6-disable.conf << EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl -p /etc/sysctl.d/99-ipv6-disable.conf >/dev/null 2>&1 || true
    print_success "IPv6 disabled"
}

apply_kernel_tuning() {
    print_step "Applying kernel network optimizations (BBR, TCP settings)..."
    if modprobe tcp_bbr 2>/dev/null; then
        cat >> /etc/sysctl.d/99-network-performance.conf << EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
        print_success "BBR enabled"
    else
        print_warning "BBR not available, using default cubic"
    fi
    cat >> /etc/sysctl.d/99-network-performance.conf << EOF
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
EOF
    sysctl -p /etc/sysctl.d/99-network-performance.conf >/dev/null 2>&1 || true
    print_success "Kernel parameters updated"
}

select_best_dns() {
    print_step "Testing Iranian anti‑filter DNS servers..."
    local dns_list=(
        "178.22.122.100|Shekan"
        "185.51.200.2|Shekan"
        "10.202.10.202|403 Online"
        "10.202.10.102|403 Online"
        "10.202.10.10|Radar Game"
        "10.202.10.11|Radar Game"
        "78.157.42.100|Electro"
        "78.157.42.101|Electro"
        "185.55.226.26|Begzar"
        "185.55.225.25|Begzar"
        "5.202.100.100|Pishgaman"
        "5.202.100.101|Pishgaman"
        "94.103.125.157|Shelter"
        "94.103.125.158|Shelter"
        "181.41.194.177|Beshekan"
        "181.41.194.186|Beshekan"
    )

    local best_dns=""
    local best_time=999999
    local test_domain="google.com"
    ensure_cmd dig dnsutils bind-utils

    for entry in "${dns_list[@]}"; do
        local dns="${entry%%|*}"
        local name="${entry#*|}"
        echo -n "  Testing $name ($dns) ... "
        local time
        time=$(timeout 3 dig +time=2 +tries=1 "$test_domain" @"$dns" 2>/dev/null | grep 'Query time:' | awk '{print $4}' || echo "9999")
        if [[ "$time" -lt 9999 ]] && [[ "$time" -gt 0 ]]; then
            echo "${time} ms"
            if (( time < best_time )); then
                best_time=$time
                best_dns=$dns
            fi
        else
            echo "Failed"
        fi
    done

    if [[ -n "$best_dns" ]]; then
        print_success "Best DNS: $best_dns (${best_time} ms)"
        backup_file /etc/resolv.conf
        cat > /etc/resolv.conf << EOF
# Set by Iran Server Optimizer
# Best anti‑filter DNS: $best_dns
nameserver $best_dns
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
        chattr +i /etc/resolv.conf 2>/dev/null || true
        print_success "System DNS configured"
    else
        print_warning "No suitable DNS found. Using default DNS."
    fi
}

select_best_mirror() {
    print_step "Testing mirrors..."
    local mirrors=(
        "mirror.iranserver.com|IR Server"
        "ir.ubuntu.sindad.cloud|Sindad"
        "mirror.arvancloud.ir|ArvanCloud"
        "archive.ubuntu.petiak.ir|Petiak"
        "ubuntu.hostiran.ir|HostIran"
        "mirrors.pardisco.co|PardisCo"
        "ubuntu.pars.host|ParsHost"
        "mirror.0-1.cloud|0-1 Cloud"
        "repo.linuxmirrors.ir|Linux Mirrors"
        "ubuntu.shatel.ir|Shatel"
        "archive.ubuntu.com|Main Archive"
        "mirrors.edge.kernel.org|Kernel"
        "mirrors.aliyun.com|Aliyun"
        "mirror.ubuntu.com|Ubuntu Mirror"
    )

    local test_path=""
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                test_path="ubuntu/dists/${UBUNTU_CODENAME:-$VERSION_CODENAME}/InRelease"
                ;;
            centos|rhel|almalinux|rocky)
                test_path="centos/${VERSION_ID}/os/x86_64/repodata/repomd.xml"
                ;;
            *)
                test_path="ubuntu/dists/noble/InRelease"
                ;;
        esac
    else
        test_path="ubuntu/dists/noble/InRelease"
    fi

    local best_mirror=""
    local best_speed=0
    ensure_cmd curl curl

    for entry in "${mirrors[@]}"; do
        local mirror="${entry%%|*}"
        local name="${entry#*|}"
        echo -n "  Testing $name ($mirror) ... "
        local speed
        speed=$(curl -s -w "%{speed_download}" -o /dev/null --max-time 5 --ipv4 "http://$mirror/$test_path" 2>/dev/null | awk '{print int($1/1024)}' || echo 0)
        if [[ "$speed" -gt 0 ]]; then
            echo "${speed} KB/s"
            if (( speed > best_speed )); then
                best_speed=$speed
                best_mirror=$mirror
            fi
        else
            echo "Failed"
        fi
    done

    if [[ -n "$best_mirror" ]]; then
        print_success "Best mirror: $best_mirror (${best_speed} KB/s)"
        # Configure mirror based on distribution
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            case "$ID" in
                ubuntu|debian)
                    if [[ -f /etc/apt/sources.list ]]; then
                        backup_file /etc/apt/sources.list
                        sed -i "s|http://[a-zA-Z0-9.-]*archive.ubuntu.com/ubuntu|http://$best_mirror/ubuntu|g" /etc/apt/sources.list 2>/dev/null || true
                        sed -i "s|http://security.ubuntu.com/ubuntu|http://$best_mirror/ubuntu|g" /etc/apt/sources.list 2>/dev/null || true
                        sed -i "s|http://deb.debian.org/debian|http://$best_mirror/debian|g" /etc/apt/sources.list 2>/dev/null || true
                        print_success "APT sources.list updated with mirror $best_mirror"
                    fi
                    ;;
                centos|rhel|almalinux|rocky)
                    print_warning "RHEL‑based distro – mirror configuration is limited."
                    ;;
                *)
                    print_warning "Unsupported distribution – mirror not configured."
                    ;;
            esac
        fi
        apt update -qq 2>/dev/null || true
    else
        print_warning "No suitable mirror found."
    fi
}

run_optimizer() {
    print_step "Starting Iran server optimizations..."
    disable_ipv6
    select_best_dns
    select_best_mirror
    apply_kernel_tuning
    print_success "Optimizations completed."
}

# -----------------------------------------------------------------------------
# Truma installation
# -----------------------------------------------------------------------------
install_truma() {
    print_step "Installing Truma Tunnel Manager..."

    local INSTALL_DIR="/opt/truma"
    local REPO_URL="https://github.com/efikhan/Truma-Tunnel.git"

    # Ensure git is available
    if ! command -v git &>/dev/null; then
        print_step "Installing git..."
        install_pkg git || { print_error "Failed to install git."; exit 1; }
    fi

    # Remove previous installation if exists
    if [[ -d "$INSTALL_DIR" ]]; then
        print_step "Removing old installation at $INSTALL_DIR..."
        rm -rf "$INSTALL_DIR"
    fi

    # Clone repository
    print_step "Cloning Truma repository..."
    mkdir -p "$INSTALL_DIR"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1 || {
        print_error "Failed to clone repository."
        exit 1
    }
    print_success "Repository cloned."

    cd "$INSTALL_DIR"

    # Fix line endings
    print_step "Fixing line endings (removing CRLF)..."
    sed -i 's/\r$//' *.sh 2>/dev/null || true
    print_success "Line endings fixed."

    # Set execute permissions
    print_step "Setting execute permissions..."
    chmod +x *.sh
    print_success "Permissions set."

    echo
    print_success "Truma Tunnel Manager installed successfully!"
    print_info "Installation directory: $INSTALL_DIR"
    echo
    print_step "Launching Truma..."
    exec ./truma.sh
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    # Root check
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}This script must be run as root. Re‑running with sudo...${NC}"
        exec sudo bash "$0" "$@"
    fi

    clear
    print_banner
    echo

    # Ask in Persian
    echo -e "${YELLOW}آیا سرور داخل ایران قرار دارد؟ (y/n) [پیش‌فرض: y]${NC}"
    read -r -p "> " answer
    answer="${answer:-y}"
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        print_info "سرور داخل ایران است. بهینه‌سازی‌ها اعمال می‌شوند."
        run_optimizer
    else
        print_info "سرور خارج از ایران است. فقط Truma نصب می‌شود."
    fi

    # Always install Truma
    install_truma
}

main "$@"
