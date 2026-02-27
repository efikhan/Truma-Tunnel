#!/usr/bin/env bash
# =============================================================================
# Truma Tunnel Manager – Professional Installer (Complete Edition)
# Includes: IPv6 Disable, DNS Optimizer, Kernel Tuning, Smart Mirror
# Robust error handling – will not stop on optional failures
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
        apt-get update -qq 2>/dev/null && apt-get install -y -qq "$pkg" 2>/dev/null
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
    print_step "Testing Iranian DNS servers..."

    if ! command -v dig >/dev/null 2>&1; then
        print_warning "dig not found – skipping DNS optimization."
        return
    fi

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

    # BBR
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

    local codename
    codename=$(lsb_release -sc 2>/dev/null || echo "noble")

    local mirrors=(
        "mirror.iranserver.com"
        "ir.ubuntu.sindad.cloud"
        "mirror.arvancloud.ir"
        "archive.ubuntu.petiak.ir"
        "ubuntu.hostiran.ir"
        "mirrors.pardisco.co"
        "ubuntu.pars.host"
        "mirror.0-1.cloud"
        "repo.linuxmirrors.ir"
        "ubuntu.shatel.ir"
        "archive.ubuntu.com"
        "mirrors.edge.kernel.org"
        "mirrors.aliyun.com"
        "mirror.ubuntu.com"
    )

    local best_mirror=""
    local best_speed=0

    for mirror in "${mirrors[@]}"; do
        echo -n "  Testing $mirror ... "
        local speed
        speed=$(curl -s -w "%{speed_download}" -o /dev/null --max-time 8 \
            "http://${mirror}/ubuntu/dists/${codename}/InRelease" 2>/dev/null \
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

    if [[ -f /etc/apt/sources.list ]]; then
        backup_file /etc/apt/sources.list
        sed -i \
            "s|http://[a-zA-Z0-9.\-]*/ubuntu|http://${best_mirror}/ubuntu|g" \
            /etc/apt/sources.list 2>/dev/null \
            || print_warning "Could not update sources.list"
    fi

    apt-get update -qq 2>/dev/null || print_warning "apt update failed (maybe not Debian/Ubuntu)."
}

# ─── Fix CRLF ─────────────────────────────────────────────────────────────────
fix_crlf() {
    print_step "Fixing line endings (removing CRLF)..."
    local fixed=0

    for file in *.sh; do
        [[ -f "$file" ]] || continue
        if grep -qP '\r$' "$file" 2>/dev/null; then
            sed -i 's/\r$//' "$file" && {
                print_success "Fixed: $file"
                (( fixed++ )) || true
            }
        else
            print_info "Already LF: $file"
        fi
    done

    if [[ "$fixed" -eq 0 ]]; then
        print_info "No files needed fixing."
    else
        print_success "$fixed file(s) now have LF line endings."
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
            -o "${tmpdir}/${file}" "${base_url}/${file}" 2>/dev/null
        then
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

    fix_crlf
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

    location_menu

    clear
    banner
    echo

    print_step "Checking required commands..."
    ensure_cmd curl curl
    ensure_cmd ping  iputils-ping
    print_success "All required commands available."
    echo

    # Iran optimizations (all optional)
    if [[ "$IRAN_OPTIMIZE" -eq 1 ]]; then
        disable_ipv6
        echo
        select_best_dns
        echo
        apply_kernel_tuning
        echo
        smart_mirror_optimizer
        echo
    else
        print_info "Skipping Iran-specific optimizations."
        echo
    fi

    # Download files
    download_release_files

    echo
    render_box "Installation Complete ✓" \
        "" \
        "  All optimizations applied (where possible)." \
        "  All scripts downloaded and ready." \
        "  CRLF issues fixed." \
        "" \
        "  Run: ./truma.sh" \
        ""
    echo

    read -r -p "Press ENTER to start Truma Tunnel Manager..."
    exec "./truma.sh"
}

main "$@"
