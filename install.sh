#!/usr/bin/env bash
# install.sh – Truma Tunnel Manager installer

set -e

VERSION="v1.9.0"
BASE_URL="https://github.com/efikhan/Truma-Tunnel/releases/download/$VERSION"

echo "Downloading Truma Tunnel Manager v1.9.0 ..."
curl -L -o truma.sh "$BASE_URL/truma.sh"
curl -L -o gre-manager.sh "$BASE_URL/gre-manager.sh"
curl -L -o paqet.sh "$BASE_URL/paqet.sh"

chmod +x truma.sh gre-manager.sh paqet.sh
echo "Installation complete. Run ./truma.sh to start."
