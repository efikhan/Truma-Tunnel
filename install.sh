#!/bin/bash
# Truma Tunnel Manager – نصب‌کننده سریع

set -e

REPO="https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main"
DEST="/opt/truma"
BIN="/usr/local/bin/truma"

# رنگ‌ها
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# بررسی روت
[[ $EUID -ne 0 ]] && { echo "لطفاً با روت اجرا کنید."; exit 1; }

# نصب curl در صورت نیاز
command -v curl >/dev/null || { apt-get update && apt-get install -y curl; }

# ایجاد پوشه و ورود
mkdir -p "$DEST" && cd "$DEST"

# دانلود فایل‌ها
echo -e "${YELLOW}در حال دریافت فایل‌ها...${NC}"
for f in truma.sh gre-manager.sh paqet.sh mesh-manager.sh haproxy-manager.sh; do
    echo -n "$f ... "
    curl -sSf -O "$REPO/$f"
    chmod +x "$f"
    # حذف CRLF و اصلاح 'cho' به 'echo'
    sed -i 's/\r$//' "$f"
    sed -i 's/cho /echo /g' "$f"
    echo "✓"
done

# لینک نمادین
ln -sf "$DEST/truma.sh" "$BIN"

echo -e "${GREEN}نصب کامل شد! اکنون با دستور 'truma' اجرا کنید.${NC}"

# اجرای اختیاری
read -rp "آیا می‌خواهید هم‌اکنون Truma را اجرا کنید؟ (y/n) " -n 1
[[ $REPLY =~ ^[Yy]$ ]] && "$DEST/truma.sh"
