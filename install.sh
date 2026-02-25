#!/usr/bin/env bash
# install.sh – Truma Tunnel Manager installer (auto-run after installation)

set -e

VERSION="v1.9.0"
BASE_URL="https://github.com/efikhan/Truma-Tunnel/releases/download/$VERSION"

echo "📥 Downloading Truma Tunnel Manager v1.9.0 ..."
curl -L -o truma.sh "$BASE_URL/truma.sh"
curl -L -o gre-manager.sh "$BASE_URL/gre-manager.sh"
curl -L -o paqet.sh "$BASE_URL/paqet.sh"

echo "🔧 Setting execute permissions..."
chmod +x truma.sh gre-manager.sh paqet.sh

# Fix Windows line endings if present (optional)
if command -v dos2unix >/dev/null 2>&1; then
    dos2unix truma.sh gre-manager.sh paqet.sh 2>/dev/null
else
    sed -i 's/\r$//' truma.sh gre-manager.sh paqet.sh 2>/dev/null
fi

echo "✅ Installation complete!"
echo "🚀 Starting Truma Tunnel Manager..."
exec ./truma.sh
