```markdown
# 🚇 Truma Tunnel Manager

<div align="center">
  <img src="https://img.shields.io/badge/version-2.0-blue?style=for-the-badge" alt="Version 2.0">
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="MIT License">
  <img src="https://img.shields.io/badge/platform-Linux-red?style=for-the-badge" alt="Platform Linux">
  <img src="https://img.shields.io/badge/bash-5.0%2B-orange?style=for-the-badge" alt="Bash 5.0+">
</div>

<p align="center">
  <b>یک اسکریپت قدرتمند و همه‌کاره برای مدیریت تونل‌های GRE با قابلیت‌های ضد فیلترینگ پیشرفته</b>
</p>

<p align="center">
  <i>An advanced GRE tunnel manager with powerful anti-filtering capabilities</i>
</p>

---

## 📥 روش دانلود و نصب

### روش اول – نصب خودکار با یک خط فرمان (پیشنهادی)
کافیست در ترمینال سرور خود (با دسترسی روت) دستور زیر را وارد کنید:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/[USERNAME]/[REPO]/main/truma.sh)"
```

⚠️ نکته: لینک بالا را با لینک مستقیم فایل خام اسکریپت خود در GitHub جایگزین کنید. برای به‌دست آوردن لینک مستقیم، به مخزن خود بروید، روی فایل truma.sh کلیک کنید، سپس روی دکمه Raw کلیک کرده و آدرس صفحه را کپی کنید.

روش دوم – نصب دستی (دانلود و اجرا)

1. فایل اسکریپت را از GitHub دانلود کنید:
   ```bash
   wget https://raw.githubusercontent.com/[USERNAME]/[REPO]/main/truma.sh
   ```
   یا با curl:
   ```bash
   curl -O https://raw.githubusercontent.com/[USERNAME]/[REPO]/main/truma.sh
   ```
2. مجوز اجرا به فایل بدهید:
   ```bash
   chmod +x truma.sh
   ```
3. اسکریپت را با دسترسی روت اجرا کنید:
   ```bash
   sudo ./truma.sh
   ```

---

🚀 آموزش کامل تانل زدن (گام‌به‌گام)

پس از اجرای اسکریپت با دستور sudo ./truma.sh، منوی اصلی نمایش داده می‌شود. برای ایجاد یک تونل جدید مراحل زیر را دنبال کنید:

مرحله ۱: انتخاب گزینه Create New Tunnel

از منوی اصلی گزینه [1] 🚀 Create New Tunnel را انتخاب کنید.

مرحله ۲: انتخاب سمت (Side)

اسکریپت از شما می‌پرسد که این سرور در کدام سمت قرار دارد:

```
Select side:
1) Iran (with HAProxy)
2) Kharej (without HAProxy)
```

· اگر سرور شما در ایران است (یعنی قرار است ترافیک را دریافت و فوروارد کند)، گزینه 1 را وارد کنید. (HAProxy روی این سرور پیکربندی می‌شود)
· اگر سرور شما در خارج است (سمت دیگر تونل)، گزینه 2 را وارد کنید. (فقط تونل GRE ساخته می‌شود و HAProxy پیکربندی نمی‌گردد)

مرحله ۳: وارد کردن نام تونل

```
Enter tunnel name (letters/numbers only, e.g., mytunnel):
```

یک نام دلخواه برای تونل وارد کنید. فقط حروف انگلیسی، اعداد و زیرخط (_) مجاز است. مثال: myoffice یا tunnel1.

مرحله ۴: تأیید IP محلی

اسکریپت به طور خودکار IP عمومی سرور شما را شناسایی کرده و نمایش می‌دهد:

```
Detected your local IP: 192.168.1.100
Is this correct? [Y/n]:
```

· اگر IP صحیح است، کلید Y (یا فقط Enter) را بزنید.
· اگر اشتباه است، کلید n را بزنید تا بتوانید IP را به صورت دستی وارد کنید.

مرحله ۵: وارد کردن IP مقصد (Remote IP)

```
Enter remote IP (the other server):
```

IP عمومی سرور مقابل (طرف دیگر تونل) را وارد کنید.

مرحله ۶: وارد کردن شبکه پایه (Base Network)

```
Enter base network (e.g., 10.20.30.0) [must start with 10 and end with 0]:
```

یک شبکه با فرمت 10.x.y.0 وارد کنید. شرط: اولین اکتت باید 10 و آخرین اکتت 0 باشد. مثال‌های مجاز:

· 10.10.10.0
· 10.20.30.0
· 10.5.100.0

مرحله ۷: تنظیم MTU (اختیاری)

```
Set custom MTU? (y/n):
```

· اگر y بزنید، مقدار MTU (بین ۵۷۶ تا ۱۶۰۰) را وارد می‌کنید.
· اگر n بزنید (یا Enter)، از MTU پیش‌فرض استفاده می‌شود.

مرحله ۸: وارد کردن پورت‌های فوروارد (فقط در سمت ایران)

اگر در مرحله ۲ گزینه ایران را انتخاب کرده باشید، اکنون از شما پرسیده می‌شود:

```
Forward PORT (e.g., 80,443,2053):
```

پورت‌هایی را که می‌خواهید از طریق تونل فوروارد شوند، با کاما جدا کنید. مثال:

· 80
· 80,443,8080
· 2050,2051,2052

مرحله ۹: نصب بسته‌های مورد نیاز (در صورت لزوم)

اگر بسته‌های iproute2 یا haproxy روی سرور نصب نباشند، اسکریپت به‌طور خودکار آن‌ها را نصب می‌کند. (در سمت خرج فقط iproute2 نصب می‌شود.)

مرحله ۱۰: اتمام و مشاهده خلاصه

پس از اتمام، خلاصه‌ای از تنظیمات اعمال‌شده نمایش داده می‌شود و وضعیت سرویس تونل نشان داده می‌شود. برای مثال:

```
Tunnel 'mytunnel' created (Iran side).
Tunnel IPs:
  Local tunnel IP : 10.20.30.1/30
  Peer tunnel IP  : 10.20.30.2
HAProxy forwards ports: 80 443 8080

Status:
● mytunnel.service - GRE Tunnel mytunnel to (203.0.113.5)
   Loaded: loaded (/etc/systemd/system/mytunnel.service; enabled; vendor preset: enabled)
   Active: active (exited) since ...
```

---

✨ ویژگی‌های اصلی

ویژگی توضیح
🚀 ایجاد تونل GRE ایجاد آسان تونل در دو سمت ایران (میزبان) و خارج (مهمان)
🔄 ری‌استارت خودکار کرون‌جاب هوشمند برای ری‌استارت دوره‌ای تونل (پیش‌فرض ۱۵ دقیقه)
🛡️ سیستم ضد فیلترینگ سه‌لایه شبیه‌سازی ترافیک HTTPS + ری‌استارت دوره‌ای + ترافیک ساختگی به Google
🌐 HAProxy پیشرفته کانفیگ خودکار HAProxy با تنظیمات HTTPS-like برای دور زدن فیلترینگ
📦 مدیریت پورت افزودن یا حذف پورت‌های فوروارد شده به تونل
🔧 تنظیم MTU تغییر MTU تونل برای بهینه‌سازی performance
📊 مدیریت سرویس‌ها مشاهده وضعیت، ری‌استارت، توقف و فعال‌سازی تونل‌ها
⚙️ تنظیمات پیشرفته انتخاب منطقه زمانی، تشخیص خودکار IP محلی، شبکه پایه دلخواه

---

🧠 توضیح سیستم ضد فیلترینگ

این سیستم از سه لایه برای پنهان‌سازی تونل GRE استفاده می‌کند:

لایه توضیح
۱. بهبود HAProxy تنظیمات پیشرفته مثل tcp-request inspect-delay و option tcpka برای شبیه‌سازی ترافیک HTTPS
۲. ری‌استارت دوره‌ای کرون‌جاب با بازه قابل تنظیم برای ری‌استارت تونل و شکستن الگوی پایدار
۳. ترافیک ساختگی سرویس systemd که هر ۳۰-۹۰ ثانیه یک درخواست HTTPS به Google ارسال می‌کند تا ترافیک تونل در میان ترافیک عادی گم شود

---

📊 ساختار فایل‌ها

```
/etc/systemd/system/
├── [name].service              # سرویس تونل GRE
└── sepehr-dummy-[name].service  # سرویس dummy traffic

/etc/haproxy/conf.d/
└── [name].cfg                  # کانفیگ HAProxy مخصوص تونل

/usr/local/bin/
├── sepehr-restart-[name].sh     # اسکریپت ری‌استارت
└── sepehr-dummy-[name].sh       # اسکریپت dummy traffic
```

---

🛠️ تکنولوژی‌های استفاده‌شده

· Bash – هسته اصلی اسکریپت
· systemd – مدیریت سرویس‌ها
· iproute2 – ایجاد و مدیریت تونل‌های GRE
· HAProxy – فوروارد پورت‌ها با قابلیت‌های پیشرفته
· cron – زمان‌بندی ری‌استارت دوره‌ای
· netcat (nc) – ارسال درخواست‌های ساختگی

---

🤝 مشارکت

از مشارکت شما عزیزان استقبال می‌شود! لطفاً:

1. مخزن را Fork کنید.
2. تغییرات خود را اعمال کنید.
3. Pull Request بفرستید.

همچنین می‌توانید:

· 🐛 باگ‌ها را گزارش دهید.
· 💡 ایده‌های جدید پیشنهاد دهید.
· 📖 مستندات را بهبود بخشید.

---

💰 حمایت مالی

اگر این پروژه برای شما مفید بوده و مایل به حمایت مالی هستید، می‌توانید از طریق آدرس‌های زیر اقدام کنید:

TRON (TRX) - TRC20

```
TXN5w8E2akLDZEswqcxCjNkJdNQnYRp78H
```

حمایت‌های شما به ادامه توسعه و بهبود این پروژه کمک می‌کند. 🙏

---

📝 مجوز

این پروژه تحت مجوز MIT منتشر شده است. برای اطلاعات بیشتر فایل LICENSE را ببینید.

---

📬 تماس با ما

· ایمیل: [efikhanjr@gmail.com]
· تلگرام: [@efikhan_jr]
· گیت‌هاب: github.com/efikhan

---

<div align="center">
  <sub>ساخته شده با ❤️ برای جامعه متن‌باز ایران</sub>
  <br>
  <sub>Made with ❤️ for the open-source community</sub>
</div>
```
