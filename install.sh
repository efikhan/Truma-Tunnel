#!/usr/bin/env bash
# quick-install.sh
# Simple quick installer for Truma Tunnel Manager (downloads required scripts)
# Usage: sudo ./quick-install.sh

set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main"
INSTALL_DIR="/opt/truma"
SYMLINK="/usr/local/bin/truma"
FILES=( "truma.sh" "gre-manager.sh" "paqet.sh" "mesh-manager.sh" "haproxy-manager.sh" )

# Colors
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

must_be_root(){
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This installer must be run as root (sudo).${NC}"
        exit 1
    fi
}

detect_pm_and_install(){
    local pkgs=("$@")
    # Only install if missing
    local to_install=()
    for p in "${pkgs[@]}"; do
        if ! command -v "$p" >/dev/null 2>&1; then
            to_install+=("$p")
        fi
    done
    if [[ ${#to_install[@]} -eq 0 ]]; then
        return 0
    fi

    echo -e "${YELLOW}Installing missing tools: ${to_install[*]}${NC}"
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y "${to_install[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "${to_install[@]}"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "${to_install[@]}"
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --noconfirm "${to_install[@]}"
    else
        echo -e "${RED}No supported package manager found. Install: ${to_install[*]} manually.${NC}"
        exit 1
    fi
}

download_file(){
    local url="$1" dest="$2"
    if curl -fsSL --connect-timeout 10 -o "$dest" "$url"; then
        return 0
    else
        return 1
    fi
}

fix_line_endings(){
    local f="$1"
    if command -v dos2unix >/dev/null 2>&1; then
        dos2unix -q "$f" 2>/dev/null || true
    else
        # fallback: remove CR (\r) at line ends
        sed -i 's/\r$//' "$f" || true
    fi
}

syntax_check(){
    local f="$1"
    if bash -n "$f" 2>/dev/null; then
        return 0
    else
        echo -e "${RED}Syntax error in $f${NC}"
        bash -n "$f" 2>&1 | sed -n '1,200p'
        return 1
    fi
}

# -------------------------
must_be_root

echo -e "${GREEN}Quick Truma installer — downloading files to ${INSTALL_DIR}${NC}"

# ensure curl exists (we need it)
detect_pm_and_install curl dos2unix || true

# prepare dir
if [[ -d "$INSTALL_DIR" ]]; then
    echo -e "${YELLOW}Note: $INSTALL_DIR exists. Backing up to ${INSTALL_DIR}.bak$(date +%s)${NC}"
    mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$(date +%s)" || true
fi
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# download files
for f in "${FILES[@]}"; do
    echo -n "  Downloading $f ... "
    if download_file "${REPO_BASE}/${f}" "$f"; then
        fix_line_endings "$f"
        # common tiny fixes
        sed -i 's/\bcho\b/echo/g' "$f" || true
        chmod +x "$f"
        if syntax_check "$f"; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}SYNTAX FAILED${NC}"
            echo -e "${RED}Aborting installation.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}FAILED${NC}"
        echo -e "${RED}Could not download ${REPO_BASE}/${f}${NC}"
        exit 1
    fi
done

# create symlink
ln -sf "$INSTALL_DIR/truma.sh" "$SYMLINK"
echo -e "${GREEN}Installed to $INSTALL_DIR${NC}"
echo -e "${GREEN}Symlink created: $SYMLINK -> $INSTALL_DIR/truma.sh${NC}"

cat <<EOF

Next steps:
  - Run: sudo truma
  - Or:  sudo $INSTALL_DIR/truma.sh

One-liner to fetch+run this installer (if you trust it):
  curl -fsSL <THIS_SCRIPT_URL> -o /tmp/quick-install.sh && sudo bash /tmp/quick-install.sh

EOF

exit 0
