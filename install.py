#!/usr/bin/env python3
"""
Truma Tunnel Manager Python Installer
--------------------------------------
This script replaces install.sh and automatically:
- Shows a menu to choose server location (Iran / Kharj).
- If Iran is selected, applies Iran‑specific optimizations (IPv6, DNS, mirror, kernel).
- Installs all required dependencies (curl, git, iptables, iproute2, openssl, systemd).
- Clones the repository or directly downloads the files.
- Permanently solves the CRLF issue (converts all files to LF).
- Finally launches truma.sh.

Version: 2.1.4
"""

import os
import sys
import subprocess
import shutil
import tempfile
import time
import re
import argparse
from pathlib import Path

# -------------------- Configuration --------------------
INSTALL_DIR = "/opt/truma"
REPO_URL = "https://github.com/efikhan/Truma-Tunnel.git"
LOG_FILE = "/var/log/truma-full-install.log"

# -------------------- Logging --------------------
def log(msg):
    timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
    with open(LOG_FILE, 'a', encoding='utf-8') as f:
        f.write(f"{timestamp} - {msg}\n")
    print(msg)

def print_step(msg):   log(f"[*] {msg}")
def print_success(msg): log(f"[✓] {msg}")
def print_error(msg):   log(f"[✗] {msg}"); sys.exit(1)
def print_warning(msg): log(f"[!] {msg}")
def print_info(msg):    log(f"[i] {msg}")

# -------------------- Helpers --------------------
def check_root():
    if os.geteuid() != 0:
        print_step("This script must be run as root. Re‑running with sudo...")
        os.execvp("sudo", ["sudo", sys.executable] + sys.argv)

def backup_file(path):
    """Create a timestamped backup of a file."""
    if os.path.isfile(path):
        backup = f"{path}.backup.{int(time.time())}"
        shutil.copy2(path, backup)
        print_info(f"Backed up: {backup}")

def detect_package_manager():
    if shutil.which("apt-get"):   return "apt-get"
    if shutil.which("yum"):       return "yum"
    if shutil.which("dnf"):       return "dnf"
    if shutil.which("pacman"):    return "pacman"
    if shutil.which("apk"):       return "apk"
    return None

def run_cmd(cmd, check=True, capture=True):
    """
    Run a command (given as a list) and return the CompletedProcess.
    If check=True and the command fails, the script exits.
    """
    cmd_str = ' '.join(cmd) if isinstance(cmd, list) else cmd
    print_step(f"Running: {cmd_str}")
    proc = subprocess.run(cmd, capture_output=capture, text=True)
    if check and proc.returncode != 0:
        print_error(f"Command failed: {proc.stderr}")
    return proc

def install_packages(pkg_manager, packages):
    """Install a list of packages using the detected package manager."""
    if pkg_manager == "apt-get":
        run_cmd(["apt-get", "update", "-qq"], check=False)
        run_cmd(["apt-get", "install", "-y", "-qq"] + packages)
    elif pkg_manager == "yum":
        run_cmd(["yum", "install", "-y", "-q"] + packages)
    elif pkg_manager == "dnf":
        run_cmd(["dnf", "install", "-y", "-q"] + packages)
    elif pkg_manager == "pacman":
        run_cmd(["pacman", "-S", "--noconfirm"] + packages)
    elif pkg_manager == "apk":
        run_cmd(["apk", "add", "--no-cache"] + packages)
    else:
        print_error("Unsupported package manager.")

# -------------------- Dependency Installation --------------------
def install_dependencies():
    print_step("Installing required packages...")
    pkg_manager = detect_package_manager()
    if not pkg_manager:
        print_error("Could not detect a supported package manager. Please install manually: curl, git, iptables, iproute2, openssl, systemd")

    # Package lists per distribution
    pkgs_map = {
        "apt-get": ["curl", "dnsutils", "git", "iptables", "iproute2", "openssl", "systemd"],
        "yum":     ["curl", "bind-utils", "git", "iptables", "iproute", "openssl", "systemd"],
        "dnf":     ["curl", "bind-utils", "git", "iptables", "iproute", "openssl", "systemd"],
        "pacman":  ["curl", "bind", "git", "iptables", "iproute2", "openssl", "systemd"],
        "apk":     ["curl", "bind-tools", "git", "iptables", "iproute2", "openssl", "openrc"],
    }
    packages = pkgs_map.get(pkg_manager, [])
    install_packages(pkg_manager, packages)
    print_success("All dependencies installed.")

# -------------------- Disk Space Check --------------------
def check_disk_space(required_mb=100):
    """Check free space on the root partition (in MB)."""
    stat = os.statvfs('/')
    available_mb = (stat.f_frsize * stat.f_bavail) / (1024 * 1024)
    if available_mb < required_mb:
        print_error(f"Insufficient disk space: need {required_mb} MB, have {int(available_mb)} MB")
    print_info(f"Disk space OK: {int(available_mb)} MB available.")

# -------------------- Iran Optimizations --------------------
def disable_ipv6():
    print_step("Disabling IPv6...")
    run_cmd(["sysctl", "-w", "net.ipv6.conf.all.disable_ipv6=1"], check=False)
    run_cmd(["sysctl", "-w", "net.ipv6.conf.default.disable_ipv6=1"], check=False)
    conf = "/etc/sysctl.d/99-ipv6-disable.conf"
    backup_file(conf)
    with open(conf, "w") as f:
        f.write("net.ipv6.conf.all.disable_ipv6 = 1\n")
        f.write("net.ipv6.conf.default.disable_ipv6 = 1\n")
        f.write("net.ipv6.conf.lo.disable_ipv6 = 1\n")
    run_cmd(["sysctl", "-p", conf], check=False)
    print_success("IPv6 disabled.")

def apply_kernel_tuning():
    print_step("Applying kernel network optimizations...")
    conf = "/etc/sysctl.d/99-network-performance.conf"
    backup_file(conf)
    if os.path.exists("/proc/sys/net/ipv4/tcp_congestion_control"):
        run_cmd(["modprobe", "tcp_bbr"], check=False)
        with open(conf, "a") as f:
            f.write("net.core.default_qdisc = fq\n")
            f.write("net.ipv4.tcp_congestion_control = bbr\n")
    params = [
        "net.core.rmem_max = 134217728",
        "net.core.wmem_max = 134217728",
        "net.ipv4.tcp_rmem = 4096 87380 134217728",
        "net.ipv4.tcp_wmem = 4096 65536 134217728",
        "net.core.netdev_max_backlog = 5000",
        "net.ipv4.tcp_fastopen = 3",
        "net.ipv4.tcp_slow_start_after_idle = 0",
    ]
    with open(conf, "a") as f:
        for p in params:
            f.write(p + "\n")
    run_cmd(["sysctl", "-p", conf], check=False)
    print_success("Kernel tuning applied.")

def select_best_dns():
    print_step("Testing Iranian DNS servers...")
    dns_list = [
        ("178.22.122.100", "Shekan"),
        ("185.51.200.2", "Shekan"),
        ("10.202.10.202", "403 Online"),
        ("10.202.10.102", "403 Online"),
        ("78.157.42.100", "Electro"),
        ("78.157.42.101", "Electro"),
        ("185.55.226.26", "Begzar"),
        ("185.55.225.25", "Begzar"),
        ("5.202.100.100", "Pishgaman"),
        ("5.202.100.101", "Pishgaman"),
        ("94.103.125.157", "Shelter"),
        ("94.103.125.158", "Shelter"),
        ("181.41.194.177", "Beshekan"),
        ("181.41.194.186", "Beshekan"),
    ]
    best_dns = None
    best_time = 999999
    for dns, name in dns_list:
        print(f"  Testing {name} ({dns}) ... ", end="", flush=True)
        proc = run_cmd(["timeout", "3", "dig", "+time=2", "+tries=1", "google.com", f"@{dns}"], check=False, capture=True)
        if proc.returncode == 0:
            m = re.search(r"Query time:\s*(\d+)", proc.stdout)
            if m:
                t = int(m.group(1))
                print(f"{t} ms")
                if t < best_time:
                    best_time = t
                    best_dns = dns
            else:
                print("Failed")
        else:
            print("Failed")
    if best_dns:
        print_success(f"Best DNS: {best_dns} ({best_time} ms)")
        backup_file("/etc/resolv.conf")
        if os.path.exists("/run/systemd/resolve/stub-resolv.conf"):
            with open("/etc/systemd/resolved.conf", "w") as f:
                f.write(f"[Resolve]\nDNS={best_dns} 8.8.8.8 1.1.1.1\n")
            run_cmd(["systemctl", "restart", "systemd-resolved"])
        else:
            run_cmd(["chattr", "-i", "/etc/resolv.conf"], check=False)
            with open("/etc/resolv.conf", "w") as f:
                f.write("# Set by Truma Installer\n")
                f.write(f"nameserver {best_dns}\n")
                f.write("nameserver 8.8.8.8\n")
                f.write("nameserver 1.1.1.1\n")
            run_cmd(["chattr", "+i", "/etc/resolv.conf"], check=False)
        print_success("DNS configured.")
    else:
        print_warning("No suitable DNS found; using default.")

def select_best_mirror():
    print_step("Testing mirrors...")
    mirrors = [
        ("mirror.iranserver.com", "IR Server"),
        ("ir.ubuntu.sindad.cloud", "Sindad"),
        ("mirror.arvancloud.ir", "ArvanCloud"),
        ("archive.ubuntu.petiak.ir", "Petiak"),
        ("ubuntu.hostiran.ir", "HostIran"),
        ("mirrors.pardisco.co", "PardisCo"),
        ("ubuntu.pars.host", "ParsHost"),
        ("mirror.0-1.cloud", "0-1 Cloud"),
        ("repo.linuxmirrors.ir", "Linux Mirrors"),
        ("ubuntu.shatel.ir", "Shatel"),
        ("archive.ubuntu.com", "Main Archive"),
        ("mirrors.edge.kernel.org", "Kernel"),
        ("mirrors.aliyun.com", "Aliyun"),
        ("mirror.ubuntu.com", "Ubuntu Mirror"),
    ]
    # Detect distribution and codename
    distro = "ubuntu"
    codename = "noble"
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("ID="):
                    distro = line.strip().split("=")[1].strip('"')
                elif line.startswith("VERSION_CODENAME="):
                    codename = line.strip().split("=")[1].strip('"')
    except:
        pass

    if distro in ["ubuntu", "debian"]:
        test_path = f"dists/{codename}/InRelease"
    else:
        # Fallback for RHEL‑like distributions
        test_path = "os/x86_64/repodata/repomd.xml"

    best_mirror = None
    best_speed = 0
    for mirror, name in mirrors:
        print(f"  Testing {name} ({mirror}) ... ", end="", flush=True)
        if distro in ["ubuntu", "debian"]:
            url = f"http://{mirror}/{distro}/{test_path}"
        else:
            # For RHEL‑like, use a CentOS style path (adjust as needed)
            url = f"http://{mirror}/centos/{test_path}"
        proc = run_cmd(["curl", "--fail", "-s", "-w", "%{speed_download}", "-o", "/dev/null", "--max-time", "5", url], check=False, capture=True)
        if proc.returncode == 0 and proc.stdout.strip():
            speed_kb = int(float(proc.stdout.strip()) / 1024)
            print(f"{speed_kb} KB/s")
            if speed_kb > best_speed:
                best_speed = speed_kb
                best_mirror = mirror
        else:
            print("Failed")
    if best_mirror:
        print_success(f"Best mirror: {best_mirror} ({best_speed} KB/s)")
        if distro in ["ubuntu", "debian"] and os.path.exists("/etc/apt/sources.list"):
            backup_file("/etc/apt/sources.list")
            with open("/etc/apt/sources.list") as f:
                content = f.read()
            # Replace any ubuntu/debian mirror with the best one
            new_content = re.sub(r"(https?://)[^/]+/(ubuntu|debian)", rf"\1{best_mirror}/\2", content)
            with open("/etc/apt/sources.list", "w") as f:
                f.write(new_content)
            run_cmd(["apt", "update"], check=False)
            print_success("APT sources updated.")
    else:
        print_warning("No suitable mirror found.")

def run_iran_optimizations():
    disable_ipv6()
    select_best_dns()
    select_best_mirror()
    apply_kernel_tuning()
    print_success("Iran optimizations completed.")

# -------------------- Truma Installation --------------------
def install_truma():
    print_step("Installing Truma Tunnel Manager...")
    check_disk_space(20)

    # Backup existing installation
    if os.path.exists(INSTALL_DIR):
        backup_dir = f"/opt/truma.backup.{int(time.time())}"
        shutil.move(INSTALL_DIR, backup_dir)
        print_info(f"Backed up existing installation to {backup_dir}")

    # Clone repository
    print_step("Cloning Truma repository...")
    with tempfile.TemporaryDirectory() as tmpdir:
        run_cmd(["git", "clone", "--depth", "1", REPO_URL, tmpdir])
        shutil.move(tmpdir, INSTALL_DIR)

    # Fix CRLF in all .sh files
    print_step("Converting all .sh files to LF line endings...")
    for sh_file in Path(INSTALL_DIR).glob("*.sh"):
        with open(sh_file, "rb") as f:
            content = f.read()
        content = content.replace(b"\r\n", b"\n")
        with open(sh_file, "wb") as f:
            f.write(content)
        os.chmod(sh_file, 0o755)

    print_success("Truma Tunnel Manager installed successfully!")
    print_info(f"Installation directory: {INSTALL_DIR}")
    return INSTALL_DIR

# -------------------- Interactive Menu --------------------
def show_menu():
    print("\nSelect your server location:")
    print("  1) Inside Iran")
    print("  2) Outside Iran (Kharj)")
    choice = input("Choice [1-2] (default: 1): ").strip() or "1"
    return choice

# -------------------- Main --------------------
def main():
    parser = argparse.ArgumentParser(description="Truma Tunnel Manager Python Installer")
    parser.add_argument("--iran", action="store_true", help="Apply Iran optimizations (bypass interactive menu)")
    args = parser.parse_args()

    check_root()

    # Step 1: Determine server location (menu or argument)
    if args.iran:
        choice = "1"
        print_info("Applying Iran optimizations (--iran flag detected).")
    else:
        choice = show_menu()

    # Step 2: Install dependencies (needed for both optimization and installation)
    install_dependencies()

    # Step 3: If inside Iran, apply optimizations
    if choice == "1":
        print_info("Server is inside Iran. Applying optimizations...")
        run_iran_optimizations()
    else:
        print_info("Server is outside Iran. Skipping optimizations.")

    # Step 4: Install Truma
    install_dir = install_truma()

    # Step 5: Launch Truma
    truma_script = os.path.join(install_dir, "truma.sh")
    if os.path.exists(truma_script):
        print_step("Launching Truma...")
        os.execv(truma_script, [truma_script])
    else:
        print_error("truma.sh not found after installation!")

if __name__ == "__main__":
    main()