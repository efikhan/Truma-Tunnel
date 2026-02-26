#!/bin/bash
# نصب‌کننده سریع Truma

set -e

REPO="https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main"
INSTALL_DIR="/opt/truma"

# رنگ‌ها
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# بررسی دسترسی روت
if [[ $EUID -ne 0 ]]; then
    echo "لطفاً با روت اجرا کنید: sudo bash $0"
    exit 1
fi

# نصب curl در صورت نیاز
if ! command -v curl &>/dev/null; then
    apt-get update && apt-get install -y curl
fi

# ایجاد پوشه نصب
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# دانلود فایل‌ها
echo -e "${YELLOW}در حال دانلود فایل‌ها...${NC}"
for file in truma.sh gre-manager.sh paqet.sh mesh-manager.sh haproxy-manager.sh; do
    echo -n "$file ... "
    curl -sSf -O "$REPO/$file"
    chmod +x "$file"
    # حذف CRLF و اصلاح 'cho' به 'echo'
    tr -d '\r' < "$file" | sed 's/cho /echo /g' > "$file.tmp"
    mv "$file.tmp" "$file"
    echo "✅"
done

# لینک نمادین
ln -sf "$INSTALL_DIR/truma.sh" /usr/local/bin/truma

echo -e "${GREEN}نصب کامل شد!${NC}"
echo "حالا می‌توانید با دستور truma اجرا کنید."

# اجرای خودکار (اختیاری)
read -rp "آیا می‌خواهید Truma را هم‌اکنون اجرا کنید؟ (y/n) " -n 1
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    "$INSTALL_DIR/truma.sh"
fi
