#!/usr/bin/env bash
# =============================================================================
# Truma Tunnel Manager – Automatic Installer (Fixed Line Endings)
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This installer must be run as root.${NC}"
    echo "Please run: sudo bash install.sh"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Truma Tunnel Manager v2 Installer   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# Detect package manager and install required tools
install_required_tools() {
    local tools=("curl" "wget")
    local missing=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}Installing missing tools: ${missing[*]}${NC}"
    
    if command -v apt-get &>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq "${missing[@]}"
    elif command -v yum &>/dev/null; then
        yum install -y -q "${missing[@]}"
    elif command -v dnf &>/dev/null; then
        dnf install -y -q "${missing[@]}"
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm "${missing[@]}"
    else
        echo -e "${RED}No supported package manager found. Please install curl or wget manually.${NC}"
        exit 1
    fi
}

install_required_tools

# Define target directory
INSTALL_DIR="/opt/truma"
BIN_DIR="/usr/local/bin"

# Create installation directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || { echo -e "${RED}Failed to create $INSTALL_DIR${NC}"; exit 1; }

# List of files to download
FILES=(
    "truma.sh"
    "gre-manager.sh"
    "paqet.sh"
    "mesh-manager.sh"
    "haproxy-manager.sh"
)

BASE_URL="https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main"

echo -e "${BLUE}Downloading Truma files from GitHub...${NC}"

download_file() {
    local file="$1"
    local url="$BASE_URL/$file"
    
    echo -n "  $file ... "
    
    # Try curl first, then wget
    if command -v curl &>/dev/null; then
        if curl -sSf -o "$file" "$url" 2>/dev/null; then
            chmod +x "$file"
            echo -e "${GREEN}OK (curl)${NC}"
            return 0
        fi
    fi
    
    if command -v wget &>/dev/null; then
        if wget -q -O "$file" "$url" 2>/dev/null; then
            chmod +x "$file"
            echo -e "${GREEN}OK (wget)${NC}"
            return 0
        fi
    fi
    
    echo -e "${RED}FAILED${NC}"
    return 1
}

failed=0
for file in "${FILES[@]}"; do
    if ! download_file "$file"; then
        failed=1
    fi
done

if [[ $failed -ne 0 ]]; then
    echo -e "${RED}Error: Failed to download one or more files.${NC}"
    echo -e "${YELLOW}Please check your internet connection and the repository URL:${NC}"
    echo "  $BASE_URL"
    exit 1
fi

# Create symbolic link
echo -n "Creating symlink /usr/local/bin/truma ... "
if ln -sf "$INSTALL_DIR/truma.sh" "$BIN_DIR/truma"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

echo
echo -e "${GREEN}Installation completed successfully!${NC}"
echo
echo -e "${BLUE}You can now start Truma by running:${NC}  ${YELLOW}truma${NC}"
echo -e "${BLUE}Or directly with:${NC}  ${YELLOW}sudo $INSTALL_DIR/truma.sh${NC}"
echo

# Optionally launch
read -rp "Do you want to start Truma now? (y/n) " -n 1
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    "$INSTALL_DIR/truma.sh"
fi

exit 0