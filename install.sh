#!/usr/bin/env bash
# =============================================================================
# Truma Tunnel Manager – Professional Installer (Complete Edition)
# Version: 4.0
# Features:
#   - Location menu (Iran / Outside Iran)
#   - Iran: IPv6 Disable, DNS Optimizer, Kernel Tuning, Smart Mirror
#   - Outside: Install files + CRLF cleanup only
#   - Permanent multi-layer CRLF prevention system
#   - Robust error handling – will not stop on optional failures
#   - Comprehensive Iranian DNS and Ubuntu mirror lists
# =============================================================================

set -uo pipefail

# ─── Global Config ────────────────────────────────────────────────────────────
AUTO_YES=0
INSTALL_LOG="/var/log/truma-install.log"
IRAN_OPTIMIZE=0
RELEASE_VERSION="v2.1.1"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# ─── Log Setup ────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$INSTALL_LOG")" 2>/dev/null || true
touch "$INSTALL_LOG" 2>/dev/null || true
chmod 0640 "$INSTALL_LOG" 2>/dev/null || true

# ─── Logging & Print Helpers ──────────────────────────────────────────────────
log()           { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$INSTALL_LOG" 2>/dev/null || true; }
print_step()    { echo -e "${CYAN}[*]${NC} $*"; log "[*] $*"; }
print_success() { echo -e "${GREEN}[✓]${NC} $*"; log "[✓] $*"; }
print_error()   { echo -e "${RED}[✗]${NC} $*" >&2; log "[✗] $*"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $*"; log "[!] $*"; }
print_info()    { echo -e "${BLUE}[i]${NC} $*"; log "[i] $*"; }

die() {
    print_error "$*"
    exit 1
}

pause_enter() {
    [[ "$AUTO_YES" -eq 1 ]] && return 0
    echo
    read -r -p "Press ENTER to continue..."
}

# ─── Box Renderer ─────────────────────────────────────────────────────────────
render_box() {
    local title="$1"
    shift
    local lines=("$@")
    echo "┌──────────────────────────────────────────────────────────────┐"
    printf "│  %-60s  │\n" "$title"
    echo "├──────────────────────────────────────────────────────────────┤"
    for line in "${lines[@]}"; do
        printf "│  %-60s  │\n" "$line"
    done
    echo "└──────────────────────────────────────────────────────────────┘"
}

# ─── Backup & Rollback ────────────────────────────────────────────────────────
BACKUP_FILES=()

backup_file() {
    local src="$1"
    local dst="${src}.truma.bak.$(date +%s)"
    if [[ -f "$src" ]]; then
        if cp -a "$src" "$dst" 2>/dev/null; then
            BACKUP_FILES+=("${src}|${dst}")
            log "Backed up $src -> $dst"
        else
            print_warning "Could not back up $src"
        fi
    fi
}

rollback_all() {
    if [[ "${#BACKUP_FILES[@]}" -eq 0 ]]; then
        return 0
    fi
    print_warning "Rolling back changes..."
    for entry in "${BACKUP_FILES[@]}"; do
        local src="${entry%%|*}"
        local dst="${entry#*|}"
        if [[ -f "$dst" ]]; then
            cp "$dst" "$src" 2>/dev/null && log "Restored $src" || true
        fi
    done
}

# ─── Trap: Rollback on unexpected exit ────────────────────────────────────────
_trap_handler() {
    local code=$?
    [[ $code -eq 0 ]] && return
    rollback_all
    exit "$code"
}
trap '_trap_handler' EXIT
trap 'echo; die "Interrupted by user."' INT TERM

# ─── Package Installer ────────────────────────────────────────────────────────
install_pkg() {
    local pkg="$1"
    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg" 2>/dev/null
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q "$pkg" 2>/dev/null
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q "$pkg" 2>/dev/null
    else
        return 1
    fi
}

ensure_cmd() {
    local cmd="$1"
    shift
    local candidates=("$@")

    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    for pkg in "${candidates[@]}"; do
        print_step "Installing $pkg ..."
        if install_pkg "$pkg"; then
            if command -v "$cmd" >/dev/null 2>&1; then
                print_success "Installed $pkg (provides $cmd)"
                return 0
            fi
        fi
    done

    die "Could not install '$cmd'. Please install ${candidates[*]} manually."
}

# ─── Banner ───────────────────────────────────────────────────────────────────
banner() {
    echo -e "${MAGENTA}"
    cat <<'BANNER'
████████╗██████╗ ██╗   ██╗███╗   ███╗ █████╗
╚══██╔══╝██╔══██╗██║   ██║████╗ ████║██╔══██╗
   ██║   ██████╔╝██║   ██║██╔████╔██║███████║
   ██║   ██╔══██╗██║   ██║██║╚██╔╝██║██╔══██║
   ██║   ██║  ██║╚██████╔╝██║ ╚═╝ ██║██║  ██║
   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝
          Truma Tunnel Manager Installer
BANNER
    echo -e "${NC}"
}

# ─── Location Menu ────────────────────────────────────────────────────────────
location_menu() {
    clear
    banner
    echo
    render_box "Server Location" \
        "Please select your server location:" \
        "" \
        "    1) Inside Iran" \
        "    2) Outside Iran (Kharej)" \
        "" \
        "Default: 1"
    echo
    echo -ne "${YELLOW}Choice [1 or 2] (default: 1): ${NC}"

    local choice
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
            print_warning "Invalid choice. Please enter 1 or 2."
            pause_enter
            location_menu
            return
            ;;
    esac

    pause_enter
}

# ─── Iran Optimization 1: Disable IPv6 ───────────────────────────────────────
disable_ipv6() {
    print_step "Disabling IPv6 (optional)..."

    if ! command -v sysctl >/dev/null 2>&1; then
        print_warning "sysctl not found – skipping IPv6 disable."
        return
    fi

    local conf="/etc/sysctl.d/99-ipv6-disable.conf"
    backup_file "$conf"

    {
        echo "net.ipv6.conf.all.disable_ipv6 = 1"
        echo "net.ipv6.conf.default.disable_ipv6 = 1"
        echo "net.ipv6.conf.lo.disable_ipv6 = 1"
    } > "$conf" 2>/dev/null || {
        print_warning "Could not write IPv6 config – skipping."
        return
    }

    sysctl -w net.ipv6.conf.all.disable_ipv6=1     >/dev/null 2>&1 || print_warning "Could not disable IPv6 immediately (all)."
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
    sysctl -p "$conf"                               >/dev/null 2>&1 || print_warning "IPv6 persistence may not work."

    print_success "IPv6 disabled (if supported)."
}

# ─── Iran Optimization 2: Best DNS ───────────────────────────────────────────
select_best_dns() {
    print_step "Testing Iranian anti-censorship DNS servers..."

    if ! command -v dig >/dev/null 2>&1; then
        print_step "dig not found – attempting to install dnsutils..."
        install_pkg "dnsutils" 2>/dev/null || install_pkg "bind-utils" 2>/dev/null || true
        if ! command -v dig >/dev/null 2>&1; then
            print_warning "dig unavailable – skipping DNS optimization."
            return
        fi
    fi

    # Comprehensive Iranian anti-censorship DNS servers
    local dns_list=(
        "178.22.122.100|SheikhDNS-Primary"
        "185.51.200.2|SheikhDNS-Secondary"
        "10.202.10.202|RadarDNS-Primary"
        "10.202.10.10|RadarDNS-Secondary"
        "185.110.190.64|Beonline-Primary"
        "185.110.190.65|Beonline-Secondary"
        "5.202.100.100|Pishgaman-Primary"
        "5.202.100.101|Pishgaman-Secondary"
        "78.157.42.100|ElectroDNS-Primary"
        "78.157.42.101|ElectroDNS-Secondary"
        "185.55.226.26|Begzar-Primary"
        "185.55.225.25|Begzar-Secondary"
        "194.104.158.24|DNSir-Primary"
        "194.104.158.30|DNSir-Secondary"
        "37.156.223.253|Shatel-Primary"
        "37.156.223.254|Shatel-Secondary"
        "217.218.155.155|MCI-Primary"
        "217.218.127.127|MCI-Secondary"
        # International fallbacks
        "8.8.8.8|Google-Primary"
        "1.1.1.1|Cloudflare-Primary"
        "9.9.9.9|Quad9"
        "208.67.222.222|OpenDNS"
    )

    local best_dns=""
    local best_time=999999
    local test_domain="google.com"

    for entry in "${dns_list[@]}"; do
        local dns="${entry%%|*}"
        local name="${entry#*|}"
        echo -n "  Testing $name ($dns) ... "

        local raw_time
        raw_time=$(timeout 3 dig +time=2 +tries=1 "$test_domain" "@$dns" 2>/dev/null \
            | grep 'Query time:' | awk '{print $4}')
        local t="${raw_time//[!0-9]/}"

        if [[ -n "$t" && "$t" -gt 0 && "$t" -lt 9999 ]]; then
            echo "${t} ms"
            if [[ "$t" -lt "$best_time" ]]; then
                best_time=$t
                best_dns=$dns
            fi
        else
            echo "Failed"
        fi
    done

    if [[ -z "$best_dns" ]]; then
        print_warning "No reachable DNS found – using system default."
        return
    fi

    print_success "Best DNS: $best_dns (${best_time} ms)"

    # Apply DNS
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        backup_file /etc/systemd/resolved.conf
        {
            echo "[Resolve]"
            echo "DNS=${best_dns} 8.8.8.8 1.1.1.1"
            echo "FallbackDNS=9.9.9.9 208.67.222.222"
        } > /etc/systemd/resolved.conf 2>/dev/null || {
            print_warning "Could not write resolved.conf"
            return
        }
        systemctl restart systemd-resolved 2>/dev/null \
            || print_warning "Failed to restart systemd-resolved."
        print_success "DNS configured via systemd-resolved."
    else
        backup_file /etc/resolv.conf
        chattr -i /etc/resolv.conf 2>/dev/null || true
        {
            echo "# Set by Truma Installer"
            echo "nameserver ${best_dns}"
            echo "nameserver 8.8.8.8"
            echo "nameserver 1.1.1.1"
        } > /etc/resolv.conf 2>/dev/null || {
            print_warning "Could not write /etc/resolv.conf"
            return
        }
        print_success "DNS configured directly in resolv.conf."
    fi
}

# ─── Iran Optimization 3: Kernel Tuning ──────────────────────────────────────
apply_kernel_tuning() {
    print_step "Applying kernel network optimizations (optional)..."

    if ! command -v sysctl >/dev/null 2>&1; then
        print_warning "sysctl not found – skipping kernel tuning."
        return
    fi

    local conf="/etc/sysctl.d/99-network-performance.conf"
    backup_file "$conf"

    # BBR congestion control
    if command -v modprobe >/dev/null 2>&1 && modprobe tcp_bbr 2>/dev/null; then
        {
            echo "net.core.default_qdisc = fq"
            echo "net.ipv4.tcp_congestion_control = bbr"
        } >> "$conf" 2>/dev/null && print_success "BBR enabled." \
          || print_warning "Could not write BBR settings."
    else
        print_warning "BBR not available – using default congestion control."
    fi

    # Buffer & performance tunings
    {
        echo "net.core.rmem_max = 134217728"
        echo "net.core.wmem_max = 134217728"
        echo "net.ipv4.tcp_rmem = 4096 87380 134217728"
        echo "net.ipv4.tcp_wmem = 4096 65536 134217728"
        echo "net.core.netdev_max_backlog = 5000"
        echo "net.ipv4.tcp_fastopen = 3"
        echo "net.ipv4.tcp_slow_start_after_idle = 0"
        echo "net.ipv4.tcp_keepalive_time = 300"
        echo "net.ipv4.tcp_keepalive_intvl = 30"
        echo "net.ipv4.tcp_keepalive_probes = 3"
    } >> "$conf" 2>/dev/null || print_warning "Could not write kernel buffer settings."

    sysctl -p "$conf" >/dev/null 2>&1 \
        || print_warning "Some kernel parameters could not be applied."

    print_success "Kernel tuning applied (where possible)."
}

# ─── Iran Optimization 4: Smart Mirror ───────────────────────────────────────
smart_mirror_optimizer() {
    clear
    banner
    echo
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Finding the Fastest Ubuntu Mirror (Iran)${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo

    # ── Detect OS and release codename safely ─────────────────────────────────
    local codename=""
    local is_ubuntu=0

    # Method 1: /etc/os-release (most reliable, works on Ubuntu and Debian)
    if [[ -f /etc/os-release ]]; then
        local os_id
        os_id=$(. /etc/os-release && echo "${ID:-}" 2>/dev/null)
        if [[ "$os_id" == "ubuntu" ]]; then
            is_ubuntu=1
            codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}" 2>/dev/null)
        fi
    fi

    # Method 2: lsb_release fallback (only if ubuntu confirmed)
    if [[ "$is_ubuntu" -eq 1 && -z "$codename" ]]; then
        codename=$(lsb_release -sc 2>/dev/null || true)
    fi

    # Method 3: parse /etc/apt/sources.list for existing codename
    if [[ "$is_ubuntu" -eq 1 && -z "$codename" ]]; then
        codename=$(grep -m1 'deb.*ubuntu' /etc/apt/sources.list 2>/dev/null \
            | awk '{print $3}' | head -1 || true)
    fi

    # If not Ubuntu, skip mirror optimization entirely
    if [[ "$is_ubuntu" -eq 0 ]]; then
        print_warning "Mirror optimization is only supported on Ubuntu – skipping."
        return
    fi

    # Final fallback codename
    if [[ -z "$codename" || "$codename" == "n/a" ]]; then
        codename="noble"
        print_warning "Could not detect Ubuntu codename – defaulting to: $codename"
    else
        print_info "Detected Ubuntu codename: $codename"
    fi

    # ── Comprehensive Iranian + International Ubuntu mirrors ──────────────────
    local mirrors=(
        # Iranian mirrors
        "mirror.arvancloud.ir"
        "mirror.iranserver.com"
        "ir.ubuntu.sindad.cloud"
        "repo.iut.ac.ir"
        "mirrors.university-of-tehran.ir"
        "mirror.nic.ir"
        "archive.ubuntu.petiak.ir"
        "mirrors.pardisco.co"
        "ubuntu.pars.host"
        "ubuntu.shatel.ir"
        # International fallbacks
        "archive.ubuntu.com"
        "mirrors.edge.kernel.org"
    )

    local best_mirror=""
    local best_speed=0
    local test_path="ubuntu/dists/${codename}/InRelease"

    for mirror in "${mirrors[@]}"; do
        echo -n "  Testing $mirror ... "
        local speed
        speed=$(curl -s -w "%{speed_download}" -o /dev/null \
            --max-time 8 --connect-timeout 5 \
            "http://${mirror}/${test_path}" 2>/dev/null \
            | awk '{print int($1/1024)}')
        speed="${speed:-0}"

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

    echo

    if [[ -z "$best_mirror" ]]; then
        print_warning "No reachable mirror found – keeping current sources."
        return
    fi

    print_success "Best mirror: $best_mirror (${best_speed} KB/s)"

    # ── Update sources.list safely ────────────────────────────────────────────
    local sources_file="/etc/apt/sources.list"

    if [[ ! -f "$sources_file" ]]; then
        print_warning "sources.list not found – skipping mirror update."
        return
    fi

    backup_file "$sources_file"

    # Verify current sources.list is not empty
    if [[ ! -s "$sources_file" ]]; then
        print_warning "sources.list is empty – skipping mirror update."
        return
    fi

    # Replace mirror URLs only (do not touch release names or components)
    # Handles both http:// and https:// existing mirrors
    local tmp_sources
    tmp_sources=$(mktemp)

    sed \
        -e "s|https\?://archive\.ubuntu\.com/ubuntu|http://${best_mirror}/ubuntu|g" \
        -e "s|https\?://security\.ubuntu\.com/ubuntu|http://${best_mirror}/ubuntu|g" \
        -e "s|https\?://[a-zA-Z0-9._-]*/ubuntu|http://${best_mirror}/ubuntu|g" \
        "$sources_file" > "$tmp_sources" 2>/dev/null

    # Verify the result is valid (non-empty and has deb lines)
    if grep -q '^deb ' "$tmp_sources" 2>/dev/null; then
        mv "$tmp_sources" "$sources_file"
        chmod 0644 "$sources_file"
        print_success "sources.list updated to use: $best_mirror"
    else
        print_warning "Mirror update produced invalid sources.list – reverting."
        rm -f "$tmp_sources"
        return
    fi

    # ── apt update with error handling ────────────────────────────────────────
    print_step "Running apt update..."
    local apt_output
    if apt_output=$(DEBIAN_FRONTEND=noninteractive apt-get update 2>&1); then
        print_success "apt update succeeded."
    else
        # Check if the error is specifically about sources.list
        if echo "$apt_output" | grep -q "The list of sources could not be read"; then
            print_warning "apt update failed – reverting to backup mirror."
            # Restore original sources.list
            local latest_bak
            latest_bak=$(find /etc/apt -name "sources.list.truma.bak.*" \
                -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
            if [[ -n "$latest_bak" && -f "$latest_bak" ]]; then
                cp "$latest_bak" "$sources_file"
                DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true
                print_info "Reverted to original sources.list."
            fi
        else
            print_warning "apt update had warnings (non-fatal): continuing."
        fi
    fi
}

# ─── Permanent CRLF Prevention System ────────────────────────────────────────
install_crlf_guard() {
    print_step "Installing permanent CRLF prevention system..."

    # Layer 1: Git config (global)
    if command -v git >/dev/null 2>&1; then
        git config --global core.autocrlf false        2>/dev/null || true
        git config --global core.eol lf               2>/dev/null || true
        git config --global core.safecrlf false        2>/dev/null || true
        git config --system core.autocrlf false        2>/dev/null || true
        git config --system core.eol lf               2>/dev/null || true
        print_success "Git global CRLF settings applied."
    fi

    # Layer 2: .gitattributes in install directory
    local install_dir
    install_dir="$(pwd)"
    if [[ -d "${install_dir}/.git" ]] || true; then
        cat > "${install_dir}/.gitattributes" 2>/dev/null <<'GITATTR'
# Force LF for all shell scripts and text files
*.sh    text eol=lf
*.py    text eol=lf
*.txt   text eol=lf
*.conf  text eol=lf
*.yaml  text eol=lf
*.yml   text eol=lf
*.json  text eol=lf
*.md    text eol=lf
*       text=auto eol=lf
GITATTR
        print_success "Created .gitattributes in install directory."
    fi

    # Layer 3: systemd service for ongoing protection
    if command -v systemctl >/dev/null 2>&1 && \
       [[ -d /etc/systemd/system ]]; then

        cat > /etc/systemd/system/truma-crlf-guard.service 2>/dev/null <<SVCFILE
[Unit]
Description=Truma CRLF Guard – keeps shell scripts LF-only
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${install_dir}
ExecStart=/bin/bash -c 'find "${install_dir}" -maxdepth 2 -name "*.sh" -exec sed -i "s/\\r\$//" {} +'
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCFILE

        systemctl daemon-reload                    2>/dev/null || true
        systemctl enable truma-crlf-guard.service  2>/dev/null || true
        systemctl start  truma-crlf-guard.service  2>/dev/null || true
        print_success "CRLF guard service installed and enabled."
    fi
}

# ─── Fix CRLF in Downloaded Files ────────────────────────────────────────────
fix_crlf() {
    print_step "Scanning and fixing line endings (removing CRLF)..."
    local fixed=0
    local checked=0

    # Fix all .sh files in current directory
    for file in *.sh; do
        [[ -f "$file" ]] || continue
        (( checked++ )) || true

        if grep -qP '\r$' "$file" 2>/dev/null || \
           grep -qP '\r' "$file" 2>/dev/null; then
            sed -i 's/\r//' "$file" && {
                print_success "Fixed CRLF: $file"
                (( fixed++ )) || true
            } || print_warning "Could not fix: $file"
        else
            print_info "Already LF: $file"
        fi
    done

    # Verify all files are now CRLF-free
    local remaining=0
    for file in *.sh; do
        [[ -f "$file" ]] || continue
        if grep -qP '\r' "$file" 2>/dev/null; then
            print_warning "Still has CRLF after fix: $file (force-fixing)"
            tr -d '\r' < "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
            (( remaining++ )) || true
        fi
    done

    if [[ "$fixed" -eq 0 && "$remaining" -eq 0 ]]; then
        print_info "All $checked file(s) already have LF line endings."
    else
        print_success "$fixed file(s) fixed. All scripts are now CRLF-free."
    fi
}

# ─── Download Release Files ───────────────────────────────────────────────────
download_release_files() {
    clear
    banner
    echo

    render_box "Downloading Files – Truma Tunnel Manager $RELEASE_VERSION" \
        "" \
        "  • truma.sh" \
        "  • gre-manager.sh" \
        "  • paqet.sh" \
        "  • mesh-manager.sh" \
        "  • haproxy-manager.sh" \
        ""
    echo

    local base_url="https://github.com/efikhan/Truma-Tunnel/releases/download/${RELEASE_VERSION}"
    local files=(
        "truma.sh"
        "gre-manager.sh"
        "paqet.sh"
        "mesh-manager.sh"
        "haproxy-manager.sh"
    )

    local tmpdir
    tmpdir="$(mktemp -d)"

    for file in "${files[@]}"; do
        echo -n "  Downloading $file ... "
        if curl -fsSL --connect-timeout 15 --retry 3 \
            -o "${tmpdir}/${file}" "${base_url}/${file}" 2>/dev/null; then
            mv "${tmpdir}/${file}" "./${file}"
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
    print_success "Permissions set."

    # Remove CRLF from all downloaded files
    fix_crlf

    # Install permanent CRLF guard
    install_crlf_guard
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) AUTO_YES=1; shift ;;
            --) shift; break ;;
            *) break ;;
        esac
    done

    # Root check
    [[ "$EUID" -eq 0 ]] || die "This script must be run as root (use sudo)."

    # Show location menu first
    location_menu

    clear
    banner
    echo

    print_step "Checking required commands..."
    ensure_cmd curl curl
    ensure_cmd ping  iputils-ping
    print_success "All required commands available."
    echo

    # ── Iran-only optimizations ───────────────────────────────────────────────
    if [[ "$IRAN_OPTIMIZE" -eq 1 ]]; then
        print_step "Applying Iran-specific optimizations..."
        echo

        disable_ipv6
        echo

        select_best_dns
        echo

        apply_kernel_tuning
        echo

        smart_mirror_optimizer
        echo

        print_success "All Iran optimizations applied."
        echo
    else
        print_info "Outside Iran selected – skipping all optimizations."
        print_info "Proceeding with file installation and CRLF cleanup only."
        echo
    fi

    # ── Download files (always runs for both locations) ───────────────────────
    download_release_files

    echo
    if [[ "$IRAN_OPTIMIZE" -eq 1 ]]; then
        render_box "Installation Complete ✓" \
            "" \
            "  Location  : Inside Iran" \
            "  IPv6      : Disabled" \
            "  DNS       : Optimized (fastest Iranian DNS)" \
            "  Kernel    : Tuned for better performance" \
            "  Mirror    : Switched to fastest Iranian mirror" \
            "  Files     : Downloaded and ready" \
            "  CRLF      : Cleaned (permanent guard active)" \
            "" \
            "  Run: ./truma.sh" \
            ""
    else
        render_box "Installation Complete ✓" \
            "" \
            "  Location  : Outside Iran" \
            "  Files     : Downloaded and ready" \
            "  CRLF      : Cleaned (permanent guard active)" \
            "" \
            "  Run: ./truma.sh" \
            ""
    fi
    echo

    read -r -p "Press ENTER to start Truma Tunnel Manager..."
    exec "./truma.sh"
}

main "$@"
