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

### روش دستی

```bash
wget https://raw.githubusercontent.com/efikhan/Truma-Tunnel/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

---

## 🚀 آموزش گام‌به‌گام تانل زدن

پس از اجرای `install.sh`، منوی اصلی نمایش داده می‌شود.  
گزینه **[1] 🚀 Create New Tunnel** را انتخاب کنید.

### ۱. انتخاب سمت سرور

```text
1) Iran (with HAProxy)        – سمت ایران (با نصب و تنظیم HAProxy)
2) Kharej (without HAProxy)  – سمت خارج (بدون HAProxy)
```

### ۲. نام تونل

```text
Enter tunnel name (letters/numbers only):
```

یک نام دلخواه مثل `myoffice` یا `kharej1` وارد کنید  
(فقط حروف انگلیسی و اعداد).

### ۳. تأیید IP محلی

```text
Detected your local IP: x.x.x.x
Is this correct? [Y/n]:
```

IP شناسایی‌شده را تأیید کنید یا با زدن `y` آن را دستی وارد کنید.

### ۴. IP مقصد

```text
Enter remote IP:
```

IP عمومی سرور مقابل (سمت دیگر تونل) را وارد کنید.

### ۵. آیپی لوکال (Base Network)

```text
Enter base network (must start with 10 and end with 0):
```

شبکه‌ای با فرمت `10.x.y.0` وارد کنید، مثال:

```text
10.20.30.0
```

### ۶. MTU (اختیاری)

در صورت تمایل می‌توانید MTU سفارشی بین **576 تا 1600** تنظیم کنید.

### ۷. پورت‌های فوروارد (فقط سمت ایران)

```text
Forward PORT (e.g., 80,443,2053):
```

پورت‌ها را با کاما جدا کنید، مثال:

```text
80,443,8535
```

---

## ✨ ویژگی‌های کلیدی

| ویژگی | توضیح |
|-----|------|
| 🚀 ایجاد آسان تونل | ساخت تونل GRE در هر دو سمت با چند مرحله ساده |
| 🛡️ ضد فیلترینگ سه‌لایه | HAProxy + ری‌استارت دوره‌ای + ترافیک ساختگی |
| 🌐 فوروارد هوشمند پورت | شبیه‌سازی ترافیک HTTPS واقعی |
| 🔄 ری‌استارت خودکار | کرون‌جاب پیش‌فرض هر ۱۵ دقیقه (قابل تنظیم) |
| 📊 مدیریت کامل | start / stop / restart / status |
| ⚙️ کنترل MTU و شبکه | تنظیم دلخواه MTU و base network |

---

## 🧠 توضیح سیستم ضد فیلترینگ

سیستم ضد فیلترینگ شامل **سه لایه مستقل** است:

### 1️⃣ بهبود HAProxy
با پارامترهایی مثل:

- `tcp-request inspect-delay`
- `option tcpka`

ترافیک تونل شبیه وب‌سرور HTTPS واقعی می‌شود.

### 2️⃣ ری‌استارت دوره‌ای تونل
یک cron job (پیش‌فرض هر ۱۵ دقیقه) تونل را ری‌استارت می‌کند  
تا الگوی پایدار برای DPI ایجاد نشود.

### 3️⃣ ترافیک ساختگی (Dummy)
یک سرویس `systemd` هر **۳۰ تا ۹۰ ثانیه** یک درخواست HTTPS به Google می‌فرستد  
تا پورت ایران همیشه ترافیک نرمال داشته باشد.

✅ ترکیب این سه لایه، شناسایی تونل توسط DPI را بسیار دشوار می‌کند.

---

## 📂 ساختار فایل‌ها

```text
/etc/systemd/system/
 ├── [name].service
 └── sepehr-dummy-[name].service

/etc/haproxy/conf.d/
 └── [name].cfg

/usr/local/bin/
 ├── sepehr-restart-[name].sh
 └── sepehr-dummy-[name].sh
```

---

## 🛠 تکنولوژی‌های استفاده‌شده

- **Bash** – هسته اصلی اسکریپت
- **systemd** – مدیریت سرویس‌ها
- **iproute2** – تونل GRE
- **HAProxy** – فوروارد پورت لایه ۴
- **cron** – ری‌استارت زمان‌بندی‌شده
- **netcat (nc)** – ترافیک ساختگی

---

## 💰 حمایت مالی

**TRON (TRC20):**

```text
TXN5w8E2akLDZEswqcxCjNkJdNQnYRp78H
```

---

## 📬 تماس با ما

- GitHub: https://github.com/efikhan/Truma-Tunnel
- Telegram: @efikhan_jr
- Email: efikhanjr@gmail.com

---

## 📝 مجوز

این پروژه تحت مجوز **MIT** منتشر شده است.

---

<p align="center">
  <i>تقدیم به شهدای راه آزادی</i>
</p>
```
