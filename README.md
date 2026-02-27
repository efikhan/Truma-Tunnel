Truma Tunnel Manager 🚀

https://img.shields.io/badge/License-MIT-yellow.svg
https://img.shields.io/badge/language-bash-green.svg
https://img.shields.io/badge/version-2.1.1-blue.svg
https://img.shields.io/badge/PRs-welcome-brightgreen.svg

Truma is a professional, menu‑driven Bash script suite that simplifies the creation, management, and monitoring of tunneling protocols on Linux servers. It provides a unified interface for GRE, KCP (via Paqet), and EMC (EasyTier Mesh) tunnels, with integrated HAProxy‑based port forwarding and automatic restart scheduling.

🎯 Perfect for bypassing internet censorship, secure remote access, and building VPNs.

---

✨ Key Features

 
🧩 Modular Design Easily add new protocols by dropping in a new manager script.
🎛️ Interactive Menu Navigate with color‑coded logs and clear prompts.
🚀 GRE Tunnels Full support with key, MTU, and IP configuration.
⚡ KCP Tunnels Powered by Paqet – fast, low‑latency, with multiple modes.
🌐 EMC (EasyTier Mesh) Decentralised mesh VPN with encryption and peer discovery.
🔀 Port Forwarding Centralised HAProxy manager for GRE/EMC; Paqet has native TCP forwarding.
⏰ Auto‑Restart Set per‑tunnel cron jobs for automatic restart at chosen intervals.
📏 MTU Adjustment Change MTU on the fly (where supported).
📜 Comprehensive Logging All actions logged and displayed in‑menu.
🔧 Non‑Interactive Mode Suitable for automated deployment (NONINTERACTIVE=1).
🧹 Clean Uninstall Removes service files, configs, cron jobs, and HAProxy rules.

---

🚀 Quick Start

Installation

Choose the installation method that works best for your location:

Option 1: For users outside Iran (fastest)

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/install.sh
sed -i 's/\r$//' install.sh
sudo bash install.sh
```

Option 2: For users inside Iran (if direct download is slow or blocked)

```bash
git clone https://github.com/efikhan/Truma-Tunnel.git
cd Truma-Tunnel
chmod +x *.sh
sed -i 's/\r$//' *.sh
sudo ./truma.sh
```

💡 Note: The sed command removes Windows‑style carriage returns (\r) to avoid common errors.

The installer (Option 1) will:

1. Ask for your server location (Inside Iran / Kharj).
2. Apply Iran‑specific optimizations if you choose "Inside Iran" (IPv6 disable, best DNS/mirror selection, kernel tuning).
3. Clone the repository into /opt/truma.
4. Launch the Truma main menu.

Option 2 simply clones the repository and launches Truma directly, skipping the installer's optimizations. You can still run the installer later if needed by executing sudo bash install.sh from the cloned directory.

Post‑Installation

If you need to run Truma again later:

```bash
cd /opt/truma
sudo ./truma.sh
```

Or if you used Option 2, you can run it from the cloned directory:

```bash
cd Truma-Tunnel
sudo ./truma.sh
```

---

📖 Main Menu

Option Description
1 – Create New Tunnel Select GRE, KCP, or EMC, then follow the prompts.
2 – Show Active Tunnels List existing tunnels and manage them (start/stop/restart/status/auto‑restart/change mode).
3 – Uninstall Tunnel Completely remove a tunnel and all its associated files/rules.
4 – Port Management Add/list/remove HAProxy port forwards, reload HAProxy, or remove all rules.
5 – Anti‑Filter System (placeholder) Future features for bypassing censorship.
6 – Change MTU Modify the MTU of an existing tunnel.
0 – Exit Quit Truma.

---

🔌 Supported Tunnels

1. GRE (Generic Routing Encapsulation)

· Simple point‑to‑point IP tunnels.
· Configurable key, local/remote IP, and MTU.
· No built‑in port forwarding – use HAProxy.

2. KCP (Paqet)

· Fast, reliable, low‑latency UDP‑based protocol.
· Modes: fast, fast2 (recommended), fast3, normal, manual.
· Native TCP port forwarding (for client side).
· Encryption key auto‑generation.

3. EMC (EasyTier Mesh)

· Decentralised mesh VPN.
· Supports TCP, UDP, WS, WSS.
· Built‑in encryption, multi‑threading, IPv6 toggle.
· Peer discovery and routing.

---

🔧 Port Management

· For GRE and EMC tunnels, port forwarding is handled by HAProxy.
  · Rules are stored as individual files in /etc/haproxy/conf.d/.
  · Use the Port Management menu to add/remove rules.
  · Each rule includes a description with the tunnel name for easy identification.
· For Paqet (client side), port forwarding is configured directly in the YAML file. Use the Paqet specific options in the service menu.

---

⏰ Auto‑Restart with Cron

From the service menu, you can set a tunnel to automatically restart at regular intervals:

· Minutes: */5 * * * *
· Hours: 0 */1 * * *

The cron job is automatically removed when you uninstall the tunnel.

---

🗑️ Uninstall

To completely remove a tunnel:

1. Go to the main menu and choose 3 – Uninstall Tunnel.
2. Select the tunnel and confirm by typing yes.
3. All related files (systemd service, config, firewall scripts, cron jobs, HAProxy rules) will be deleted.

If you want to uninstall Truma itself, simply remove the /opt/truma directory and any HAProxy rules you added. The installer does not modify system files beyond what is described.

---

🙏 Acknowledgements

· Aref Hadinezhad – for his invaluable contribution to the GRE tunnel project, which served as the foundation for this work.
· The developers of EasyTier and Paqet for their amazing tunnel engines.
· Musixal for the inspiration from the Easy-Mesh project.

❤️ Support the Project

If you find Truma useful, consider supporting its development:

TRX (TRC20):
TXN5w8E2akLDZEswqcxCjNkJdNQnYRp78H

---

📄 License

This project is licensed under the MIT License – see the LICENSE file for details.

---

📬 Contact & Community

· GitHub Repository: https://github.com/efikhan/Truma-Tunnel
· Telegram Channel: @TrumaTunnel
· Issues: GitHub Issues
