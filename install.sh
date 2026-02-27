#!/usr/bin/env python3
# =============================================================================
# Truma Tunnel Manager – Professional Installer (Final Version)
# Smart Mirror + Smart DNS + Full Rollback + CRLF Fix
# Appearance kept 100% the same as your original Bash version
# =============================================================================

import os
import sys
import subprocess
import shutil
import tempfile
import time
import re
import signal
from pathlib import Path

# -------------------- Global Variables --------------------
AUTO_YES = False
INSTALL_LOG = "/var/log/truma-install.log"
BACKUP_FILES = []  # لیست فایل‌های پشتیبان‌گیری‌شده
COLORS = {
    'RED': '\033[0;31m',
    'GREEN': '\033[0;32m',
    'YELLOW': '\033[1;33m',
    'CYAN': '\033[0;36m',
    'BLUE': '\033[0;34m',
    'MAGENTA': '\033[0;35m',
    'WHITE': '\033[1;37m',
    'NC': '\033[0m'
}

# -------------------- Logging --------------------
def log(msg):
    timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
    with open(INSTALL_LOG, 'a', encoding='utf-8') as f:
        f.write(f"{timestamp} - {msg}\n")
    print(msg)

def print_step(msg):   log(f"{COLORS['CYAN']}[*]{COLORS['NC']} {msg}")
def print_success(msg): log(f"{COLORS['GREEN']}[✓]{COLORS['NC']} {msg}")
def print_error(msg):   log(f"{COLORS['RED']}[✗]{COLORS['NC']} {msg}"); sys.exit(1)
def print_warning(msg): log(f"{COLORS['YELLOW']}[!]{COLORS['NC']} {msg}")
def print_info(msg):    log(f"{COLORS['BLUE']}[i]{COLORS['NC']} {msg}")

# -------------------- Helpers --------------------
def pause_enter():
    if AUTO_YES:
        return
    input("\nPress ENTER to continue...")

def confirm(prompt, default='y'):
    if AUTO_YES:
        return True
    while True:
        answer = input(f"{COLORS['YELLOW']}{prompt} (y/n) [default: {default}]{COLORS['NC']} ").strip().lower()
        if answer == '':
            answer = default
        if answer in ('y', 'yes'):
            return True
        if answer in ('n', 'no'):
            return False
        print("Please answer y or n.")

def die(msg):
    print_error(msg)
    sys.exit(1)

def render_box(title, content):
    print("┌──────────────────────────────────────────────────────────────┐")
    print(f"│  {title:<68}  │")
    print("├──────────────────────────────────────────────────────────────┤")
    for line in content.split('\n'):
        print(f"│  {line:<68}  │")
    print("└──────────────────────────────────────────────────────────────┘")

# -------------------- Backup & Rollback --------------------
def backup_file(path):
    """Create a timestamped backup of a file and record it."""
    if os.path.isfile(path):
        timestamp = time.time()
        backup_path = f"{path}.truma.bak.{int(timestamp)}.{int((timestamp % 1)*1e9)}"
        shutil.copy2(path, backup_path)
        BACKUP_FILES.append((path, backup_path))
        log(f"Backed up {path} -> {backup_path}")

def rollback_all():
    print_warning("Rolling back changes...")
    for src, dst in BACKUP_FILES:
        if os.path.isfile(dst):
            shutil.copy2(dst, src)
            log(f"Restored {src}")

# -------------------- Signal Handling --------------------
def signal_handler(sig, frame):
    rollback_all()
    sys.exit(1)

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

# -------------------- Package Installation --------------------
def install_pkg(pkg):
    """Install a package using the system's package manager."""
    if shutil.which('apt-get'):
        subprocess.run(['apt-get', 'update', '-qq'], check=False)
        return subprocess.run(['apt-get', 'install', '-y', '-qq', pkg], check=False).returncode == 0
    elif shutil.which('yum'):
        return subprocess.run(['yum', 'install', '-y', '-q', pkg], check=False).returncode == 0
    elif shutil.which('dnf'):
        return subprocess.run(['dnf', 'install', '-y', '-q', pkg], check=False).returncode == 0
    else:
        return False

def ensure_cmd(cmd, *candidates):
    """Ensure a command exists, install it if possible."""
    if shutil.which(cmd):
        return True
    for pkg in candidates:
        if install_pkg(pkg):
            if shutil.which(cmd):
                print_success(f"Installed {pkg} (provides {cmd})")
                return True
    die(f"Failed to install {cmd}. Please install {', '.join(candidates)} manually.")

# -------------------- Smart Mirror Optimizer --------------------
def smart_mirror_optimizer():
    """Test 14 mirrors and select the fastest one for Ubuntu."""
    os.system('clear')
    banner()
    print()
    print(f"{COLORS['CYAN']}══════════════════════════════════════════════════{COLORS['NC']}")
    print(f"{COLORS['GREEN']}  Finding the Fastest Ubuntu Mirror{COLORS['NC']}")
    print(f"{COLORS['CYAN']}══════════════════════════════════════════════════{COLORS['NC']}")
    print()

    # Detect Ubuntu codename
    ubuntu_codename = "noble"
    try:
        result = subprocess.run(['lsb_release', '-sc'], capture_output=True, text=True)
        if result.returncode == 0:
            ubuntu_codename = result.stdout.strip()
    except:
        pass

    mirrors = [
        "mirror.iranserver.com",
        "ir.ubuntu.sindad.cloud",
        "mirror.arvancloud.ir",
        "archive.ubuntu.petiak.ir",
        "ubuntu.hostiran.ir",
        "mirrors.pardisco.co",
        "ubuntu.pars.host",
        "mirror.0-1.cloud",
        "repo.linuxmirrors.ir",
        "ubuntu.shatel.ir",
        "archive.ubuntu.com",
        "mirrors.edge.kernel.org",
        "mirrors.aliyun.com",
        "mirror.ubuntu.com"
    ]

    best_mirror = None
    best_speed = 0
    for mirror in mirrors:
        print(f"  Testing {mirror} ... ", end='', flush=True)
        url = f"http://{mirror}/ubuntu/dists/{ubuntu_codename}/InRelease"
        try:
            result = subprocess.run(
                ['curl', '-s', '-w', '%{speed_download}', '-o', '/dev/null', '--max-time', '8', url],
                capture_output=True, text=True, check=False
            )
            if result.returncode == 0 and result.stdout.strip():
                speed = int(float(result.stdout.strip()) / 1024)  # KB/s
                print(f"{speed} KB/s")
                if speed > best_speed:
                    best_speed = speed
                    best_mirror = mirror
            else:
                print("Failed")
        except Exception:
            print("Failed")

    if best_mirror:
        print_success(f"Best mirror: {best_mirror} ({best_speed} KB/s)")
        if os.path.exists("/etc/apt/sources.list"):
            backup_file("/etc/apt/sources.list")
            with open("/etc/apt/sources.list", 'r') as f:
                content = f.read()
            # Replace any archive.ubuntu.com with the best mirror
            new_content = re.sub(r'http://[a-zA-Z0-9.-]*archive\.ubuntu\.com/ubuntu', f'http://{best_mirror}/ubuntu', content)
            with open("/etc/apt/sources.list", 'w') as f:
                f.write(new_content)
            subprocess.run(['apt', 'update', '-qq'], check=False)
    else:
        print_warning("No suitable mirror found.")

# -------------------- Banner --------------------
def banner():
    print(f"{COLORS['MAGENTA']}")
    print("████████╗██████╗ ██╗   ██╗███╗   ███╗ █████╗")
    print("╚══██╔══╝██╔══██╗██║   ██║████╗ ████║██╔══██╗")
    print("   ██║   ██████╔╝██║   ██║██╔████╔██║███████║")
    print("   ██║   ██╔══██╗██║   ██║██║╚██╔╝██║██╔══██║")
    print("   ██║   ██║  ██║╚██████╔╝██║ ╚═╝ ██║██║  ██║")
    print("   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝")
    print("          Truma Tunnel Manager Installer")
    print(f"{COLORS['NC']}")

# -------------------- Download Files --------------------
def download_files():
    """Download the required script files from GitHub release."""
    files = ["truma.sh", "gre-manager.sh", "paqet.sh", "mesh-manager.sh", "haproxy-manager.sh"]
    base_url = "https://github.com/efikhan/Truma-Tunnel/releases/download/v2.1.1"

    with tempfile.TemporaryDirectory() as tmpdir:
        for file in files:
            print(f"  {file} ... ", end='', flush=True)
            url = f"{base_url}/{file}"
            dest = os.path.join(tmpdir, file)
            result = subprocess.run(
                ['curl', '-fSL', '--connect-timeout', '15', '-o', dest, url],
                capture_output=True, text=True, check=False
            )
            if result.returncode == 0:
                shutil.copy2(dest, f"./{file}")
                print(f"{COLORS['GREEN']}OK{COLORS['NC']}")
            else:
                print(f"{COLORS['RED']}FAILED{COLORS['NC']}")
                die(f"Failed to download {file}")

# -------------------- Fix CRLF --------------------
def fix_crlf():
    """Convert Windows line endings to Unix (LF) for all .sh files in current directory."""
    print_step("Fixing line endings (CRLF -> LF)...")
    for sh_file in Path('.').glob('*.sh'):
        with open(sh_file, 'rb') as f:
            content = f.read()
        content = content.replace(b'\r\n', b'\n')
        with open(sh_file, 'wb') as f:
            f.write(content)
        os.chmod(sh_file, 0o755)
    print_success("Line endings fixed.")

# -------------------- Main --------------------
def main():
    global AUTO_YES
    # Parse command line arguments
    args = sys.argv[1:]
    for arg in args:
        if arg in ('-y', '--yes'):
            AUTO_YES = True
        else:
            print_error(f"Unknown option: {arg}")
            sys.exit(1)

    # Ensure log directory exists
    os.makedirs(os.path.dirname(INSTALL_LOG), exist_ok=True)
    with open(INSTALL_LOG, 'a'):
        pass

    os.system('clear')
    banner()
    print()

    if os.geteuid() != 0:
        die("This script must be run as root.")

    ensure_cmd('curl', 'curl')
    ensure_cmd('ping', 'iputils-ping')

    smart_mirror_optimizer()

    os.system('clear')
    banner()
    print()
    render_box("Downloading Files", "Truma Tunnel Manager v2.0.0\n\n• truma.sh\n• gre-manager.sh\n• paqet.sh\n• mesh-manager.sh\n• haproxy-manager.sh")
    print()

    download_files()

    print_step("Setting execute permissions...")
    for file in ["truma.sh", "gre-manager.sh", "paqet.sh", "mesh-manager.sh", "haproxy-manager.sh"]:
        os.chmod(file, 0o755)

    fix_crlf()

    print()
    render_box("Installation Complete", "Smart mirror optimization done.\nAll files ready.\n\nRun ./truma.sh")
    print()
    input("Press ENTER to start Truma Tunnel Manager...")
    os.execv("./truma.sh", ["./truma.sh"])

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        rollback_all()
        raise
