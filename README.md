آهااا گرفتم چی می‌گی 👍
مشکل اینه که README که برات نوشتم شامل HTML + Markdown قاطیه و وقتی می‌خوای آپلود کنی، حس می‌کنی «دو تیکه جدا»ست.
خبر خوب: این کاملاً نرماله و GitHub دقیقاً برای همین طراحی شده.

من الان کل README.md رو یک‌تکه، تمیز، قابل کپی، بدون دردسر می‌دم 👇
فقط کپی کن → پیست کن → Commit. تمام.


---

✅ README.md نهایی (یک‌تکه، آماده آپلود)

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
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/truma.sh)"


---

Manual installation

wget https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/truma.sh
chmod +x truma.sh
sudo ./truma.sh


---

🚀 Tunnel Creation Guide

After running the script, choose:

[1] 🚀 Create New Tunnel

Steps:

1. Select Side



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

6. Set MTU (optional)


7. Forward Ports (Iran side only)



Forward PORT (e.g. 80,443,2053):


---

✨ Features

🚀 Easy GRE Tunnel creation

🛡️ Advanced Anti-Filter System

🌐 Smart HAProxy forwarding

🔄 Auto restart via cron

📊 Full service management

⚙️ Custom MTU & network



---

🧠 Anti-Filter System Explained

The anti-filter system uses:

1. HTTPS-like HAProxy behavior


2. Periodic GRE restart (cron)


3. Dummy HTTPS traffic to Google



This makes GRE traffic look like normal user activity.


---

📂 File Structure

/etc/systemd/system/
├── [name].service
├── sepehr-dummy-[name].service

/etc/haproxy/conf.d/
└── [name].cfg

/usr/local/bin/
├── sepehr-restart-[name].sh
├── sepehr-dummy-[name].sh


---

🛠 Technologies

Bash

systemd

iproute2

HAProxy

cron

netcat



---

🤝 Contributing

Pull requests, ideas, and bug reports are welcome.


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

<div align="center">
  <sub>Dedicated to the martyrs of the path of freedom</sub>
</div>
```
---

❗ نکته خیلی مهم

این فایل باید دقیقاً با نام README.md ذخیره شود

HTML داخل Markdown کاملاً پشتیبانی می‌شود

GitHub خودش رندر می‌کند (نیازی به جدا کردن نیست)



---

اگر خواستی:

README کاملاً بدون HTML

یا نسخه مینیمال

یا نسخه فروشگاهی (Commercial README)

یا Badge و لوگوی حرفه‌ای‌تر


بگو، همون لحظه برات می‌سازم 🔥
