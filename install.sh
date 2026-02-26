#!/usr/bin/env bash
# =============================================================================
# Truma Tunnel Manager – Professional Installer
# =============================================================================
# This installer clones the Truma repository, sets permissions, fixes line
# endings, and launches the main menu. It features a polished interface
# matching Truma's own style.
# =============================================================================

set -euo pipefail

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
print_banner() {
    echo -e "${MAGENTA}"
    cat << "EOF"
████████╗██████╗ ██╗   ██╗███╗   ███╗ █████╗
╚══██╔══╝██╔══██╗██║   ██║████╗ ████║██╔══██╗
   ██║   ██████╔╝██║   ██║██╔████╔██║███████║
   ██║   ██╔══██╗██║   ██║██║╚██╔╝██║██╔══██║
   ██║   ██║  ██║╚██████╔╝██║ ╚═╝ ██║██║  ██║
   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝
          Truma Tunnel Manager v2
EOF
    echo -e "${NC}"
}

print_step()   { echo -e "${CYAN}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error()   { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_info()    { echo -e "${WHITE}[i]${NC} $1"; }

# -----------------------------------------------------------------------------
# Preliminary checks
# -----------------------------------------------------------------------------
clear
print_banner
echo

if [[ $EUID -ne 0 ]]; then
    print_error "This installer must be run as root."
    echo -e "Please use: ${YELLOW}sudo bash $0${NC}"
    exit 1
fi

# -----------------------------------------------------------------------------
# Check for required tools
# -----------------------------------------------------------------------------
print_step "Checking required tools..."

MISSING=()
if ! command -v git &>/dev/null; then
    MISSING+=("git")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    print_warning "Missing tools: ${MISSING[*]}"
    print_info "Attempting to install git automatically..."
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y git -qq
    elif command -v yum &>/dev/null; then
        yum install -y git -q
    elif command -v dnf &>/dev/null; then
        dnf install -y git -q
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm git
    else
        print_error "No supported package manager found."
        echo -e "Please install git manually and re-run this installer."
        exit 1
    fi
    print_success "git installed successfully."
else
    print_success "All required tools are present."
fi

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
INSTALL_DIR="/opt/truma"
REPO_URL="https://github.com/efikhan/Truma-Tunnel.git"

# -----------------------------------------------------------------------------
# Handle existing installation
# -----------------------------------------------------------------------------
if [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/truma.sh" ]]; then
    print_warning "Existing Truma installation found at $INSTALL_DIR"
    echo -ne "${YELLOW}Do you want to reinstall (overwrite)? (y/n) ${NC}"
    read -r -n 1
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_step "Removing old installation..."
        rm -rf "$INSTALL_DIR"
        print_success "Old installation removed."
    else
        print_info "Using existing installation."
        cd "$INSTALL_DIR"
        echo
        print_step "Launching Truma..."
        ./truma.sh
        exit 0
    fi
fi

# -----------------------------------------------------------------------------
# Clone repository
# -----------------------------------------------------------------------------
print_step "Cloning Truma repository from GitHub..."
if git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"; then
    print_success "Repository cloned successfully."
else
    print_error "Failed to clone repository. Check your internet connection."
    exit 1
fi

# -----------------------------------------------------------------------------
# Set permissions and fix line endings
# -----------------------------------------------------------------------------
cd "$INSTALL_DIR"
print_step "Setting execute permissions on scripts..."
chmod +x *.sh
print_success "Permissions set."

print_step "Removing Windows line endings (CRLF)..."
sed -i 's/\r$//' *.sh
print_success "Line endings fixed."

# -----------------------------------------------------------------------------
# Final launch
# -----------------------------------------------------------------------------
echo
print_success "Truma Tunnel Manager has been installed successfully!"
print_info "Installation directory: $INSTALL_DIR"
echo
print_step "Launching Truma..."
./truma.sh

exit 0
