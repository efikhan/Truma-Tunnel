#!/bin/bash
# Truma Tunnel Manager – Minimal Installer

set -e

REPO="https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main"
DEST="/opt/truma"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# روت
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This installer must be run as root.${NC}"
    exit 1
fi

# wget
if ! command -v wget &>/dev/null; then
    echo -e "${YELLOW}wget not found. Installing...${NC}"
    apt-get update && apt-get install -y wget
fi

# پوشه
mkdir -p "$DEST"
cd "$DEST"

# دانلود
echo -e "${YELLOW}Downloading files...${NC}"
FILES=("truma.sh" "gre-manager.sh" "paqet.sh" "mesh-manager.sh" "haproxy-manager.sh")
for f in "${FILES[@]}"; do
    echo -n "  $f ... "
    wget -q -O "$f" "$REPO/$f"
    chmod +x "$f"
    echo "✅"
done

# رفع CRLF
sed -i 's/\r$//' *.sh

echo -e "${GREEN}Done. Starting Truma...${NC}"
./truma.sh

exit 0
