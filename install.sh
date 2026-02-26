#!/bin/bash
# Truma Tunnel Manager Installer – نسخه پایدار

set -e

REPO="https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main"
INSTALL_DIR="/opt/truma"
BIN="/usr/local/bin/truma"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This installer must be run as root.${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Truma Tunnel Manager v2 Installer   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo

# نصب خودکار curl در صورت نیاز
if ! command -v curl &>/dev/null; then
    echo -e "${YELLOW}curl not found. Installing...${NC}"
    if command -v apt-get &>/dev/null; then
        apt-get update && apt-get install -y curl
    elif command -v yum &>/dev/null; then
        yum install -y curl
    elif command -v dnf &>/dev/null; then
        dnf install -y curl
    else
        echo -e "${RED}Could not install curl. Please install it manually.${NC}"
        exit 1
    fi
fi

# ایجاد پوشه نصب
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# لیست فایل‌های اصلی
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
        # حذف کاراکترهای CRLF (اگر وجود داشته باشند) با استفاده از tr
        tr -d '\r' < "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        exit 1
    fi
done

# ایجاد لینک نمادین
ln -sf "$INSTALL_DIR/truma.sh" "$BIN"

echo
echo -e "${GREEN}Installation completed successfully!${NC}"
echo -e "You can now run ${YELLOW}truma${NC} from anywhere."
echo

# بررسی سریع سینتکس (اختیاری)
echo -e "${YELLOW}Checking syntax of truma.sh...${NC}"
if bash -n "$INSTALL_DIR/truma.sh" 2>/dev/null; then
    echo -e "${GREEN}Syntax OK.${NC}"
else
    echo -e "${RED}Warning: truma.sh has syntax errors. You may need to fix it manually.${NC}"
fi

# اجرا
read -rp "Do you want to start Truma now? (y/n) " -n 1
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    "$INSTALL_DIR/truma.sh"
fi

exit 0
