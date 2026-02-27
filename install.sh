#!/usr/bin/env bash
# =============================================================================
# Truma Tunnel Manager – Professional Installer (Complete Edition)
# Includes: IPv6 Disable, DNS Optimizer, Kernel Tuning, Smart Mirror
# Robust error handling – will not stop on optional failures
# =============================================================================

set -euo pipefail

# Global flags
AUTO_YES=0
INSTALL_LOG="/var/log/truma-install.log"
IRAN_OPTIMIZE=0
RELEASE_VERSION="v2.1.1"  # Fixed release

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; NC='\033[0m'

# Early log creation
mkdir -p "$(dirname "$INSTALL_LOG")"
touch "$INSTALL_LOG" 2>/dev/null || true
chmod 0640 "$INSTALL_LOG" 2>/dev/null || true

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$INSTALL_LOG" 2>/dev/null || true; }

print_step()   { echo -e "${CYAN}[*]${NC} $1"; log "[*] $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; log "[✓] $1"; }
print_error()   { echo -e "${RED}[✗]${NC} $1"; log "[✗] $1"; exit 1; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; log "[!] $1"; }
print_info()    { echo -e "${BLUE}[i]${NC} $1"; log "[i] $1"; }

pause_enter() {
    [[ $AUTO_YES -eq 1 ]] && return 0
    echo
    read -r -p "Press ENTER to continue..."
}

die() { print_error "$1"; exit 1; }

render_box() {
    local title="$1" content="$2"
    echo "┌──────────────────────────────────────────────────────────────┐"
    printf "│  %-68s  │\n" "$title"
    echo "├──────────────────────────────────────────────────────────────┤"
    while IFS= read -r line; do
        printf "│  %-68s  │\n" "$line"
    done <<< "$content"
    echo "└──────────────────────────────────────────────────────────────┘"
}

# Backup & Rollback
declare -a BACKUP_FILES=()
backup_file() {
    local src="$1"
    local dst="${src}.truma.bak.$(date +%s.%N)"
    if [[ -f "$src" ]]; then
        cp -a "$src" "$dst" && BACKUP_FILES+=("$src|$dst") && log "Backed up $src -> $dst"
    fi
}
rollback_all() {
    print_warning "Rolling back changes..."
    for entry in "${BACKUP_FILES[@]}"; do
        local src="${entry%%|*}" dst="${entry#*|}"
        [[ -f "$dst" ]] && cp "$dst" "$src" && log "Restored $src"
    done
}
trap 'rollback_all; exit 1' ERR INT TERM

# Ensure command (fatal if missing after installation attempt)
ensure_cmd() {
    local cmd="$1"; shift
    local candidates=("$@")
    if command -v "$cmd" >/dev/null 2>&1; then return 0; fi
    for pkg in "${candidates[@]}"; do
        if install_pkg "$pkg"; then
            if command -v "$cmd" >/dev/null 2>&1; then
                print_success "Installed $pkg (provides $cmd)"
                return 0
            fi
        fi
    done
    die "Failed to install $cmd. Please install ${candidates[*]} manually."
}

install_pkg() {
    local pkg="$1"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq "$pkg"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q "$pkg"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q "$pkg"
    else
        return 1
    fi
    return 0
}

# ====================================================================
# Iran‑specific optimizations (all optional – failures become warnings)
# ====================================================================

# 1. Disable IPv6
disable_ipv6() {
    print_step "Disabling IPv6 (optional) ..."
    if ! command -v sysctl &>/dev/null; then
        print_warning "sysctl not found – skipping IPv6 disable."
        return
    fi
    backup_file /etc/sysctl.d/99-ipv6-disable.conf 2>/dev/null || true
    cat > /etc/sysctl.d/99-ipv6-disable.conf << EOF 2>/dev/null || {
        print_warning "Could not write IPv6 config – skipping."
        return
    }
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || print_warning "Failed to disable IPv6 immediately."
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
    sysctl -p /etc/sysctl.d/99-ipv6-disable.conf >/dev/null 2>&1 || print_warning "IPv6 persistence may not work."
    print_success "IPv6 disabled (if supported)."
}

# 2. Select best DNS
select_best_dns() {
    print_step "Testing Iranian DNS servers..."
    local dns_list=(
        "178.22.122.100|Shekan"
        "185.51.200.2|Shekan"
        "78.157.42.100|Electro"
        "78.157.42.101|Electro"
        "185.55.226.26|Begzar"
        "185.55.225.25|Begzar"
        "5.202.100.100|Pishgaman"
        "5.202.100.101|Pishgaman"
    )
    local best_dns=""
    local best_time=999999
    local test_domain="google.com"

    if ! command -v dig &>/dev/null; then
        print_warning "dig not found – skipping DNS optimization."
        return
    fi

    for entry in "${dns_list[@]}"; do
        local dns="${entry%%|*}"
        local name="${entry#*|}"
        echo -n "  Testing $name ($dns) ... "
        local time
        time=$(timeout 3 dig +time=2 +tries=1 "$test_domain" @"$dns" 2>/dev/null | grep 'Query time:' | awk '{print $4}' || echo "9999")
        time="${time//[!0-9]/}"
        if [[ -n "$time" && "$time" -lt 9999 && "$time" -gt 0 ]]; then
            echo "${time} ms"
            if [[ "$time" -lt "$best_time" ]]; then
                best_time=$time
                best_dns=$dns
            fi
        else
            echo "Failed"
        fi
    done

    if [[ -z "$best_dns" ]]; then
        print_warning "No suitable DNS found. Using default."
        return
    fi

    print_success "Best DNS: $best_dns (${best_time} ms)"
    backup_file /etc/resolv.conf

    if systemctl is-active systemd-resolved &>/dev/null; then
        backup_file /etc/systemd/resolved.conf
        if cat > /etc/systemd/resolved.conf << EOF 2>/dev/null; then
[Resolve]
DNS=$best_dns 8.8.8.8 1.1.1.1
EOF
            systemctl restart systemd-resolved 2>/dev/null || print_warning "Failed to restart systemd-resolved."
            print_success "DNS configured via systemd-resolved."
        else
            print_warning "Could not configure systemd-resolved – skipping."
        fi
    else
        # Direct resolv.conf modification
        chattr -i /etc/resolv.conf 2>/dev/null || true
        if cat > /etc/resolv.conf << EOF; then
# Set by Truma Installer
nameserver $best_dns
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
            print_success "DNS configured directly."
        else
            print_warning "Could not write /etc/resolv.conf"
        fi
        # Do not lock with chattr to avoid future issues
    fi
}

# 3. Kernel tuning (BBR, buffers, etc.)
apply_kernel_tuning() {
    print_step "Applying kernel network optimizations (optional)..."
    if ! command -v sysctl &>/dev/null || ! command -v modprobe &>/dev/null; then
        print_warning "sysctl or modprobe not found – skipping kernel tuning."
        return
    fi

    local conf="/etc/sysctl.d/99-network-performance.conf"
    backup_file "$conf"

    # Try to enable BBR (may fail on older kernels)
    if modprobe tcp_bbr 2>/dev/null; then
        cat >> "$conf" << EOF 2>/dev/null || print_warning "Could not write BBR settings."
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
        print_success "BBR enabled."
    else
        print_warning "BBR not available – using cubic."
    fi

    # Add common performance tunings (these are usually safe)
    cat >> "$conf" << EOF 2>/dev/null || print_warning "Could not write all kernel tunings."
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
EOF

    sysctl -p "$conf" >/dev/null 2>&1 || print_warning "Failed to apply some kernel parameters."
    print_success "Kernel tuning applied (where possible)."
}

# 4. Smart mirror optimizer (only for Iran)
smart_mirror_optimizer() {
    clear
    banner
    echo
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Finding the Fastest Ubuntu Mirror (Iran)${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo

    local UBUNTU_CODENAME
    UBUNTU_CODENAME=$(lsb_release -sc 2>/dev/null || echo noble)

    local mirrors=(
        "mirror.iranserver.com" "ir.ubuntu.sindad.cloud" "mirror.arvancloud.ir"
        "archive.ubuntu.petiak.ir" "ubuntu.hostiran.ir" "mirrors.pardisco.co"
        "ubuntu.pars.host" "mirror.0-1.cloud" "repo.linuxmirrors.ir" "ubuntu.shatel.ir"
        "archive.ubuntu.com" "mirrors.edge.kernel.org" "mirrors.aliyun.com" "mirror.ubuntu.com"
    )

    local best_mirror="" best_speed=0
    for mirror in "${mirrors[@]}"; do
        echo -n "  Testing $mirror ... "
        local speed
        speed=$(curl -s -w "%{speed_download}" -o /dev/null --max-time 8 "http://${mirror}/ubuntu/dists/${UBUNTU_CODENAME}/InRelease" 2>/dev/null | awk '{print int($1/1024)}' || echo 0)
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
        if [[ -f /etc/apt/sources.list ]]; then
            backup_file /etc/apt/sources.list
            sed -i "s|http://[a-zA-Z0-9.-]*archive.ubuntu.com/ubuntu|http://$best_mirror/ubuntu|g" /etc/apt/sources.list 2>/dev/null || print_warning "Could not update sources.list"
        fi
        apt update -qq 2>/dev/null || print_warning "apt update failed (maybe not Debian/Ubuntu)."
    else
        print_warning "No suitable mirror found."
    fi
}

# Fix CRLF in downloaded files
fix_crlf() {
    print_step "Fixing line endings (removing CRLF)..."
    local fixed=0
    for file in *.sh; do
        [[ -f "$file" ]] || continue
        if grep -q $'\r$' "$file"; then
            sed -i 's/\r$//' "$file"
            print_success "Fixed: $file"
            ((fixed++))
        else
            print_info "Already LF: $file"
        fi
    done
    if [[ $fixed -eq 0 ]]; then
        print_info "No files needed fixing."
    else
        print_success "All files now have LF line endings."
    fi
}

# Banner
banner() {
    echo -e "${MAGENTA}"
    cat <<'EOF'
████████╗██████╗ ██╗   ██╗███╗   ███╗ █████╗
╚══██╔══╝██╔══██╗██║   ██║████╗ ████║██╔══██╗
   ██║   ██████╔╝██║   ██║██╔████╔██║███████║
   ██║   ██╔══██╗██║   ██║██║╚██╔╝██║██╔══██║
   ██║   ██║  ██║╚██████╔╝██║ ╚═╝ ██║██║  ██║
   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝
          Truma Tunnel Manager Installer
EOF
    echo -e "${NC}"
}

# Location menu (exactly like working version)
location_menu() {
    clear
    banner
    echo
    render_box "Server Location" "Please select your server location:\n\n    1) Inside Iran\n    2) Kharj (Outside Iran)\n\nDefault: 1"
    echo
    echo -ne "${YELLOW}Choice [1 or 2] (default: 1): ${NC}"
    read -r choice
    choice="${choice:-1}"
    echo

    case "$choice" in
        1)
            print_info "Server is inside Iran. Applying optimizations..."
            IRAN_OPTIMIZE=1
            ;;
        2)
            print_info "Server is outside Iran. Skipping optimizations."
            IRAN_OPTIMIZE=0
            ;;
        *)
            print_error "Invalid choice. Please enter 1 or 2."
            pause_enter
            location_menu
            return
            ;;
    esac
    pause_enter
}

# Main
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) AUTO_YES=1; shift ;;
            *) break ;;
        esac
    done

    mkdir -p "$(dirname "$INSTALL_LOG")"
    touch "$INSTALL_LOG"

    location_menu

    clear
    banner
    echo

    [[ $EUID -eq 0 ]] || die "This script must be run as root."

    # Install essential commands (fail if these cannot be installed)
    ensure_cmd curl curl
    ensure_cmd ping iputils-ping

    # Iran optimizations (all optional, failures become warnings)
    if [[ $IRAN_OPTIMIZE -eq 1 ]]; then
        disable_ipv6
        select_best_dns
        apply_kernel_tuning
        smart_mirror_optimizer
    else
        print_info "Skipping Iran optimizations."
    fi

    # Download files from release (using version from top)
    clear
    banner
    echo
    render_box "Downloading Files" "Truma Tunnel Manager $RELEASE_VERSION\n\n• truma.sh\n• gre-manager.sh\n• paqet.sh\n• mesh-manager.sh\n• haproxy-manager.sh"
    echo

    local base_url="https://github.com/efikhan/Truma-Tunnel/releases/download/$RELEASE_VERSION"
    local files=("truma.sh" "gre-manager.sh" "paqet.sh" "mesh-manager.sh" "haproxy-manager.sh")
    local tmpdir="$(mktemp -d)"

    for file in "${files[@]}"; do
        echo -n "  $file ... "
        if curl -fSL --connect-timeout 15 -o "$tmpdir/$file" "$base_url/$file" 2>/dev/null; then
            mv "$tmpdir/$file" "./$file"
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
            rm -rf "$tmpdir"
            die "Failed to download $file from GitHub release $RELEASE_VERSION."
        fi
    done
    rm -rf "$tmpdir"

    print_step "Setting execute permissions..."
    chmod 0755 "${files[@]}"

    fix_crlf

    echo
    render_box "Installation Complete" "All optimizations applied (where possible).\nAll files ready.\nCRLF issues fixed.\n\nRun ./truma.sh"
    echo
    read -r -p "Press ENTER to start Truma Tunnel Manager..."
    exec "./truma.sh"
}

main "$@"