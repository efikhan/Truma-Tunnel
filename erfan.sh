```bash
#!/bin/bash
# Truma Tunnel Manager – Simple Installer with Auto‑Start

set -e

REPO="https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main"
DEST="/opt/truma"
BIN="/usr/local/bin/truma"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This installer must be run as root.${NC}"
    exit 1
fi

# Install curl if missing
if ! command -v curl &>/dev/null; then
    echo -e "${YELLOW}curl not found. Installing...${NC}"
    if command -v apt-get &>/dev/null; then
        apt-get update && apt-get install -y curl
    elif command -v yum &>/dev/null; then
        yum install -y curl
    elif command -v dnf &>/dev/null; then
        dnf install -y curl
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm curl
    else
        echo -e "${RED}No supported package manager. Please install curl manually.${NC}"
        exit 1
    fi
fi

# Create destination directory
mkdir -p "$DEST"
cd "$DEST"

# Download files
echo -e "${YELLOW}Downloading files from GitHub...${NC}"
FILES=("truma.sh" "gre-manager.sh" "paqet.sh" "mesh-manager.sh" "haproxy-manager.sh")
for f in "${FILES[@]}"; do
    echo -n "  $f ... "
    if curl -fsSL -o "$f" "$REPO/$f"; then
        chmod +x "$f"
        echo "✅"
    else
        echo -e "${RED}❌ Failed to download $f${NC}"
        exit 1
    fi
done

# Fix CRLF line endings
echo -e "${YELLOW}Fixing CRLF line endings...${NC}"
sed -i 's/\r$//' *.sh
echo "✅ CRLF cleaned."

# Create symlink
ln -sf "$DEST/truma.sh" "$BIN"

echo -e "${GREEN}Installation complete! Starting Truma now...${NC}"
echo "--------------------------------------------------"

# Auto-start Truma
./truma.sh

exit 0
```
