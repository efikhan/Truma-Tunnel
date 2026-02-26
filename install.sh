#!/bin/bash
# Truma Tunnel Manager Installer

set -e

REPO="https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main"
INSTALL_DIR="/opt/truma"
BIN="/usr/local/bin/truma"

# رنگ‌ها برای خروجی
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# بررسی دسترسی روت
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This installer must be run as root.${NC}"
    echo "Please run: sudo bash install.sh"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Truma Tunnel Manager v2 Installer   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# نصب curl در صورت نبود
if ! command -v curl &>/dev/null; then
    echo -e "${YELLOW}curl not found. Installing...${NC}"
    if command -v apt-get &>/dev/null; then
        apt-get update && apt-get install -y curl
    elif command -v yum &>/dev/null; then
        yum install -y curl
    elif command -v dnf &>/dev/null; then
        dnf install -y curl
    else
        echo -e "${RED}Could not install curl automatically. Please install curl manually.${NC}"
        exit 1
    fi
fi

# ایجاد پوشه نصب
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# لیست فایل‌ها
FILES=(
    "truma.sh"
    "gre-manager.sh"
    "paqet.sh"
    "mesh-manager.sh"
    "haproxy-manager.sh"
)

echo -e "${YELLOW}Downloading files from GitHub...${NC}"

for file in "${FILES[@]}"; do
    echo -n "  $file ... "
    if curl -sSf -O "$REPO/$file"; then
        chmod +x "$file"
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo "Error downloading $file. Check your internet connection."
        exit 1
    fi
done

# ایجاد لینک نمادین
echo -n "Creating symlink $BIN ... "
ln -sf "$INSTALL_DIR/truma.sh" "$BIN"
echo -e "${GREEN}OK${NC}"

echo
echo -e "${GREEN}Installation completed successfully!${NC}"
echo
echo -e "You can now start Truma by running: ${YELLOW}truma${NC}"
echo -e "Or directly with: ${YELLOW}sudo $INSTALL_DIR/truma.sh${NC}"
echo

# اجرای خودکار (اختیاری)
read -rp "Do you want to start Truma now? (y/n) " -n 1
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    "$INSTALL_DIR/truma.sh"
fi

exit 0