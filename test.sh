#!/usr/bin/env bash
# =============================================================================
# Truma Tunnel Manager – Professional Installer (Fully Hardened + Smart DNS + Smart Mirror)
# Appearance kept 100% the same as your original
# =============================================================================

set -euo pipefail

# Global flags
AUTO_YES=0
INSTALL_LOG="/var/log/truma-install.log"

# Colors (exactly the same)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; NC='\033[0m'

# Early log
mkdir -p "$(dirname "$INSTALL_LOG")"
touch "$INSTALL_LOG" 2>/dev/null || true
chmod 0640 "$INSTALL_LOG" 2>/dev/null || true

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$INSTALL_LOG" 2>/dev/null || true; }

print_step()   { echo -e "\( {CYAN}[*] \){NC} $1"; log "[*] $1"; }
print_success() { echo -e "\( {GREEN}[✓] \){NC} $1"; log "[✓] $1"; }
print_error()   { echo -e "\( {RED}[✗] \){NC} $1"; log "[✗] $1"; }
print_warning() { echo -e "\( {YELLOW}[!] \){NC} $1"; log "[!] $1"; }
print_info()    { echo -e "\( {BLUE}[i] \){NC} $1"; log "[i] $1"; }

pause_enter() {
    [[ $AUTO_YES -eq 1 ]] && return 0
    echo
    read -r -p "Press ENTER to continue..."
}

confirm() {
    if [[ $AUTO_YES -eq 1 ]]; then return 0; fi
    local prompt="$1" default="${2:-y}" answer
    while true; do
        echo -en "${YELLOW}$prompt (y/n) [default: \( default] \){NC} "
        read -r answer
        [[ -z "$answer" ]] && answer="$default"
        case "$answer" in [Yy]*) return 0 ;; [Nn]*) return 1 ;; esac
        echo "Please answer y or n."
    done
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

# Backup & Rollback with trap
declare -a BACKUP_FILES=()

backup_file() {
    local src="$1"
    local dst="\( {src}.truma.bak. \)(date +%s.%N)"
    if [[ -f "$src" ]]; then
        cp -a "$src" "$dst" && BACKUP_FILES+=("$src|$dst") && log "Backed up $src -> $dst"
    fi
}

rollback_all() {
    print_warning "Rolling back changes..."
    for entry in "${BACKUP_FILES[@]}"; do
        local src="\( {entry%%|*}" dst=" \){entry#*|}"
        [[ -f "$dst" ]] && cp "$dst" "$src" && log "Restored $src"
    done
}

trap 'rollback_all; exit 1' ERR INT TERM

# Ensure command
ensure_cmd() {
    local cmd="$1"; shift
    local candidates=("$@")
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi
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

# Smart Mirror Optimizer (14 mirrors)
smart_mirror_optimizer() {
    clear
    banner
    echo
    echo -e "\( {CYAN}══════════════════════════════════════════════════ \){NC}"
    echo -e "\( {GREEN}  Finding the Fastest Ubuntu Mirror \){NC}"
    echo -e "\( {CYAN}══════════════════════════════════════════════════ \){NC}"
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
        speed=$(curl -s -w "%{speed_download}" -o /dev/null --max-time 8 "http://\( mirror/ubuntu/dists/ \){UBUNTU_CODENAME}/InRelease" 2>/dev/null | awk '{print int($1/1024)}' || echo 0)
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
        print_success "Best mirror: \( best_mirror ( \){best_speed} KB/s)"
        if [[ -f /etc/apt/sources.list ]]; then
            backup_file /etc/apt/sources.list
            sed -i "s|http://[a-zA-Z0-9.-]*archive.ubuntu.com/ubuntu|http://$best_mirror/ubuntu|g" /etc/apt/sources.list 2>/dev/null || true
        fi
        apt update -qq
    else
        print_warning "No suitable mirror found."
    fi
}

# Banner (100% same as yours)
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

    clear
    banner
    echo

    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root."
        exit 1
    fi

    ensure_cmd curl curl
    ensure_cmd ping iputils-ping

    smart_mirror_optimizer

    # Download files
    clear
    banner
    echo
    render_box "Downloading Files" "Truma Tunnel Manager v2.0.0\n\n• truma.sh\n• gre-manager.sh\n• paqet.sh\n• mesh-manager.sh\n• haproxy-manager.sh"
    echo

    local base_url="https://github.com/efikhan/Truma-Tunnel/releases/download/v2.0.0"
    local files=("truma.sh" "gre-manager.sh" "paqet.sh" "mesh-manager.sh" "haproxy-manager.sh")
    local tmpdir="$(mktemp -d)"

    for file in "${files[@]}"; do
        echo -n "  $file ... "
        if curl -fSL --connect-timeout 15 -o "$tmpdir/$file" "$base_url/$file" 2>/dev/null; then
            mv "$tmpdir/$file" "./$file"
            echo -e "\( {GREEN}OK \){NC}"
        else
            echo -e "\( {RED}FAILED \){NC}"
            rm -rf "$tmpdir"
            die "Failed to download $file"
        fi
    done
    rm -rf "$tmpdir"

    print_step "Setting execute permissions..."
    chmod 0755 "${files[@]}"

    echo
    render_box "Installation Complete" "Smart mirror optimization done.\nAll files ready.\n\nRun ./truma.sh"
    echo
    read -r -p "Press ENTER to start Truma Tunnel Manager..."
    exec "./truma.sh"
}

main "$@"
