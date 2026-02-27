#!/bin/bash
# ================================================================
# Truma Tunnel Manager - Full Installer v3.0
# Optimized for Iranian Servers
# Author: efikhan
# GitHub: https://github.com/efikhan/Truma-Tunnel
# ================================================================

set -euo pipefail
IFS=$'\n\t'

# ────────────────────────────────────────────────────────────────
# Terminal Colors
# ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
RESET='\033[0m'

# ────────────────────────────────────────────────────────────────
# Global Variables
# ────────────────────────────────────────────────────────────────
INSTALL_DIR="/opt/truma"
CONFIG_DIR="/etc/truma"
LOG_DIR="/var/log/truma"
BACKUP_DIR="/var/backup/truma"
SERVICE_NAME="truma"
VERSION="3.0.0"
GITHUB_RAW="https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main"
GITHUB_REPO="https://github.com/efikhan/Truma-Tunnel"

# ────────────────────────────────────────────────────────────────
# Iranian DNS List (Anti-Censorship) + International Fallback
# ────────────────────────────────────────────────────────────────
IRANIAN_DNS_LIST=(
    # SheidDNS
    "178.22.122.100"
    "185.51.200.2"
    # RadarDNS
    "10.202.10.202"
    "10.202.10.102"
    # Beonline
    "185.55.226.26"
    "185.55.225.25"
    # Shatel
    "85.15.1.14"
    "85.15.1.15"
    # DNS.ir
    "194.104.158.48"
    "194.104.158.78"
    # Mokhابarat (MCI)
    "217.218.155.155"
    "217.218.127.127"
    # International Fallback
    "8.8.8.8"
    "8.8.4.4"
    "1.1.1.1"
    "1.0.0.1"
    "9.9.9.9"
    "4.2.2.4"
)

# ────────────────────────────────────────────────────────────────
# Iranian Ubuntu Mirror List
# ────────────────────────────────────────────────────────────────
MIRROR_LIST=(
    # ArvanCloud (Fastest in Iran)
    "http://mirror.arvancloud.ir/ubuntu/"
    # IranServer
    "http://mirror.iranserver.com/ubuntu/"
    # Official Iran Mirror
    "http://ir.archive.ubuntu.com/ubuntu/"
    # NIC Iran
    "http://mirrors.nic.ir/ubuntu/"
    # Isfahan University of Technology
    "http://repo.iut.ac.ir/repo/ubuntu/"
    # Razavi University
    "http://ubuntu.razavi.ac.ir/ubuntu/"
    # Amirkabir University
    "http://ftp.aut.ac.ir/ubuntu/"
    # Yazd University
    "http://ubuntu.yazd.ac.ir/ubuntu/"
    # ParsOnline
    "http://mirror.parsonline.com/ubuntu/"
    # Official Fallback
    "http://archive.ubuntu.com/ubuntu/"
)

# ────────────────────────────────────────────────────────────────
# Logging Functions
# ────────────────────────────────────────────────────────────────
log_info()    { echo -e "${GREEN}[INFO]${RESET}    ${WHITE}$1${RESET}"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}    ${YELLOW}$1${RESET}"; }
log_error()   { echo -e "${RED}[ERROR]${RESET}   ${RED}$1${RESET}"; }
log_step()    { echo -e "\n${CYAN}[STEP]${RESET}    ${BOLD}$1${RESET}"; }
log_success() { echo -e "${GREEN}[SUCCESS]${RESET} ${GREEN}${BOLD}$1${RESET}"; }
log_debug()   { echo -e "${BLUE}[DEBUG]${RESET}   ${BLUE}$1${RESET}"; }

# ────────────────────────────────────────────────────────────────
# Banner
# ────────────────────────────────────────────────────────────────
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "  ████████╗██████╗ ██╗   ██╗███╗   ███╗ █████╗ "
    echo "     ██╔══╝██╔══██╗██║   ██║████╗ ████║██╔══██╗"
    echo "     ██║   ██████╔╝██║   ██║██╔████╔██║███████║"
    echo "     ██║   ██╔══██╗██║   ██║██║╚██╔╝██║██╔══██║"
    echo "     ██║   ██║  ██║╚██████╔╝██║ ╚═╝ ██║██║  ██║"
    echo "     ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝"
    echo -e "${RESET}"
    echo -e "${MAGENTA}          ╔════════════════════════════════════╗${RESET}"
    echo -e "${MAGENTA}          ║   Tunnel Manager  v${VERSION}         ║${RESET}"
    echo -e "${MAGENTA}          ║   Optimized for Iranian Servers    ║${RESET}"
    echo -e "${MAGENTA}          ╚════════════════════════════════════╝${RESET}"
    echo ""
}

# ────────────────────────────────────────────────────────────────
# Check Root Access
# ────────────────────────────────────────────────────────────────
check_root() {
    log_step "Checking root privileges"
    if [[ $EUID -ne 0 ]]; then
        log_error "This script requires root privileges"
        log_warn "Usage: sudo bash install.sh"
        exit 1
    fi
    log_info "Root access confirmed"
}

# ────────────────────────────────────────────────────────────────
# Check Operating System
# ────────────────────────────────────────────────────────────────
check_os() {
    log_step "Checking operating system"
    if [[ ! -f /etc/os-release ]]; then
        log_error "Unsupported operating system"
        exit 1
    fi
    source /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        log_error "Only Ubuntu and Debian are supported (detected: $ID)"
        exit 1
    fi
    log_info "Operating system: $PRETTY_NAME"
}

# ────────────────────────────────────────────────────────────────
# Select Best DNS (Speed Test)
# ────────────────────────────────────────────────────────────────
select_best_dns() {
    log_step "Testing and selecting best DNS server"
    local best_dns=""
    local best_time=9999

    for dns in "${IRANIAN_DNS_LIST[@]}"; do
        local start_ms end_ms elapsed
        start_ms=$(date +%s%3N)
        if timeout 2 bash -c "echo >/dev/tcp/$dns/53" 2>/dev/null; then
            end_ms=$(date +%s%3N)
            elapsed=$((end_ms - start_ms))
            log_debug "DNS $dns -> ${elapsed}ms"
            if (( elapsed < best_time )); then
                best_time=$elapsed
                best_dns=$dns
            fi
        else
            log_debug "DNS $dns -> timeout"
        fi
    done

    if [[ -z "$best_dns" ]]; then
        log_warn "No DNS responded, using default fallback"
        best_dns="178.22.122.100"
    fi

    log_info "Best DNS selected: ${BOLD}$best_dns${RESET} (${best_time}ms)"
    echo "$best_dns"
}

# ────────────────────────────────────────────────────────────────
# Configure System DNS
# ────────────────────────────────────────────────────────────────
configure_dns() {
    log_step "Configuring system DNS"
    select_best_dns > /dev/null

    # Backup resolv.conf
    if [[ -f /etc/resolv.conf ]]; then
        cp /etc/resolv.conf /etc/resolv.conf.truma.bak
        log_info "Backup of resolv.conf saved"
    fi

    # Disable systemd-resolved if active
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        systemctl stop systemd-resolved
        systemctl disable systemd-resolved
        rm -f /etc/resolv.conf
        log_info "systemd-resolved disabled"
    fi

    # Write DNS configuration (Iranian first, international fallback)
    cat > /etc/resolv.conf << EOF
# Truma Tunnel Manager - DNS Configuration
# Generated: $(date)

# --- Iranian Anti-Censorship DNS ---
nameserver 178.22.122.100
nameserver 185.51.200.2
nameserver 10.202.10.202
nameserver 10.202.10.102
nameserver 185.55.226.26
nameserver 85.15.1.14
nameserver 194.104.158.48

# --- International Fallback DNS ---
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 9.9.9.9

options timeout:2 attempts:3 rotate
EOF

    # Lock resolv.conf to prevent overwrite
    chattr +i /etc/resolv.conf 2>/dev/null || true
    log_info "DNS configured and locked"
}

# ────────────────────────────────────────────────────────────────
# Select Best Mirror (Speed Test)
# ────────────────────────────────────────────────────────────────
select_best_mirror() {
    log_step "Testing and selecting best Ubuntu mirror"
    local best_mirror=""
    local best_time=9999

    for mirror in "${MIRROR_LIST[@]}"; do
        local host
        host=$(echo "$mirror" | awk -F/ '{print $3}')
        local start_ms end_ms elapsed
        start_ms=$(date +%s%3N)
        if curl -sf --max-time 3 --head "$mirror" > /dev/null 2>&1; then
            end_ms=$(date +%s%3N)
            elapsed=$((end_ms - start_ms))
            log_debug "Mirror $host -> ${elapsed}ms"
            if (( elapsed < best_time )); then
                best_time=$elapsed
                best_mirror=$mirror
            fi
        else
            log_debug "Mirror $host -> unreachable"
        fi
    done

    if [[ -z "$best_mirror" ]]; then
        log_warn "No mirror reachable, using official fallback"
        best_mirror="http://archive.ubuntu.com/ubuntu/"
    fi

    log_info "Best mirror selected: ${BOLD}$best_mirror${RESET} (${best_time}ms)"
    echo "$best_mirror"
}

# ────────────────────────────────────────────────────────────────
# Configure Ubuntu Mirror
# ────────────────────────────────────────────────────────────────
configure_mirror() {
    log_step "Configuring Ubuntu package mirror"
    local codename
    codename=$(lsb_release -cs 2>/dev/null || echo "focal")
    local best_mirror
    best_mirror=$(select_best_mirror)

    # Backup sources.list
    cp /etc/apt/sources.list /etc/apt/sources.list.truma.bak 2>/dev/null || true
    log_info "Backup of sources.list saved"

    cat > /etc/apt/sources.list << EOF
# Truma Tunnel Manager - Mirror Configuration
# Generated: $(date)
# Selected Mirror: $best_mirror

deb $best_mirror $codename main restricted universe multiverse
deb $best_mirror $codename-updates main restricted universe multiverse
deb $best_mirror $codename-backports main restricted universe multiverse
deb $best_mirror $codename-security main restricted universe multiverse
EOF

    log_info "Mirror configured: $best_mirror"
}

# ────────────────────────────────────────────────────────────────
# CRLF Fix - Single File (4 layers)
# ────────────────────────────────────────────────────────────────
fix_crlf() {
    local file="$1"
    if [[ ! -f "$file" ]]; then return 0; fi

    # Layer 1: sed
    sed -i 's/\r$//' "$file" 2>/dev/null || true

    # Layer 2: tr
    local tmp
    tmp=$(mktemp)
    tr -d '\r' < "$file" > "$tmp" && mv "$tmp" "$file" 2>/dev/null || true

    # Layer 3: dos2unix if available
    if command -v dos2unix &>/dev/null; then
        dos2unix "$file" 2>/dev/null || true
    fi

    # Layer 4: Verify result
    if grep -qP '\r' "$file" 2>/dev/null; then
        log_warn "CRLF still detected in: $file"
        return 1
    fi
    return 0
}

# ────────────────────────────────────────────────────────────────
# CRLF Fix - All Files in Install Directory
# ────────────────────────────────────────────────────────────────
fix_all_crlf() {
    log_step "Scanning and cleaning CRLF characters"
    local count=0

    while IFS= read -r -d '' file; do
        if grep -qP '\r' "$file" 2>/dev/null; then
            fix_crlf "$file"
            log_info "CRLF cleaned: $file"
            (( count++ )) || true
        fi
    done < <(find "$INSTALL_DIR" -type f \
        \( -name "*.sh" -o -name "*.py" -o -name "*.conf" -o -name "*.json" \) \
        -print0 2>/dev/null)

    if (( count == 0 )); then
        log_info "No files with CRLF found"
    else
        log_success "Total $count file(s) cleaned"
    fi
}

# ────────────────────────────────────────────────────────────────
# Install CRLF Guard Service (systemd)
# Runs every 6 hours to auto-fix CRLF
# ────────────────────────────────────────────────────────────────
install_crlf_guard() {
    log_step "Installing CRLF Guard systemd service"

    cat > /etc/systemd/system/truma-crlf-guard.service << EOF
[Unit]
Description=Truma CRLF Guard Service
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'find ${INSTALL_DIR} -type f \( -name "*.sh" -o -name "*.py" -o -name "*.conf" \) -exec sed -i "s/\r\$//" {} \;'
StandardOutput=journal
StandardError=journal
EOF

    cat > /etc/systemd/system/truma-crlf-guard.timer << EOF
[Unit]
Description=Truma CRLF Guard Timer - runs every 6 hours
Requires=truma-crlf-guard.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h
Unit=truma-crlf-guard.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now truma-crlf-guard.timer
    log_info "CRLF Guard service installed and enabled (every 6 hours)"
}

# ────────────────────────────────────────────────────────────────
# Install Git CRLF Protection (hook + .gitattributes)
# ────────────────────────────────────────────────────────────────
install_git_crlf_protection() {
    log_step "Installing Git CRLF protection"

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        local hook="$INSTALL_DIR/.git/hooks/pre-commit"
        cat > "$hook" << 'HOOK'
#!/bin/bash
# Truma Git Hook - Block CRLF commits
files=$(git diff --cached --name-only --diff-filter=ACM)
for file in $files; do
    if grep -qP '\r' "$file" 2>/dev/null; then
        echo "[ERROR] CRLF detected in: $file"
        echo "[ERROR] Run: sed -i 's/\r$//' $file"
        exit 1
    fi
done
exit 0
HOOK
        chmod +x "$hook"
        log_info "Git pre-commit hook installed"

        cat > "$INSTALL_DIR/.gitattributes" << 'GITATTR'
# Truma - Force LF line endings
* text=auto eol=lf
*.sh text eol=lf
*.py text eol=lf
*.conf text eol=lf
*.json text eol=lf
GITATTR
        log_info ".gitattributes configured (force LF)"
    else
        log_warn "No Git repository found, skipping Git hook installation"
    fi
}

# ────────────────────────────────────────────────────────────────
# Disable IPv6
# ────────────────────────────────────────────────────────────────
disable_ipv6() {
    log_step "Disabling IPv6"

    cat >> /etc/sysctl.conf << EOF

# Truma Tunnel Manager - Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

    sysctl -p > /dev/null 2>&1
    log_info "IPv6 disabled"
}

# ────────────────────────────────────────────────────────────────
# Optimize Kernel Parameters
# ────────────────────────────────────────────────────────────────
optimize_kernel() {
    log_step "Applying kernel optimizations"

    cat > /etc/sysctl.d/99-truma-optimize.conf << EOF
# Truma Tunnel Manager - Kernel Optimization
# Generated: $(date)

# --- Network Buffers ---
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# --- TCP Optimization ---
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.ip_forward = 1

# --- Security ---
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1

# --- Memory ---
vm.swappiness = 10
fs.file-max = 1000000
EOF

    sysctl --system > /dev/null 2>&1
    log_info "Kernel optimizations applied"
}

# ────────────────────────────────────────────────────────────────
# Install Dependencies
# ────────────────────────────────────────────────────────────────
install_dependencies() {
    log_step "Installing required packages"

    apt-get update -qq 2>&1 | tail -1
    apt-get install -y -qq \
        curl wget git unzip dos2unix \
        net-tools iproute2 iptables \
        python3 python3-pip \
        jq bc lsof \
        2>&1 | tail -5

    log_info "All dependencies installed successfully"
}

# ────────────────────────────────────────────────────────────────
# Download Truma Files from GitHub
# ────────────────────────────────────────────────────────────────
download_truma() {
    log_step "Downloading Truma Tunnel Manager files"

    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$BACKUP_DIR"

    local files=(
        "truma.sh"
        "truma-menu.sh"
        "truma-core.py"
        "truma.conf"
    )

    for file in "${files[@]}"; do
        local url="$GITHUB_RAW/$file"
        local dest="$INSTALL_DIR/$file"
        log_info "Downloading: $file"

        if curl -fsSL "$url" | tr -d '\r' > "$dest" 2>/dev/null; then
            chmod +x "$dest" 2>/dev/null || true
            fix_crlf "$dest"
            log_info "Download successful: $file"
        else
            log_warn "Download failed: $file (continuing...)"
        fi
    done
}

# ────────────────────────────────────────────────────────────────
# Create Global truma Command
# ────────────────────────────────────────────────────────────────
create_command() {
    log_step "Creating global truma command"

    cat > /usr/local/bin/truma << 'TRUMA_CMD'
#!/bin/bash
# Truma Tunnel Manager - Global Command
exec /opt/truma/truma-menu.sh "$@"
TRUMA_CMD

    chmod +x /usr/local/bin/truma
    log_info "Command 'truma' created at /usr/local/bin/truma"
}

# ────────────────────────────────────────────────────────────────
# Verify Installation
# ────────────────────────────────────────────────────────────────
verify_installation() {
    log_step "Verifying installation integrity"
    local errors=0

    # Check directories
    for dir in "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"; do
        if [[ -d "$dir" ]]; then
            log_info "Directory OK: $dir"
        else
            log_warn "Directory missing: $dir"
            (( errors++ )) || true
        fi
    done

    # Check CRLF in all installed files
    local crlf_found=0
    while IFS= read -r -d '' file; do
        if grep -qP '\r' "$file" 2>/dev/null; then
            log_warn "CRLF still found in: $file - auto-fixing..."
            fix_crlf "$file"
            (( crlf_found++ )) || true
        fi
    done < <(find "$INSTALL_DIR" -type f -print0 2>/dev/null)

    if (( crlf_found > 0 )); then
        log_warn "$crlf_found file(s) had CRLF and were re-cleaned"
    else
        log_info "No CRLF issues detected"
    fi

    # Check global command
    if command -v truma &>/dev/null; then
        log_info "Command 'truma' is available"
    else
        log_warn "Command 'truma' not found in PATH"
        (( errors++ )) || true
    fi

    if (( errors == 0 )); then
        log_success "Installation verification passed"
    else
        log_warn "Installation completed with $errors warning(s)"
    fi
}

# ────────────────────────────────────────────────────────────────
# Show Final Report
# ────────────────────────────────────────────────────────────────
show_final_report() {
    local server_ip
    server_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "unknown")

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║         Installation Completed Successfully!       ║${RESET}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "  ${CYAN}Server IP:${RESET}       $server_ip"
    echo -e "  ${CYAN}Version:${RESET}         v${VERSION}"
    echo -e "  ${CYAN}Install Path:${RESET}    $INSTALL_DIR"
    echo -e "  ${CYAN}Config Path:${RESET}     $CONFIG_DIR"
    echo -e "  ${CYAN}Log Path:${RESET}        $LOG_DIR"
    echo ""
    echo -e "  ${YELLOW}Available Commands:${RESET}"
    echo -e "  ${WHITE}truma${RESET}            -> Open main menu"
    echo -e "  ${WHITE}truma status${RESET}     -> Show service status"
    echo -e "  ${WHITE}truma restart${RESET}    -> Restart service"
    echo -e "  ${WHITE}truma update${RESET}     -> Update to latest version"
    echo ""
    echo -e "  ${YELLOW}Active Protections:${RESET}"
    echo -e "  ${WHITE}CRLF Guard${RESET}       -> Runs every 6 hours via systemd"
    echo -e "  ${WHITE}DNS Shield${RESET}       -> Iranian anti-censorship DNS active"
    echo -e "  ${WHITE}IPv6${RESET}             -> Disabled"
    echo -e "  ${WHITE}BBR${RESET}              -> TCP congestion control enabled"
    echo ""
    echo -e "${MAGENTA}  ══════════════════════════════════════════════════${RESET}"
    echo -e "  ${BOLD}GitHub:${RESET} $GITHUB_REPO"
    echo -e "${MAGENTA}  ══════════════════════════════════════════════════${RESET}"
    echo ""
}

# ────────────────────────────────────────────────────────────────
# Main Entry Point
# ────────────────────────────────────────────────────────────────
main() {
    show_banner
    check_root
    check_os
    configure_dns
    configure_mirror
    disable_ipv6
    optimize_kernel
    install_dependencies
    download_truma
    fix_all_crlf
    install_crlf_guard
    install_git_crlf_protection
    create_command
    verify_installation
    show_final_report
}

main "$@"
