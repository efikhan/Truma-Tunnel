# 🚇 Truma Tunnel Manager v2

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Bash-4.2%2B-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20|%20Ubuntu%20|%20Debian%20|%20CentOS-brightgreen)]()
[![Version](https://img.shields.io/badge/Version-2.0.0-green.svg)]()

**Truma** is a professional, modular Bash script for creating and managing various types of tunnels (GRE, Paqet/KCP, EMC/EasyTier) with a beautiful interactive menu. It centralizes HAProxy port forwarding, supports anti‑filter mechanisms (coming soon), and ensures a clean, complete uninstall – all while maintaining a consistent user experience.

---

## ✨ Key Features

- 🧩 **Modular design** – Each tunnel type (`gre`, `paqet`, `mesh`) is a separate, self‑contained script.
- 🎯 **Multi‑protocol support**:
  - **GRE** – Simple point‑to‑point GRE tunnels.
  - **KCP** – High‑performance KCP tunnels powered by [Paqet](https://github.com/hanselime/paqet).
  - **EMC** – Mesh networks with [EasyTier](https://github.com/EasyTier/EasyTier)
- 🛡️ **Centralized HAProxy management** – All port‑forwarding rules are handled by a dedicated `haproxy-manager.sh` module. Add, list, or remove rules without touching the tunnel configuration.
- 🧹 **Complete uninstall** – Removes systemd services, configuration files, cron jobs, firewall scripts, and even HAProxy rules associated with a tunnel.
- 📊 **Beautiful menu interface** – Colorful, log‑aware, and compatible with non‑interactive environments.
- ⏰ **Auto‑restart cron** – Easily set up periodic tunnel restarts via cron.
- 🔧 **Change MTU** – On‑the‑fly MTU adjustments (supported for GRE and Paqet).
- 🛠️ **Self‑contained** – Automatically installs required packages (`iproute2`, `haproxy`, `curl`, etc.) and the Paqet/EasyTier binaries.
- 🐧 **Cross‑distribution** – Works on Debian, Ubuntu, CentOS, and other Linux distributions thanks to multi‑package‑manager support.
- 🌐 **IPv6 ready** – All tunnels support IPv6 configuration (optional).
- 🔒 **Encryption options** – KCP and EMC tunnels support encryption.

---

## 🚀 Quick Install

Run the following one‑liner as **root** (or with `sudo`):

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/install.sh)"
```

The installer will:

· Download all five scripts to /opt/truma/.
· Make them executable.
· Create a symbolic link /usr/local/bin/truma for easy access.
· Launch Truma automatically.

After installation, just type truma in your terminal to start the manager.

---

📦 Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/efikhan/Truma-Tunnel.git
   cd Truma-Tunnel
   ```
2. Make all scripts executable:
   ```bash
   chmod +x *.sh
   ```
3. Run as root:
   ```bash
   sudo ./truma.sh
   ```

---

📖 Detailed Usage Guide

Main Menu

When you start Truma, you’ll see:

```
  Truma Tunnel Manager
  [1] 🚀 Create New Tunnel
  [2] 🔍 Show Active Tunnels
  [3] 🧹 Uninstall Tunnel
  [4] 🔧 Port Management
  [5] 🛡️ Anti-Filter System
  [6] 📦 Change MTU
  [0] ❌ Exit
```

Navigate by entering the corresponding number.

---

🌐 Creating a GRE Tunnel

GRE is a classic point‑to‑point tunnel. It uses a base network (e.g., 10.20.30.0) to derive the tunnel IPs: the Direct side gets .1, the Remote side gets .2.

Steps on both servers:

1. Select [1] Create New Tunnel → [1] GRE.
2. Choose the side:
   · Direct – typically the Iran server (will later forward ports via HAProxy).
   · Remote – typically the Kharej server.
3. Enter a tunnel name (e.g., mytunnel). Use only letters, numbers, _, or -.
4. Confirm or correct your local public IP (auto‑detected).
5. Enter the remote public IP of the other server.
6. Specify a base network (must start with 10 and end with 0, e.g., 10.20.30.0).
7. For the GRE key, you can either:
   · Press Enter to auto‑generate a random 4‑digit key.
   · Enter a custom number (must be the same on both sides).
8. The tunnel service will be created and started automatically.

Testing the GRE tunnel:

· On Direct side: ping 10.20.30.2
· On Remote side: ping 10.20.30.1

If ping fails, check:

· Firewall rules for protocol 47 (GRE)
· That the GRE key matches on both sides
· System rp_filter settings (set to 0 if needed)

Adding port forwarding (via HAProxy):

· Go to [4] Port Management → [1] Add Port Forward.
· Select your GRE tunnel.
· The target IP will be automatically detected (the peer’s tunnel IP). Confirm or override.
· Enter the bind port (on the Iran side) and the destination port (on the Kharej side).
· The rule is added and HAProxy reloaded automatically.

---

⚡ Creating a KCP Tunnel (Paqet)

KCP tunnels are optimized for high‑latency links and work in client/server mode.

Steps:

1. Select [1] Create New Tunnel → [2] KCP.
2. Choose the side:
   · Direct – client (usually Iran)
   · Remote – server (usually Kharej)
3. Enter a tunnel name.
4. For the client side, enter the remote server IP (the server’s public IP). For the server side, you’ll be prompted for a public IP (auto‑detected; you can confirm or change it).
5. Set the tunnel port (default 8535). Both sides must use the same port.
6. Either auto‑generate or enter an encryption key (must match on both sides).
7. Choose an MTU (default 1280).
8. Select a KCP mode:
   · fast – balanced speed, low latency
   · fast2 – higher speed, lower latency (recommended)
   · fast3 – maximum speed, aggressive
   · normal – conservative, like TCP
   · manual – advanced manual settings
9. For the server side, you may be asked for the gateway MAC (usually auto‑detected; if not, you can enter it manually).
10. For the client side, you can specify forwarded ports (comma‑separated). These ports will be forwarded internally by Paqet, not via HAProxy.

The service will start automatically. Check its status with:

```bash
systemctl status paqet-<name>.service
```

Managing KCP ports:

· Use the [4] Port Management menu, but note that for Paqet, the operations are handled by its own functions (paqet::add_port_interactive, etc.). When you select a Paqet tunnel, you’ll be prompted to add ports in a Paqet‑specific way.

Changing KCP mode:

· In the [2] Show Active Tunnels menu, select your Paqet tunnel and choose option [6] Change Mode (KCP). You can then switch between the available KCP modes without recreating the tunnel.

---

🔗 Creating an EMC Tunnel (EasyTier – Mesh)

EMC creates a mesh network, allowing multiple servers to connect directly. It uses a base network similar to GRE.

Steps:

1. Select [1] Create New Tunnel → [3] EMC.
2. Choose the side:
   · Direct – one peer (e.g., Iran)
   · Remote – another peer (e.g., Kharej)
3. Enter a tunnel name.
4. Specify a base network (e.g., 10.144.144.0). The Direct side will get .1, the Remote side .2.
5. Enter a domain (any label, e.g., IranServer).
6. Set the tunnel port (default 8535).
7. Enter the remote IP of the other server (only one peer at creation time; additional peers can be added later by editing the service file).
8. A network secret will be auto‑generated – you can change it, but it must match on all peers.
9. Choose the protocol (default tcp).
10. Answer prompts for encryption, multi‑thread, and IPv6 (yes/no).

The service will start automatically. Use the [2] Show Active Tunnels menu, select your EMC tunnel, and choose [6] Show Peers to verify connectivity.

Port forwarding with EMC:

EMC does not have built‑in port forwarding. Instead, use the [4] Port Management menu to add HAProxy rules. When you add a rule for an EMC tunnel, the target IP will be auto‑detected as the peer’s tunnel IP (.2 for a Direct server, .1 for a Remote server).

---

🧭 Managing Tunnels

From the main menu, select [2] Show Active Tunnels. You’ll see a list of all existing tunnels. Choose one to enter its management menu:

```
[Tunnel: mytunnel]
  [1] 🟢 Enable & Start
  [2] 🔄 Restart
  [3] ⏹️  Stop & Disable
  [4] 📊 Status
  [5] ⏰ Set Auto Restart (Cron)
  [6] ... (protocol‑specific actions)
  [0] ↩️  Back
```

· Enable & Start – starts and enables the tunnel at boot.
· Restart – restarts the tunnel service.
· Stop & Disable – stops the tunnel and disables autostart.
· Status – shows the current status and recent logs.
· Set Auto Restart – creates a cron job to restart the tunnel periodically (choose minutes or hours).
· Protocol‑specific actions:
  · For Paqet: Change Mode (KCP mode).
  · For EMC: Show Peers (display connected mesh peers).

---

🔧 Port Management (HAProxy)

All HAProxy rules are managed centrally from [4] Port Management. The submenu:

```
  Port Management
  [1] ➕ Add Port Forward (HAProxy for GRE/EMC)
  [2] 📋 List Forwarded Ports
  [3] ❌ Remove Port Forward
  [4] 🔄 Reload HAProxy
  [5] 🗑️  Remove All HAProxy Rules
  [6] 📊 HAProxy Status
  [0] ↩️  Back
```

· Add Port Forward: Select a tunnel (GRE or EMC). The target IP is auto‑detected from the tunnel configuration. You can override it if needed. Then enter the bind port (on the Iran side) and the destination port (on the Kharej side). HAProxy will be reloaded automatically.
· List Forwarded Ports: Select a tunnel to see all HAProxy rules associated with it.
· Remove Port Forward: Select a tunnel, then enter the bind port to remove its rule.
· Reload HAProxy: Force a reload after manual changes (though reloads happen automatically after add/remove).
· Remove All HAProxy Rules: Deletes every rule from HAProxy (use with caution).
· HAProxy Status: Shows the current status of the HAProxy service.

Note: Paqet tunnels manage their own port forwarding internally; they are not affected by this HAProxy menu.

---

🧹 Uninstalling a Tunnel

Select [3] Uninstall Tunnel from the main menu. You will be shown a list of existing tunnels. Choose one, then type yes to confirm. This will:

· Stop and disable the tunnel service.
· Remove its systemd unit file and all symlinks.
· Delete any associated firewall scripts.
· Remove cron jobs created by Truma for that tunnel.
· Also remove any HAProxy rules linked to that tunnel (by scanning rule files for the tunnel name).
· Reload systemd and HAProxy.

After uninstall, no traces of the tunnel remain.

---

📦 Changing MTU

Use [6] Change MTU to adjust the MTU of an existing GRE or Paqet tunnel. Select the tunnel, enter the new MTU value (between 576 and 1600 for GRE, up to 9000 for Paqet), and the script will:

· Update the running interface (if possible).
· Patch the systemd unit file so the change persists after reboot.
· Restart the service.

For EMC tunnels, MTU change is not supported directly (you would need to modify the EasyTier configuration manually).

---

🛡️ Anti-Filter System (Coming Soon)

This menu option is a placeholder for future enhancements that will help bypass internet restrictions. Stay tuned!

---

📁 Project Structure

After installation, all files reside in /opt/truma/:

```
/opt/truma/
├── truma.sh               # Main menu and core functions
├── gre-manager.sh          # GRE tunnel logic
├── paqet.sh                # KCP (Paqet) tunnel logic
├── mesh-manager.sh         # EMC (EasyTier) tunnel logic
└── haproxy-manager.sh      # Centralized HAProxy rule manager
```

A symlink /usr/local/bin/truma points to truma.sh for easy execution.

---

💰 Support Development

If you find Truma useful and want to support its ongoing development, you can send a donation to the following TRC20 address:

TRX (TRC20): TXN5w8E2akLDZEswqcxCjNkJdNQnYRp78H

Your support is greatly appreciated! 🙏

---

📢 Community

Join our Telegram channel for announcements, updates, and discussions:
👉 @TrumaTunnel

---

🙏 Acknowledgements

· Aref Hadinezhad – for his invaluable contribution to the GRE tunnel project, which served as the foundation for this work.
· The developers of EasyTier and Paqet for their amazing tunnel engines.
· Musixal for the inspiration from the Easy-Mesh project.

---

📄 License

This project is licensed under the MIT License – see the LICENSE file for details.

---

⭐ Show Your Support

If you like Truma, please consider giving it a star on GitHub!
For issues or feature requests, open an issue.

---

Truma – Tunnel like a pro! 🚇

```
