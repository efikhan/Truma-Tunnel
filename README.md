---

# 🚇 Truma Tunnel Manager

<div align="center">
  <img src="https://img.shields.io/badge/version-2.0-pink?style=for-the-badge" alt="Version 2.0">
  <img src="https://img.shields.io/badge/platform-Linux-lightgrey?style=for-the-badge" alt="Platform Linux">
  <img src="https://img.shields.io/badge/bash-5.0%2B-ff69b4?style=for-the-badge" alt="Bash 5.0+">
</div>

<p align="center">
  <b>An advanced GRE tunnel manager with anti-filtering capabilities</b>
</p>

<p align="center">
  <i>Simple • Clean • Powerful</i>
</p>

---

## 📥 Installation

### Method 1 – One-line install (Recommended)

Run the following command on your server (root required):

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/truma.sh)"

> Replace the link if your script filename is different.




---

Method 2 – Manual install

wget https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/truma.sh
chmod +x truma.sh
sudo ./truma.sh


---

🚀 Full Tunnel Setup Guide (Step by Step)

Step 1: Create New Tunnel

From the main menu select:

[1] 🚀 Create New Tunnel


---

Step 2: Select Side

Select side:
1) Iran (with HAProxy)
2) Kharej (without HAProxy)

Iran → HAProxy + port forwarding

Kharej → GRE tunnel only



---

Step 3: Tunnel Name

Enter tunnel name (letters/numbers only):

Examples:

office1

truma01

mytunnel



---

Step 4: Local IP Detection

Detected your local IP: X.X.X.X
Is this correct? [Y/n]:

Press Enter / Y to confirm

Press n to enter manually



---

Step 5: Remote IP

Enter remote IP:

Enter the public IP of the other server.


---

Step 6: Base Network

Enter base network (must start with 10 and end with 0):

Valid examples:

10.10.10.0

10.20.30.0

10.5.100.0



---

Step 7: MTU (Optional)

Set custom MTU? (y/n):

Default MTU is used if skipped.



---

Step 8: Forward Ports (Iran side only)

Forward PORT (e.g. 80,443,2053):

Single port: 443

Multiple ports: 80,443,8080



---

Step 9: Auto Dependency Install

The script automatically installs:

iproute2

haproxy (Iran side only)



---

Step 10: Done 🎉

You will see a full summary:

Tunnel created successfully
Local tunnel IP : 10.x.x.1/30
Peer tunnel IP  : 10.x.x.2
Forwarded ports : 80 443 8080


---

✨ Features

Feature	Description

🚀 GRE Tunnel	Easy GRE tunnel creation
🛡️ Anti-Filter System	Traffic obfuscation + dummy HTTPS traffic
🔄 Auto Restart	Periodic tunnel restart
🌐 HAProxy	HTTPS-like forwarding
🔧 MTU Control	Performance tuning
📊 Service Manager	Start / Stop / Restart
⚙️ Auto IP Detect	Smart local IP detection



---

🧠 Anti-Filter System Explained

The anti-filter mechanism works in three layers:

1. HAProxy Optimization
Traffic is forwarded through the GRE tunnel peer IP to ensure all data passes inside the tunnel.


2. Periodic Restart
Cron-based tunnel restart breaks static traffic patterns.


3. Dummy HTTPS Traffic
A systemd service sends HTTPS requests at random intervals to simulate real user activity.



> Note: Dummy traffic destination can be changed if Google is not reachable.




---

📊 File Structure

/etc/systemd/system/
├── [name].service
├── sepehr-dummy-[name].service

/etc/haproxy/conf.d/
└── [name].cfg

/usr/local/bin/
├── sepehr-restart-[name].sh
└── sepehr-dummy-[name].sh


---

🛠️ Technologies Used

Bash

systemd

iproute2

HAProxy

cron

netcat (nc)



---

🤝 Contribution

Contributions are welcome!

1. Fork the repository


2. Make changes


3. Submit a Pull Request



You can also:

Report bugs 🐛

Suggest features 💡

Improve documentation 📖



---

💰 Support the Project

If this project helps you, you can support development:

TRON (TRC20)

TXN5w8E2akLDZEswqcxCjNkJdNQnYRp78H


---

📬 Contact

GitHub: https://github.com/efikhan/Truma-Tunnel.git

Telegram: @efikhan_jr

Email: efikhanjr@gmail.com



---

<div align="center">
  <sub>Dedicated to the martyrs of the path of freedom</sub>
  <br>
  <sub>تقدیم به شهدای راه آزادی</sub>
</div>
```
---

