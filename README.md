```markdown
# 🚇 Truma Tunnel Manager

<div align="center">
  <img src="https://img.shields.io/badge/version-2.0-blue?style=for-the-badge" alt="ورژن ۲.۰">
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="مجوز MIT">
  <img src="https://img.shields.io/badge/platform-Linux-red?style=for-the-badge" alt="پلتفرم لینوکس">
  <img src="https://img.shields.io/badge/bash-5.0%2B-orange?style=for-the-badge" alt="نسخه Bash">
</div>

<p align="center">
  <b>یک اسکریپت حرفه‌ای و قدرتمند برای مدیریت تونل‌های GRE با قابلیت‌های پیشرفته ضد فیلترینگ</b>
</p>

<p dir="rtl" align="center">
  <i>به راحتی تونل GRE ایجاد کنید و با سیستم سه‌لایه ضد فیلتر، ارتباط خود را پایدار نگه دارید.</i>
</p>

---

## 📥 نصب

### روش خودکار (پیشنهادی)
یک دستور زیر را در ترمینال سرور خود (با دسترسی روت) اجرا کنید:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/install.sh)"
```

روش دستی

```bash
wget https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

---

🚀 آموزش گام‌به‌گام تانل زدن

پس از اجرای install.sh، منوی اصلی نمایش داده می‌شود. گزینه [1] 🚀 Create New Tunnel را انتخاب کنید.

۱. انتخاب سمت سرور

```
1) Iran (with HAProxy)   – سمت ایران (با نصب و تنظیم HAProxy)
2) Kharej (without HAProxy) – سمت خارج (بدون HAProxy)
```

۲. نام تونل

```
Enter tunnel name (letters/numbers only):
```

یک نام دلخواه مثلاً myoffice یا kharej1 وارد کنید (فقط حروف انگلیسی و اعداد).

۳. تأیید IP محلی

```
Detected your local IP: x.x.x.x
Is this correct? [Y/n]:
```

IP شناسایی‌شده را تأیید کنید یا با زدن n آن را دستی وارد کنید.

۴. IP مقصد

```
Enter remote IP:
```

IP عمومی سرور مقابل (طرف دیگر تونل) را وارد کنید.

۵. شبکه پایه

```
Enter base network (must start with 10 and end with 0):
```

شبکه‌ای با فرمت 10.x.y.0 وارد کنید، مانند 10.20.30.0.

۶. MTU (اختیاری)

با زدن y می‌توانید MTU سفارشی (بین ۵۷۶ تا ۱۶۰۰) تنظیم کنید.

۷. پورت‌های فوروارد (فقط در سمت ایران)

```
Forward PORT (e.g., 80,443,2053):
```

پورت‌های مورد نظر را با کاما جدا کنید. مثال: 80,443,8535

---

✨ ویژگی‌های کلیدی

ویژگی توضیح
🚀 ایجاد آسان تونل با چند مرحله ساده تونل GRE خود را در هر دو سمت بسازید.
🛡️ سیستم ضد فیلترینگ سه‌لایه ترکیب بهبود HAProxy، ری‌استارت دوره‌ای و ترافیک ساختگی به Google.
🌐 فوروارد هوشمند پورت با HAProxy تنظیمات پیشرفته برای شبیه‌سازی ترافیک HTTPS.
🔄 ری‌استارت خودکار دوره‌ای جلوگیری از الگوهای پایدار با کرون‌جاب (پیش‌فرض ۱۵ دقیقه).
📊 مدیریت کامل سرویس‌ها فعال، غیرفعال، ری‌استارت و مشاهده وضعیت تونل‌ها.
⚙️ کنترل MTU و شبکه تنظیم دلخواه MTU و شبکه پایه.

---

🧠 توضیح سیستم ضد فیلترینگ

سیستم ضد فیلترینگ ما سه لایه دارد:

1. بهبود HAProxy
      با اضافه کردن پارامترهایی مثل tcp-request inspect-delay و option tcpka، ترافیک تونل شبیه یک وب‌سرور HTTPS واقعی می‌شود.
2. ری‌استارت دوره‌ای تونل
      کرون‌جاب هر ۱۵ دقیقه (قابل تنظیم) سرویس تونل را ری‌استارت می‌کند تا الگوی پایدار ایجاد نشود.
3. ترافیک ساختگی (dummy) به Google
      یک سرویس systemd هر ۳۰ تا ۹۰ ثانیه یک درخواست HTTPS به گوگل ارسال می‌کند. این کار باعث می‌شود پورت سرور ایران همیشه ترافیک عادی داشته باشد و تونل در میان آن گم شود.

این سه لایه با هم، تشخیص توسط سیستم‌های DPI را بسیار دشوار می‌کنند.

---

📂 ساختار فایل‌ها

```
/etc/systemd/system/
 ├── [name].service               # سرویس اصلی تونل GRE
 └── sepehr-dummy-[name].service  # سرویس ترافیک ساختگی

/etc/haproxy/conf.d/
 └── [name].cfg                   # کانفیگ HAProxy مخصوص تونل

/usr/local/bin/
 ├── sepehr-restart-[name].sh     # اسکریپت ری‌استارت
 └── sepehr-dummy-[name].sh       # اسکریپت dummy
```

---

🛠 تکنولوژی‌های استفاده‌شده

· Bash – هسته اصلی اسکریپت
· systemd – مدیریت سرویس‌ها
· iproute2 – ایجاد و مدیریت تونل‌های GRE
· HAProxy – فوروارد پورت با قابلیت‌های پیشرفته
· cron – زمان‌بندی ری‌استارت
· netcat (nc) – ارسال درخواست‌های ساختگی

---

💰 حمایت مالی

اگر این پروژه برای شما مفید بوده و مایل به حمایت هستید:

TRON (TRC20):

```
TXN5w8E2akLDZEswqcxCjNkJdNQnYRp78H
```

---

📬 تماس با ما

· گیت‌هاب: github.com/efikhan/Truma-Tunnel
· تلگرام: @efikhan_jr
· ایمیل: efikhanjr@gmail.com

---

📝 مجوز

این پروژه تحت مجوز MIT منتشر شده است.

---

<p align="center">
  <i>تقدیم به شهدای راه آزادی</i>
</p>
``` 
