---

# 🚇 Truma Tunnel Manager

<div align="center">
  <img src="https://img.shields.io/badge/version-2.0-blue?style=for-the-badge" alt="Version 2.0">
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="MIT License">
  <img src="https://img.shields.io/badge/platform-Linux-red?style=for-the-badge" alt="Platform Linux">
  <img src="https://img.shields.io/badge/bash-5.0%2B-orange?style=for-the-badge" alt="Bash 5.0+">
</div>

<p align="center">
  <b>An advanced GRE tunnel manager with powerful anti-filtering capabilities</b>
</p>

<p align="center">
  <i>Professional GRE Tunnel & Anti-Filter System</i>
</p>

---

## 📥 Installation

### One-line automatic install (Recommended)

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/install.sh)"

Manual installation

wget https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/install.sh
chmod +x install.sh
sudo ./install.sh


---

🚀 Tunnel Creation Guide

After running install.sh, the main menu will appear.

Choose:

[1] 🚀 Create New Tunnel

Steps

1. Select Server Side



1) Iran (with HAProxy)
2) Kharej (without HAProxy)

2. Enter Tunnel Name



Enter tunnel name (letters/numbers only):

3. Confirm Local IP



Detected your local IP: x.x.x.x
Is this correct? [Y/n]:

4. Enter Remote IP



Enter remote IP:

5. Enter Base Network



Enter base network (must start with 10 and end with 0):

Example:

10.10.10.0

6. Set MTU (Optional)


7. Forward Ports (Iran side only)



Forward PORT (e.g. 80,443,2053):


---

✨ Features

🚀 Easy GRE tunnel creation

🛡️ Advanced anti-filter system

🌐 Smart HAProxy port forwarding

🔄 Automatic restart via cron jobs

📊 Full service lifecycle management

⚙️ Custom MTU and network control



---

🧠 Anti-Filter System Explained

The anti-filter system is designed to make GRE tunnel traffic look like normal user activity.

It uses:

1. HTTPS-like behavior through HAProxy


2. Periodic GRE tunnel restart via cron


3. Dummy HTTPS traffic generation (simulating normal browsing)



This helps prevent detection by DPI (Deep Packet Inspection) systems.


---

📂 File Structure

/etc/systemd/system/
 ├── [tunnel-name].service
 ├── sepehr-dummy-[tunnel-name].service

/etc/haproxy/conf.d/
 └── [tunnel-name].cfg

/usr/local/bin/
 ├── sepehr-restart-[tunnel-name].sh
 ├── sepehr-dummy-[tunnel-name].sh


---

🛠 Technologies Used

Bash

systemd

iproute2

HAProxy

cron

netcat



---

🤝 Contributing

Pull requests, feature ideas, and bug reports are welcome.


---

💰 Support

TRON (TRC20):

TXN5w8E2akLDZEswqcxCjNkJdNQnYRp78H


---

📬 Contact

GitHub: https://github.com/efikhan/Truma-Tunnel

Telegram: @efikhan_jr

Email: efikhanjr@gmail.com



---

📝 License

MIT License


---

Dedicated to the martyrs of the path of freedom

---

