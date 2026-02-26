
---



```bash
#!/usr/bin/env bash
# =============================================================================
# Truma Tunnel Manager – Automatic Installer
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

echo -e "${YELLOW}Downloading files...${NC}"
for file in "${FILES[@]}"; do
    echo -n "  $file ... "
    if curl -sSf -O "$BASE_URL/$file"; then
        chmod +x "$file"
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        exit 1
    fi
done

# Create symbolic link
echo -n "Creating symlink /usr/local/bin/truma ... "
ln -sf "$INSTALL_DIR/truma.sh" "$BIN_DIR/truma"
echo -e "${GREEN}OK${NC}"

echo -e "${GREEN}Installation completed successfully!${NC}"
echo
echo "You can now start Truma by running:  truma"
echo "Or directly with:  sudo $INSTALL_DIR/truma.sh"
echo

# Optionally launch
read -rp "Do you want to start Truma now? (y/n) " -n 1
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    "$INSTALL_DIR/truma.sh"
fi

exit 0