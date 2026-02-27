#!/usr/bin/env bash

=============================================================================

install.sh – Truma Tunnel Manager Installer (fixed)

Version: 2.1.5-fixed

- All here-doc + "|| { ... }" anti-patterns fixed

- Preserves previous UI & behavior (Iran optimizations, fallback downloads, CRLF fix)

- Safer file writes, backups, robust logging

=============================================================================

set -euo pipefail IFS=$'\n\t'

---------------------------

Configuration

---------------------------

INSTALL_DIR="/opt/truma" REPO_URL="https://github.com/efikhan/Truma-Tunnel.git" FALLBACK_BASE_URL="https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main" MIRROR_BASE_URL="https://hub.fastgit.xyz/efikhan/Truma-Tunnel/raw/main" FILES=( "truma.sh" "gre-manager.sh" "paqet.sh" "mesh-manager.sh" "haproxy-manager.sh" "install.sh" ) LOG_FILE="/var/log/truma-full-install.log" MIN_DISK_MB=50 RELEASE_VERSION="v2.1.1"

Colors

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m' CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

---------------------------

Logging helpers

---------------------------

log() { local msg="$1" local ts ts="$(date '+%Y-%m-%d %H:%M:%S')" printf "%s - %s\n" "$ts" "$msg" >>"$LOG_FILE" 2>/dev/null || true printf "%s\n" "$msg" } print_step()   { log "[] $1"; printf "${CYAN}[]${NC} %s\n" "$1"; } print_success(){ log "[✓] $1"; printf "${GREEN}[✓]${NC} %s\n" "$1"; } print_warning(){ log "[!] $1"; printf "${YELLOW}[!]${NC} %s\n" "$1"; } print_error()  { log "[✗] $1"; printf "${RED}[✗]${NC} %s\n" "$1"; exit 1; } print_info()   { log "[i] $1"; printf "${CYAN}[i]${NC} %s\n" "$1"; }

---------------------------

Utility helpers

---------------------------

check_root() { if [[ $EUID -ne 0 ]]; then print_step "This installer requires root. Re-running with sudo..." exec sudo bash "$0" "$@" fi }

detect_package_manager() { if command -v apt-get &>/dev/null; then echo "apt-get" elif command -v yum &>/dev/null; then echo "yum" elif command -v dnf &>/dev/null; then echo "dnf" elif command -v pacman &>/dev/null; then echo "pacman" elif command -v apk &>/dev/null; then echo "apk" else echo "" fi }

run_cmd() { # usage: run_cmd <cmd-array...> [--no-fail] [--timeout N] local nofail=0 timeout_sec=0 local -a parts=() while [[ $# -gt 0 ]]; do case "$1" in --no-fail) nofail=1; shift;; --timeout) timeout_sec="$2"; shift 2;; *) parts+=("$1"); shift;; esac done

if (( timeout_sec > 0 )); then
    if ! command -v timeout &>/dev/null; then
        # If no timeout binary, run without timeout
        :
    else
        parts=( "timeout" "$timeout_sec" "${parts[@]}" )
    fi
fi

print_step "Running: ${parts[*]}"
local out
if out="$( "${parts[@]}" 2>&1 )"; then
    printf "%s\n" "$out"
    return 0
else
    local rc=$?
    if (( nofail )); then
        print_warning "Command failed (rc=$rc), continuing: ${parts[*]}"
        printf "%s\n" "$out"
        return $rc
    else
        print_error "Command failed (rc=$rc): ${parts[*]}"
    fi
fi

}

install_packages() { local pm="$1"; shift local pkgs=( "$@" ) case "$pm" in apt-get) run_cmd apt-get update --no-fail --timeout 60 || true run_cmd apt-get install -y "${pkgs[@]}" ;; yum|dnf) run_cmd "$pm" install -y "${pkgs[@]}" ;; pacman) run_cmd pacman -Syu --noconfirm "${pkgs[@]}" ;; apk) run_cmd apk add --no-cache "${pkgs[@]}" ;; *) print_warning "Unknown package manager: $pm" return 1 ;; esac }

backup_file() { local f="$1" if [[ -f "$f" ]]; then local bak="${f}.truma.bak.$(date +%s)" cp -a "$f" "$bak" && print_info "Backed up $f -> $bak" fi }

check_disk_space() { local need_mb="${1:-$MIN_DISK_MB}" local avail_mb avail_mb=$(( $(df --output=avail -m / | tail -1) )) if (( avail_mb < need_mb )); then print_error "Insufficient disk space: need ${need_mb}MB, have ${avail_mb}MB" fi print_info "Disk space OK: ${avail_mb}MB available" }

---------------------------

Iran-specific optimizations

---------------------------

disable_ipv6() { print_step "Disabling IPv6 (best-effort)..." if ! command -v sysctl &>/dev/null; then print_warning "sysctl not found; skipping IPv6 disable" return 0 fi

backup_file /etc/sysctl.d/99-ipv6-disable.conf
# Safe here-doc write with if-block
if ! cat > /etc/sysctl.d/99-ipv6-disable.conf <<'EOF'; then

net.ipv6.conf.all.disable_ipv6 = 1 net.ipv6.conf.default.disable_ipv6 = 1 net.ipv6.conf.lo.disable_ipv6 = 1 EOF then print_warning "Could not write /etc/sysctl.d/99-ipv6-disable.conf" return 0 fi

# Try immediate disable; don't fail installer if it doesn't work
run_cmd sysctl -w net.ipv6.conf.all.disable_ipv6=1 --no-fail || true
run_cmd sysctl -w net.ipv6.conf.default.disable_ipv6=1 --no-fail || true
run_cmd sysctl -p /etc/sysctl.d/99-ipv6-disable.conf --no-fail || true
print_success "IPv6 disable attempted (persisted in sysctl.d if supported)."

}

select_best_dns() { print_step "Testing DNS servers (best-effort, may take a few seconds)..." if ! command -v dig &>/dev/null; then print_warning "dig not installed; skipping DNS tests" return 0 fi

local dns_list=(
    "178.22.122.100|Shekan"
    "185.51.200.2|Shekan"
    "78.157.42.100|Electro"
    "78.157.42.101|Electro"
    "185.55.226.26|Begzar"
    "185.55.225.25|Begzar"
    "5.202.100.100|Pishgaman"
    "5.202.100.101|Pishgaman"
    "94.103.125.157|Shelter"
    "94.103.125.158|Shelter"
)
local best_dns="" best_time=999999
for entry in "${dns_list[@]}"; do
    local dns="${entry%%|*}"
    local name="${entry#*|}"
    printf "  Testing %s (%s) ... " "$name" "$dns"
    local out
    out="$( timeout 3 dig +time=2 +tries=1 google.com @"$dns" 2>/dev/null || true )"
    if [[ -n "$out" ]]; then
        local t
        t="$(printf "%s" "$out" | awk -F':' '/Query time:/{gsub(/[^0-9]/,"",$2); print $2; exit}' | tr -d '[:space:]')"
        if [[ -n "$t" && "$t" =~ ^[0-9]+$ ]]; then
            printf "%sms\n" "$t"
            if (( t < best_time )); then best_time=$t; best_dns=$dns; fi
        else
            printf "no time\n"
        fi
    else
        printf "failed\n"
    fi
done

if [[ -z "$best_dns" ]]; then
    print_warning "No DNS selected; leaving existing resolv.conf"
    return 0
fi

print_success "Selected DNS: $best_dns (${best_time} ms)"
backup_file /etc/resolv.conf

# Try to configure systemd-resolved if present
if systemctl list-units --type=service --all | grep -q systemd-resolved; then
    backup_file /etc/systemd/resolved.conf
    if cat > /etc/systemd/resolved.conf <<EOF; then

[Resolve] DNS=$best_dns 8.8.8.8 1.1.1.1 EOF run_cmd systemctl restart systemd-resolved --no-fail || true print_success "Configured systemd-resolved with chosen DNS" return 0 else print_warning "Could not write resolved.conf" fi fi

# Fallback: write /etc/resolv.conf (best effort)
if chattr -i /etc/resolv.conf 2>/dev/null || true; then
    if cat > /etc/resolv.conf <<EOF; then

Set by Truma Installer

nameserver $best_dns nameserver 8.8.8.8 nameserver 1.1.1.1 EOF print_success "/etc/resolv.conf updated" else print_warning "Failed to write /etc/resolv.conf" fi fi }

select_best_mirror() { print_step "Testing mirrors (best-effort)" local distro="ubuntu" codename="focal" if [[ -f /etc/os-release ]]; then . /etc/os-release distro="${ID:-ubuntu}" codename="${VERSION_CODENAME:-$codename}" fi

local mirrors=( "mirror.iranserver.com" "ir.ubuntu.sindad.cloud" "mirror.arvancloud.ir" "archive.ubuntu.petiak.ir" "ubuntu.hostiran.ir" "mirrors.pardisco.co" "ubuntu.pars.host" "mirror.0-1.cloud" "repo.linuxmirrors.ir" "ubuntu.shatel.ir" "archive.ubuntu.com" )
local best_mirror="" best_speed=0
for m in "${mirrors[@]}"; do
    printf "  Testing %s ... " "$m"
    local url
    if [[ "$distro" == "ubuntu" || "$distro" == "debian" ]]; then
        url="http://${m}/ubuntu/dists/${codename}/InRelease"
    else
        url="http://${m}/"
    fi
    local speed
    speed="$(curl -s -w '%{speed_download}' -o /dev/null --max-time 5 "$url" 2>/dev/null || echo 0)"
    speed="$(awk "BEGIN{print int(${speed:-0}/1024)}")"
    if (( speed > 0 )); then
        printf "%s KB/s\n" "$speed"
        if (( speed > best_speed )); then best_speed=$speed; best_mirror=$m; fi
    else
        printf "failed\n"
    fi
done

if [[ -n "$best_mirror" ]]; then
    print_success "Best mirror: $best_mirror (${best_speed} KB/s)"
    if [[ -f /etc/apt/sources.list && ( "$distro" == "ubuntu" || "$distro" == "debian" ) ]]; then
        backup_file /etc/apt/sources.list
        if sed -E -i "s@https?://[^/]+/ubuntu@http://$best_mirror/ubuntu@g" /etc/apt/sources.list 2>/dev/null; then
            run_cmd apt-get update --no-fail || true
            print_success "APT sources updated to use fastest mirror"
        fi
    fi
else
    print_warning "No mirror selected"
fi

}

apply_kernel_tuning() { print_step "Applying kernel network tuning (best-effort)..." if ! command -v sysctl &>/dev/null; then print_warning "sysctl not available; skipping kernel tuning" return 0 fi backup_file /etc/sysctl.d/99-network-performance.conf

if ! cat > /etc/sysctl.d/99-network-performance.conf <<'EOF'; then

Truma network performance tunings

net.core.rmem_max = 134217728 net.core.wmem_max = 134217728 net.ipv4.tcp_rmem = 4096 87380 134217728 net.ipv4.tcp_wmem = 4096 65536 134217728 net.core.netdev_max_backlog = 5000 net.ipv4.tcp_fastopen = 3 net.ipv4.tcp_slow_start_after_idle = 0 EOF then print_warning "Could not write kernel tuning file" fi

# try enabling BBR if available (non-fatal)
if modprobe tcp_bbr 2>/dev/null; then
    if ! sed -n 's/^/ /p' /dev/null >/dev/null 2>&1; then :; fi
    # append BBR lines if won't break
    if ! grep -q '^net.ipv4.tcp_congestion_control' /etc/sysctl.d/99-network-performance.conf 2>/dev/null; then
        printf "\nnet.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n" >> /etc/sysctl.d/99-network-performance.conf || true
    fi
else
    print_warning "BBR not available on this kernel"
fi

run_cmd sysctl -p /etc/sysctl.d/99-network-performance.conf --no-fail || true
print_success "Kernel tuning applied (where supported)"

}

---------------------------

Dependencies

---------------------------

install_dependencies() { print_step "Installing dependencies (curl, git, iproute2, iptables, dnsutils/dig, openssl)..." local pm pm="$(detect_package_manager)" if [[ -z "$pm" ]]; then print_warning "No supported package manager found. Please install the following manually: curl git iproute2 iptables openssl dnsutils" return 0 fi

local packages=()
case "$pm" in
    apt-get) packages=(curl git iproute2 iptables openssl dnsutils) ;;
    yum|dnf) packages=(curl git iproute iptables openssl bind-utils) ;;
    pacman) packages=(curl git iproute2 iptables openssl bind) ;;
    apk) packages=(curl git iproute2 iptables openssl bind-tools) ;;
    *) packages=(curl git iproute2 iptables openssl dnsutils) ;;
esac

install_packages "$pm" "${packages[@]}" || print_warning "Some packages may have failed to install"
print_success "Dependencies installation attempted"

}

---------------------------

Download & install Truma

---------------------------

download_files_via_curl() { local base="$1" dest="$2" mkdir -p "$dest" local ok=0 for f in "${FILES[@]}"; do print_step "Downloading ${f} from ${base}/${f}" if ! curl -fL --connect-timeout 15 --max-time 60 -o "${dest}/${f}" "${base}/${f}" 2>/dev/null; then print_warning "Failed to download ${f} from ${base}" ok=1 break fi done return $ok }

install_truma() { print_step "Installing Truma into ${INSTALL_DIR}" check_disk_space 20

if [[ -d "$INSTALL_DIR" ]]; then
    local bak="/opt/truma.backup.$(date +%s)"
    mv "$INSTALL_DIR" "$bak"
    print_info "Existing installation moved to $bak"
fi
mkdir -p "$INSTALL_DIR"

local git_ok=1
if command -v git &>/dev/null; then
    print_step "Attempting git clone (30s timeout)..."
    local tmpd
    tmpd="$(mktemp -d)"
    if run_cmd git clone --depth 1 "$REPO_URL" "$tmpd" --timeout 30 --no-fail; then
        # move content
        rsync -a "$tmpd"/ "$INSTALL_DIR"/
        rm -rf "$tmpd"
        print_success "Cloned repository via git"
        git_ok=0
    else
        print_warning "git clone failed or timed out; will try direct download"
        rm -rf "$tmpd"
        git_ok=1
    fi
else
    print_warning "git not installed; trying direct download"
fi

if (( git_ok == 1 )); then
    print_step "Trying mirror download (fastgit)"
    if download_files_via_curl "$MIRROR_BASE_URL" "$INSTALL_DIR"; then
        print_success "Downloaded files from mirror"
    else
        print_step "Trying raw.githubusercontent.com fallback"
        if download_files_via_curl "$FALLBACK_BASE_URL" "$INSTALL_DIR"; then
            print_success "Downloaded files from raw.githubusercontent.com"
        else
            print_error "All download methods failed. Check network or mirror accessibility."
        fi
    fi
fi

# Convert CRLF to LF in scripts, set perms
print_step "Fixing CRLF and setting execute perms"
for sh in "$INSTALL_DIR"/*.sh; do
    if [[ -f "$sh" ]]; then
        sed -i 's/\r$//' "$sh" || true
        chmod 0755 "$sh" || true
    fi
done

print_success "Truma installed to $INSTALL_DIR"
return 0

}

---------------------------

UI / Menu

---------------------------

banner() { printf "${MAGENTA}" cat <<'EOF' ████████╗██████╗ ██╗   ██╗███╗   ███╗ █████╗ ╚══██╔══╝██╔══██╗██║   ██║████╗ ████║██╔══██╗ ██║   ██████╔╝██║   ██║██╔████╔██║███████║ ██║   ██╔══██╗██║   ██║██║╚██╔╝██║██╔══██║ ██║   ██║  ██║╚██████╔╝██║ ╚═╝ ██║██║  ██║ ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝ Truma - Tunnel Manager Installer EOF printf "${NC}" }

location_menu() { while true; do banner echo printf "Select server location:\n" printf "  1) Inside Iran\n" printf "  2) Outside Iran (Kharj)\n" read -r -p "Choice [1-2] (default 1): " choice choice="${choice:-1}" case "$choice" in 1) echo "iran"; return 0 ;; 2) echo "kharj"; return 0 ;; *) print_warning "Please enter 1 or 2";; esac done }

---------------------------

Main

---------------------------

main() { check_root

local loc
loc="$(location_menu)"
print_info "Selected location: $loc"

# disable ipv6 early if Iran
if [[ "$loc" == "iran" ]]; then
    disable_ipv6
fi

# install deps
install_dependencies

# Iran post-deps optimizations
if [[ "$loc" == "iran" ]]; then
    select_best_dns
    select_best_mirror
    apply_kernel_tuning
fi

# install truma
install_truma

# Launch truma.sh (use bash explicitly)
local truma_script="${INSTALL_DIR}/truma.sh"
if [[ -x "$truma_script" ]]; then
    print_step "Launching Truma: $truma_script"
    exec /bin/bash "$truma_script"
else
    if [[ -f "$truma_script" ]]; then
        chmod +x "$truma_script" || true
        print_step "Launching Truma (made executable): $truma_script"
        exec /bin/bash "$truma_script"
    else
        print_error "truma.sh not found after install in ${INSTALL_DIR}"
    fi
fi

}

kick off

main "$@"
