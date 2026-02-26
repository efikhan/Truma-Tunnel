#!/usr/bin/env bash
# =============================================================================
# Truma Tunnel Manager – Enterprise Installer
# =============================================================================
# Version: 2.0.0
# Author:  Truma Team
# Description: Production-grade installer with checksum verification,
#              rollback, systemd integration, and full dependency management.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
VERSION="2.0.0"
REPO_BASE="https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main"
INSTALL_DIR="/opt/truma"
SYMLINK="/usr/local/bin/truma"
LOG_FILE="/var/log/truma-install.log"
CHECKSUM_FILE="checksums.txt"

# List of required scripts
SCRIPTS=(
    "truma.sh"
    "gre-manager.sh"
    "paqet.sh"
    "mesh-manager.sh"
    "haproxy-manager.sh"
)

# System dependencies (will be installed if missing)
DEPS=(
    "curl"
    "dos2unix"
    "iproute2"
    "haproxy"
    "openssl"
    "jq"
)

# -----------------------------------------------------------------------------
# Colors (aligned with Truma)
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------
log() {
    echo -e "${CYAN}[installer]${NC} $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1" >&2
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# -----------------------------------------------------------------------------
# Trap handlers
# -----------------------------------------------------------------------------
cleanup() {
    if [[ -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
        log "Cleaned up temporary directory."
    fi
}

interrupt() {
    echo -e "\n${RED}Installation interrupted by user.${NC}"
    exit 1
}

trap cleanup EXIT
trap interrupt INT
trap 'error "Installation failed at line $LINENO. Check log: $LOG_FILE"' ERR

# -----------------------------------------------------------------------------
# Preliminary checks
# -----------------------------------------------------------------------------
clear
# Display banner with proper color expansion
echo -e "${MAGENTA}"
cat << "EOF"
████████╗██████╗ ██╗   ██╗███╗   ███╗ █████╗
╚══██╔══╝██╔══██╗██║   ██║████╗ ████║██╔══██╗
   ██║   ██████╔╝██║   ██║██╔████╔██║███████║
   ██║   ██╔══██╗██║   ██║██║╚██╔╝██║██╔══██║
   ██║   ██║  ██║╚██████╔╝██║ ╚═╝ ██║██║  ██║
   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝
EOF
echo -e "${NC}  Truma Tunnel Manager v${VERSION} – Enterprise Installer"
echo

if [[ $EUID -ne 0 ]]; then
    error "This installer must be run as root. Use 'sudo bash install.sh'."
fi

# Create log directory if needed
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
log "Starting Truma installation (version $VERSION). Log: $LOG_FILE"

# Create temporary directory
TMP_DIR=$(mktemp -d -t truma-install-XXXXXXXXXX)
log "Using temporary directory: $TMP_DIR"

# -----------------------------------------------------------------------------
# Parse command-line options
# -----------------------------------------------------------------------------
SKIP_CHECKSUM=0
INSTALL_DEPS=1
ENABLE_SERVICE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-checksum) SKIP_CHECKSUM=1; shift ;;
        --no-deps) INSTALL_DEPS=0; shift ;;
        --enable-service) ENABLE_SERVICE=1; shift ;;
        --help)
            echo "Usage: $0 [--skip-checksum] [--no-deps] [--enable-service]"
            exit 0
            ;;
        *) error "Unknown option: $1" ;;
    esac
done

# -----------------------------------------------------------------------------
# Install system dependencies (if requested)
# -----------------------------------------------------------------------------
if [[ $INSTALL_DEPS -eq 1 ]]; then
    log "Checking system dependencies..."
    MISSING=()
    for pkg in "${DEPS[@]}"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            # Special case: iproute2 provides 'ip' command
            if [[ "$pkg" == "iproute2" ]] && command -v ip >/dev/null 2>&1; then
                continue
            fi
            MISSING+=("$pkg")
        fi
    done

    if [[ ${#MISSING[@]} -gt 0 ]]; then
        warn "Missing packages: ${MISSING[*]}. Attempting to install..."
        if command -v apt-get >/dev/null 2>&1; then
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq || error "apt update failed"
            apt-get install -y -qq "${MISSING[@]}" || error "Failed to install packages via apt."
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q "${MISSING[@]}" || error "Failed to install packages via yum."
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y -q "${MISSING[@]}" || error "Failed to install packages via dnf."
        else
            error "No supported package manager found. Please install the following manually: ${MISSING[*]}"
        fi
        success "Dependencies installed."
    else
        success "All required packages are already installed."
    fi
else
    log "Skipping dependency installation (--no-deps)."
fi

# -----------------------------------------------------------------------------
# Backup existing installation
# -----------------------------------------------------------------------------
log "Preparing installation directory: $INSTALL_DIR"
if [[ -d "$INSTALL_DIR" ]]; then
    warn "Directory $INSTALL_DIR already exists. Moving to backup."
    BACKUP_DIR="${INSTALL_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    mv "$INSTALL_DIR" "$BACKUP_DIR" || error "Failed to backup existing installation."
    success "Backed up to $BACKUP_DIR"
fi
mkdir -p "$INSTALL_DIR" || error "Cannot create $INSTALL_DIR"
cd "$INSTALL_DIR"

# -----------------------------------------------------------------------------
# Download scripts and checksums
# -----------------------------------------------------------------------------
log "Downloading Truma scripts from GitHub..."

# Download checksums file first (unless skipped)
if [[ $SKIP_CHECKSUM -eq 0 ]]; then
    if curl -fsSL --connect-timeout 10 -o "$TMP_DIR/$CHECKSUM_FILE" "$REPO_BASE/$CHECKSUM_FILE"; then
        dos2unix -q "$TMP_DIR/$CHECKSUM_FILE" 2>/dev/null || sed -i 's/\r$//' "$TMP_DIR/$CHECKSUM_FILE"
        log "Checksums file downloaded."
    else
        warn "Checksums file not found or download failed. Skipping verification."
        SKIP_CHECKSUM=1
    fi
fi

for script in "${SCRIPTS[@]}"; do
    echo -n "  $script ... "
    if curl -fsSL --connect-timeout 10 -o "$script" "$REPO_BASE/$script"; then
        # Fix line endings and common typos
        dos2unix -q "$script" 2>/dev/null || sed -i 's/\r$//' "$script"
        sed -i 's/\bcho\b/echo/g' "$script"
        chmod +x "$script"
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        error "Failed to download $script from $REPO_BASE/$script"
    fi
done
success "All scripts downloaded."

# -----------------------------------------------------------------------------
# Checksum verification (if enabled)
# -----------------------------------------------------------------------------
if [[ $SKIP_CHECKSUM -eq 0 ]]; then
    log "Verifying checksums..."
    cd "$INSTALL_DIR"
    if ! sha256sum -c "$TMP_DIR/$CHECKSUM_FILE" --quiet 2>/dev/null; then
        error "Checksum verification failed. Files may be corrupted. Use --skip-checksum to bypass."
    fi
    success "All checksums match."
fi

# -----------------------------------------------------------------------------
# Syntax check
# -----------------------------------------------------------------------------
log "Performing syntax validation..."
for script in "${SCRIPTS[@]}"; do
    if bash -n "$script" 2>/dev/null; then
        echo -e "  $script ... ${GREEN}OK${NC}"
    else
        echo -e "  $script ... ${RED}FAILED${NC}"
        error "Syntax error in $script. Please check the file manually."
    fi
done
success "All scripts passed the syntax check."

# -----------------------------------------------------------------------------
# Create symlink
# -----------------------------------------------------------------------------
log "Creating symlink $SYMLINK"
ln -sf "$INSTALL_DIR/truma.sh" "$SYMLINK" || error "Failed to create symlink."
success "Symlink created."

# -----------------------------------------------------------------------------
# Optional: Create systemd service
# -----------------------------------------------------------------------------
if [[ $ENABLE_SERVICE -eq 1 ]]; then
    log "Setting up systemd service..."
    UNIT_FILE="/etc/systemd/system/truma.service"
    cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Truma Tunnel Manager
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SYMLINK
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable truma.service || warn "Failed to enable truma.service (non-fatal)"
    success "Systemd service created and enabled."
fi

# -----------------------------------------------------------------------------
# Final message
# -----------------------------------------------------------------------------
echo
success "Truma Tunnel Manager v${VERSION} has been successfully installed!"
echo
echo -e "  ${WHITE}Installation directory:${NC} $INSTALL_DIR"
echo -e "  ${WHITE}Symlink:${NC} $SYMLINK"
echo -e "  ${WHITE}Log file:${NC} $LOG_FILE"
if [[ $ENABLE_SERVICE -eq 1 ]]; then
    echo -e "  ${WHITE}Systemd service:${NC} truma.service"
fi
echo

# Interactive launch only if running in a terminal
if [[ -t 0 ]]; then
    read -rp "Do you want to start Truma now? (y/n) " -n 1
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "$INSTALL_DIR/truma.sh"
    else
        echo "You can start it later by typing 'truma'."
    fi
else
    log "Non-interactive mode detected. Skipping launch prompt."
fi

exit 0