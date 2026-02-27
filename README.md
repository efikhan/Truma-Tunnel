Truma Tunnel Manager 🚀

https://img.shields.io/badge/License-MIT-yellow.svg
https://img.shields.io/badge/language-bash-green.svg

Truma Tunnel Manager is a professional, menu‑driven Bash script suite designed to simplify the creation, management, and monitoring of various tunneling protocols on Linux servers. It provides an all‑in‑one interface for GRE, KCP (via Paqet), and EMC (EasyTier Mesh) tunnels, with integrated HAProxy‑based port forwarding and automatic restart scheduling.

---

📖 Overview

Managing multiple tunnel types manually can be tedious and error‑prone. Truma automates the entire lifecycle:

· Create tunnels with guided interactive prompts.
· Manage services (start/stop/restart/status) from a unified menu.
· Forward ports using HAProxy (for GRE/EMC) or built‑in forwarding (for Paqet).
· Schedule auto‑restart with cron.
· Cleanly uninstall tunnels, removing all associated files and rules.

Truma is modular and extensible – new protocols can be added by dropping in a new manager script following the defined interface.

---

✨ Features

· ✅ Interactive Menu – Easy navigation with color‑coded logs.
· ✅ GRE Tunnels – Full support with key, MTU, and IP configuration.
· ✅ KCP Tunnels – Powered by Paqet, with configurable modes (fast, fast2, normal, manual).
· ✅ EMC (EasyTier Mesh) Tunnels – Decentralised mesh networking with encryption.
· ✅ Port Forwarding – Centralised HAProxy manager for GRE/EMC; Paqet has native TCP forwarding.
· ✅ Auto‑Restart – Set per‑tunnel cron jobs for automatic restart at chosen intervals.
· ✅ MTU Adjustment – Change MTU on the fly (where supported).
· ✅ Comprehensive Logging – All actions logged and displayed in‑menu.
· ✅ Non‑Interactive Mode – Suitable for automated deployment (NONINTERACTIVE=1).
· ✅ Clean Uninstall – Removes service files, configs, cron jobs, and HAProxy rules.

---

🛠️ Installation

You can install Truma with a single command.

Note: If you encounter $'\r': command not found errors, use the command below – it automatically removes Windows‑style carriage returns.

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/install.sh
sed -i 's/\r$//' install.sh
sudo bash install.sh
```

The installer will:

1. Ask for your server location (Inside Iran / Kharj).
2. Apply Iran‑specific optimizations if you choose "Inside Iran" (IPv6 disable, best DNS/mirror selection, kernel tuning).
3. Clone the repository into /opt/truma.
4. Launch the Truma main menu.

---

🚦 Usage

After installation, Truma starts automatically. If you need to run it again later:

```bash
cd /opt/truma
sudo ./truma.sh
```

Main Menu Options

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

مدیر تانل تروما 🇮🇷

https://img.shields.io/badge/License-MIT-yellow.svg

تروما (Truma) یک مجموعه اسکریپت Bash حرفه‌ای و منو‑محور است که مدیریت پروتکل‌های مختلف تانل روی سرورهای لینوکس را ساده می‌کند. این ابزار با یک رابط یکپارچه، امکان ساخت، مدیریت و نظارت بر تانل‌های GRE، KCP (با موتور Paqet) و EMC (مش EasyTier) را فراهم کرده و با HAProxy فوروارد پورت را انجام می‌دهد.

---

📖 معرفی

مدیریت دستی چند نوع تانل می‌تواند خسته‌کننده و خطا‌خیز باشد. تروما تمام چرخهٔ عمر تانل را خودکار می‌کند:

· ساخت تانل با راهنمایی تعاملی.
· مدیریت سرویس‌ها (شروع/توقف/ری‌استارت/وضعیت) از یک منوی واحد.
· فوروارد پورت با HAProxy (برای GRE/EMC) یا فوروارد داخلی (برای Paqet).
· تنظیم ری‌استارت خودکار با کرون.
· پاکسازی کامل تانل با حذف تمام فایل‌ها و قوانین مرتبط.

تروما ماژولار و قابل گسترش است – پروتکل‌های جدید را می‌توان با افزودن یک اسکریپت مدیر جدید و پیروی از رابط تعریف‌شده اضافه کرد.

---

✨ ویژگی‌ها

· ✅ منوی تعاملی – پیمایش آسان با لاگ‌های رنگی.
· ✅ تانل GRE – پشتیبانی کامل با کلید، MTU و تنظیم IP.
· ✅ تانل KCP – مبتنی بر Paqet، با حالت‌های قابل تنظیم (fast، fast2، normal، manual).
· ✅ تانل EMC (مش EasyTier) – شبکه‌های مش غیرمتمرکز با رمزنگاری.
· ✅ فوروارد پورت – مدیریت متمرکز HAProxy برای GRE/EMC؛ Paqet فوروارد TCP بومی دارد.
· ✅ ری‌استارت خودکار – تنظیم کرون برای هر تانل با بازه‌های دلخواه.
· ✅ تغییر MTU – تغییر MTU در لحظه (در صورت پشتیبانی).
· ✅ لاگ‌گیری جامع – ثبت تمام اقدامات و نمایش در منو.
· ✅ حالت غیرتعاملی – مناسب برای نصب خودکار (NONINTERACTIVE=1).
· ✅ پاکسازی کامل – حذف فایل‌های سرویس، کانفیگ، کرون و قوانین HAProxy.

---

🛠️ نصب

با یک دستور می‌توانید تروما را نصب کنید.

توجه: اگر با خطای $'\r': command not found مواجه شدید، از دستور زیر استفاده کنید – این دستور به‌طور خودکار کاراکترهای بازگشت به ابتدای خط (CR) را حذف می‌کند.

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/install.sh
sed -i 's/\r$//' install.sh
sudo bash install.sh
```

نصب‌کننده:

1. موقعیت سرور را می‌پرسد (Inside Iran / Kharj).
2. اگر گزینه «Inside Iran» را انتخاب کنید، بهینه‌سازی‌های مخصوص ایران اعمال می‌شود (غیرفعال‌سازی IPv6، انتخاب بهترین DNS و mirror، تنظیمات هسته).
3. مخزن را در /opt/truma کلون می‌کند.
4. منوی اصلی تروما را اجرا می‌کند.

---

🚦 نحوه استفاده

پس از نصب، تروما به‌طور خودکار شروع می‌شود. اگر بعداً نیاز به اجرای مجدد داشتید:

```bash
cd /opt/truma
sudo ./truma.sh
```

گزینه‌های منوی اصلی

گزینه توضیحات
1 – ساخت تانل جدید انتخاب GRE، KCP یا EMC و پیروی از راهنما.
`2 – نمایش تانل‌های فعال فهرست تانل‌های موجود و مدیریت آن‌ها (شروع/توقف/ری‌استارت/وضعیت/ری‌استارت خودکار/تغییر حالت).
`3 – پاکسازی تانل حذف کامل یک تانل و تمام فایل‌ها و قوانین مرتبط.
`4 – مدیریت پورت افزودن/فهرست/حذف قوانین HAProxy، بارگذاری مجدد HAProxy یا حذف همه قوانین.
`5 – سیستم ضد فیلتر (محل نگه‌داری) ویژگی‌های آتی برای دور زدن فیلترینگ.
`6 – تغییر MTU تغییر MTU یک تانل موجود.
`0 – خروج ترک تروما.

---

🔌 تانل‌های پشتیبانی‌شده

۱. GRE (Generic Routing Encapsulation)

· تانل‌های نقطه‌به‌نقطه ساده.
· قابل تنظیم با کلید، IP محلی/راه‌دور و MTU.
· فوروارد پورت داخلی ندارد – از HAProxy استفاده کنید.

۲. KCP (Paqet)

· پروتکل سریع و کم‌تأخیر مبتنی بر UDP.
· حالت‌ها: fast، fast2 (پیشنهادی)، fast3، normal، manual.
· فوروارد پورت TCP بومی (برای سمت کلاینت).
· تولید خودکار کلید رمزنگاری.

۳. EMC (مش EasyTier)

· شبکه خصوصی مش غیرمتمرکز.
· پشتیبانی از TCP، UDP، WS، WSS.
· رمزنگاری داخلی، چندنخی، فعال/غیرفعال‌سازی IPv6.
· کشف همسایه و مسیریابی.

---

🔧 مدیریت پورت

· برای تانل‌های GRE و EMC، فوروارد پورت توسط HAProxy انجام می‌شود.
  · قوانین به‌صورت فایل‌های جداگانه در /etc/haproxy/conf.d/ ذخیره می‌شوند.
  · از منوی «مدیریت پورت» برای افزودن/حذف قوانین استفاده کنید.
  · هر قانون شامل توضیحی با نام تانل برای شناسایی آسان است.
· برای Paqet (در سمت کلاینت)، فوروارد پورت مستقیماً در فایل YAML پیکربندی می‌شود. از گزینه‌های مخصوص Paqet در منوی سرویس استفاده کنید.

---

⏰ ری‌استارت خودکار با کرون

از منوی سرویس می‌توانید برای یک تانل ری‌استارت خودکار با بازه‌های منظم تنظیم کنید:

· دقیقه: */5 * * * *
· ساعت: 0 */1 * * *

کرون‌جاب هنگام پاکسازی تانل به‌طور خودکار حذف می‌شود.

---

🗑️ پاکسازی

برای حذف کامل یک تانل:

1. به منوی اصلی رفته و گزینه 3 – Uninstall Tunnel را انتخاب کنید.
2. تانل مورد نظر را انتخاب کرده و با تایپ yes تأیید کنید.
3. تمام فایل‌های مرتبط (سرویس systemd، کانفیگ، اسکریپت فایروال، کرون‌جاب، قوانین HAProxy) حذف می‌شوند.

اگر می‌خواهید خود تروما را پاک کنید، کافیست پوشه /opt/truma و هر قانون HAProxy که اضافه کرده‌اید را حذف نمایید. نصب‌کننده فایل‌های سیستمی فراتر از موارد ذکر شده را تغییر نمی‌دهد.

---

🙏 قدردانی

· عارف هادی‌نژاد – به خاطر مشارکت ارزشمندش در پروژه تانل GRE که پایه‌ای برای این کار بود.
· توسعه‌دهندگان EasyTier و Paqet برای موتورهای تانل فوق‌العاده‌شان.
· Musixal برای الهام از پروژه Easy-Mesh.

❤️ حمایت از پروژه

اگر تروما را مفید می‌دانید، می‌توانید از توسعه آن حمایت کنید:

آدرس TRX (TRC20):
TXN5w8E2akLDZEswqcxCjNkJdNQnYRp78H

---

📄 License / مجوز

This project is licensed under the MIT License – see the LICENSE file for details.
این پروژه تحت مجوز MIT منتشر شده است – برای جزئیات بیشتر فایل LICENSE را ببینید.

---

📬 Contact / ارتباط

· GitHub Repository / مخزن گیت‌هاب: https://github.com/efikhan/Truma-Tunnel
· Telegram Channel / کانال تلگرام: @TrumaTunnel (example)
· Issues / گزارش مشکلات: GitHub Issues
