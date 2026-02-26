#!/bin/bash
# نصب‌کننده هوشمند Truma (فقط یک بار دانلود می‌کند)

INSTALL_DIR="/opt/truma"
REPO_URL="https://github.com/efikhan/Truma-Tunnel.git"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}لطفاً با روت اجرا کنید: sudo $0${NC}"
    exit 1
fi

if [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/truma.sh" ]]; then
    echo -e "${YELLOW}نصب قبلی در $INSTALL_DIR پیدا شد.${NC}"
    read -rp "آیا می‌خواهید دوباره نصب کنید (پاک کردن و دانلود مجدد)؟ (y/n) " -n 1
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}در حال دریافت فایل‌ها از GitHub...${NC}"
        rm -rf "$INSTALL_DIR"
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    else
        echo -e "${GREEN}استفاده از نصب قبلی.${NC}"
    fi
else
    echo -e "${YELLOW}در حال دریافت فایل‌ها از GitHub...${NC}"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"
chmod +x *.sh
sed -i 's/\r$//' *.sh

echo -e "${GREEN}در حال اجرای Truma...${NC}"
./truma.sh
