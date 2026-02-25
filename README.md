# 🚇 Truma Tunnel Manager v1.9.0

**A professional and powerful script for managing GRE and Paqet tunnels with an intuitive menu interface**

[![GitHub release](https://img.shields.io/github/v/release/efikhan/Truma-Tunnel?include_prereleases&label=version)](https://github.com/efikhan/Truma-Tunnel/releases/tag/v1.9.0)
[![GitHub commits](https://img.shields.io/github/commits/v1.9.0/efikhan/Truma-Tunnel)](https://github.com/efikhan/Truma-Tunnel/commits/v1.9.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-100%25-brightgreen)]()
[![Telegram](https://img.shields.io/badge/Telegram-@efikhan_jr-blue)](https://t.me/efikhan_jr)

---

## ✨ Key Features

| Feature | Description |
|---------|-------------|
| 🚀 **Dual Tunnel Support** | Create and manage both **GRE** (with HAProxy) and **Paqet** (KCP) tunnels from a single unified menu |
| 🎨 **Beautiful Menus** | Colorful, intuitive interface with clear prompts and real‑time action log |
| 🧹 **Complete Removal** | Uninstall tunnels along with all associated files – systemd services, configs, firewall rules, **and cron jobs** – leaving no leftovers |
| 🔄 **Auto Restart (Cron)** | Set up automatic restart of any tunnel with a simple interactive menu (minute/hour intervals) |
| 📋 **Port Management** | Easily add, list, or remove forwarded ports for any tunnel |
| ⚙️ **MTU Control** | Change MTU of any tunnel on the fly |
| 🔧 **Paqet Mode Switching** | Switch between KCP modes (`fast`, `fast2`, `fast3`, `normal`, `manual`) interactively |
| 🛡️ **Anti‑Filter (Planned)** | A future update will reintroduce anti‑filter features (currently placeholder) |

---

## 📥 Installation

### 🔹 Automatic (Recommended – always gets latest version)
Run this one‑liner on your server as **root**:
```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/install.sh)"
```

🔹 Download Specific Version (v1.9.0)

You can download the three main script files directly from the v1.9.0 Release page:

· truma.sh – Main unified manager
· gre-manager.sh – GRE tunnel engine
· paqet.sh – Paqet tunnel engine

After downloading, make them executable and run:

```bash
chmod +x truma.sh gre-manager.sh paqet.sh
sudo ./truma.sh
```

🔹 Manual Installation (from source archive)

```bash
wget https://github.com/efikhan/Truma-Tunnel/archive/refs/tags/v1.9.0.tar.gz
tar -xzf v1.9.0.tar.gz
cd Truma-Tunnel-1.9.0
sudo ./install.sh
```

After installation, the main script truma.sh will be available. You can run it anytime with:

```bash
sudo ./truma.sh
```

---

🚀 Quick Start Guide

After launching truma.sh, the main menu appears:

```
  [1] 🚀 Create New Tunnel
  [2] 🔍 Show Active Tunnels
  [3] 🧹 Uninstall Tunnel
  [4] 🔧 Port Management
  [5] 🛡️ Anti-Filter System
  [6] 📦 Change MTU
  [0] ❌ Exit
```

Creating a Tunnel

Select 1 and then choose the tunnel type:

```
Select tunnel type:
1) GRE (with HAProxy)
2) Paqet (KCP)
```

GRE Tunnel Steps

1. Choose side – Iran (with HAProxy) or Kharej (without HAProxy)
2. Enter tunnel name – e.g., mygre (letters, numbers, _, - allowed)
3. Confirm local IP – detected automatically; confirm or enter manually
4. Enter remote IP – public IP of the opposite server
5. Enter base network – must start with 10 and end with .0, e.g., 10.20.30.0
6. GRE key – automatically generated and displayed (save it for the opposite side)
7. If Iran side: enter ports to forward (comma‑separated, e.g., 80,443,8535)
8. Tunnel is created and started – status is shown

Paqet Tunnel Steps

1. Choose side – Iran (client) or Kharej (server)
2. Enter tunnel name – same rules as GRE
3. If client: enter remote server IP
4. Enter tunnel port – e.g., 2095 (default)
5. Encryption key – auto‑generated (displayed) or you can enter your own
6. Enter MTU – default 1280 (you can change later via menu)
7. Choose KCP mode – select one of the five modes (default fast2)
8. Gateway MAC – auto‑detected; if detection fails, you will be prompted to enter it
9. If client: enter forwarded ports (comma‑separated) or leave empty
10. Tunnel is created and started – key and status displayed

---

🔍 Managing Tunnels

From the main menu, select [2] Show Active Tunnels, then choose a tunnel to see its service menu:

```
  Tunnel: mytunnel

  [1] 🟢 Enable & Start
  [2] 🔄 Restart
  [3] ⏹️  Stop & Disable
  [4] 📊 Status
  [5] ⏰ Set Auto Restart (Cron)
  [6] 🔧 Change Mode          (Paqet only)
  [0] ↩️  Back
```

Auto Restart (Cron)

When you select [5], you can:

· Remove any existing cron job for this tunnel
· Set a new restart interval (minutes or hours)

The cron job will be automatically removed when you uninstall the tunnel via the script.

---

🧹 Manual Cleanup Commands

If you ever need to completely remove a tunnel manually (e.g., if the script’s uninstall fails), use the following commands.

🟢 Remove a GRE tunnel named erfan

```bash
# Stop and disable service
systemctl stop erfan.service 2>/dev/null
systemctl disable erfan.service 2>/dev/null

# Remove service file and symlinks
rm -f /etc/systemd/system/erfan.service
find /etc/systemd/system -type l -name "erfan.service" -delete 2>/dev/null

# Remove HAProxy config
rm -f /etc/haproxy/conf.d/erfan.cfg

# Delete GRE interface
ip link set erfan down 2>/dev/null
ip tunnel del erfan 2>/dev/null

# Remove any cron jobs for this tunnel
crontab -l 2>/dev/null | grep -v "systemctl restart erfan.service" | crontab - 2>/dev/null

# Reload systemd
systemctl daemon-reload
systemctl reset-failed 2>/dev/null
```

🔵 Remove a Paqet tunnel named erfan

```bash
# Stop and disable all related services
systemctl stop paqet-erfan.service paqet@erfan.service paqet-fw-erfan.service 2>/dev/null
systemctl disable paqet-erfan.service paqet@erfan.service paqet-fw-erfan.service 2>/dev/null

# Remove service files
rm -f /etc/systemd/system/paqet-erfan.service /etc/systemd/system/paqet@erfan.service /etc/systemd/system/paqet-fw-erfan.service

# Remove config and firewall script
rm -f /etc/paqet-tunnel/instances/erfan.yaml
rm -f /etc/paqet-tunnel/firewall/fw-erfan.sh

# Remove cron jobs (both direct commands and script‑based)
crontab -l 2>/dev/null | grep -v "systemctl restart erfan.service" | grep -v "truma-restart-erfan" | crontab - 2>/dev/null

# Remove any dummy scripts (if present)
rm -f /usr/local/bin/truma-restart-erfan.sh /usr/local/bin/truma-dummy-erfan.sh 2>/dev/null

# Reload systemd
systemctl daemon-reload
systemctl reset-failed 2>/dev/null
```

After running these commands, no trace of the tunnel remains.

---

📂 File Structure (v1.9.0)

```
/etc/systemd/system/
 ├── <name>.service                # GRE tunnel
 ├── paqet-<name>.service           # Paqet tunnel (dash style)
 ├── paqet@<name>.service           # Paqet tunnel (at style)
 └── paqet-fw-<name>.service        # Paqet firewall service

/etc/haproxy/conf.d/
 └── <name>.cfg                     # HAProxy per‑tunnel config (GRE)

/etc/paqet-tunnel/
 ├── instances/
 │   └── <name>.yaml                 # Paqet configuration
 └── firewall/
     └── fw-<name>.sh                 # Paqet firewall rules

/usr/local/bin/
 ├── truma-restart-<name>.sh         # (optional) restart script for cron
 └── truma-dummy-<name>.sh            # (optional) dummy traffic script

Installation directory (where you extracted the archive):
 ├── truma.sh                        # Main unified script
 ├── gre-manager.sh                   # GRE engine module
 └── paqet.sh                         # Paqet engine module
```

---

💰 Support the Project

If you find this tool useful, consider donating to support development:

TRON (TRC20):
TXN5w8E2akLDZEswqcxCjNkJdNQnYRp78H

---

📬 Contact & Community

· GitHub: efikhan/Truma-Tunnel
· Telegram (Developer): @efikhan_jr
· Channel (Announcements): @TrumaTunnel

---

📄 License

This project is licensed under the MIT License – see the LICENSE file for details.

---

Dedicated to the martyrs of freedom.

```

### 📝 تغییرات اعمال‌شده:
1. **لینک‌های دانلود دقیق:**  
   - در بخش نصب خودکار، لینک به شاخه `main` تغییر یافت تا کاربران همیشه آخرین نسخه را دریافت کنند.  
   - در بخش دانلود نسخه مشخص، لینک‌های مستقیم به سه فایل اصلی از صفحه Release v1.9.0 اضافه شد.  
   - لینک دانلود آرشیو سورس (tar.gz) نیز به‌روزرسانی شد.

2. **توضیحات حذف دستی:**  
   - دستورات حذف دستی برای GRE و Paqet به‌صورت جداگانه و کامل (شامل حذف کرون‌جاب‌ها و dummy scripts) آورده شده است.

3. **ساختار فایل‌ها:**  
   - مسیر دقیق فایل‌های مربوط به هر تانل فهرست شده است.

اکنون README شما کامل، دقیق و کاربردی است. می‌توانید آن را در ریپوی خود جایگزین کنید.
