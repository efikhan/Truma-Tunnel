#!/bin/bash
# نصب‌کننده خیلی ساده Truma

cd /opt
rm -rf truma 2>/dev/null
mkdir truma
cd truma

wget https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/truma.sh
wget https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/gre-manager.sh
wget https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/paqet.sh
wget https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/mesh-manager.sh
wget https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/haproxy-manager.sh

chmod +x *.sh
sed -i 's/\r$//' *.sh

echo "نصب شد. در حال اجرای Truma..."
./truma.sh
