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

پس از اجرای install.sh، منوی اصلی نمایش داده می‌شود.  
گزینه **[1] 🚀 Create New Tunnel** را انتخاب کنید.

### ۱. انتخاب سمت سرور
```
1) Iran (with HAProxy)        – سمت ایران (با نصب و تنظیم HAProxy)
2) Kharej (without HAProxy)  – سمت خارج (بدون HAProxy)
```

### ۲. نام تونل
```
Enter tunnel name (letters/numbers only):
```

### ۳. تأیید IP محلی
```
Detected your local IP: x.x.x.x
Is this correct? [Y/n]:
```

### ۴. IP مقصد
```
Enter remote IP:
```

### ۵. شبکه پایه
```
Enter base network (must start with 10 and end with 0):
```

### ۶. MTU (اختیاری)
امکان تنظیم MTU سفارشی بین **576 تا 1600**

### ۷. فوروارد پورت (فقط سمت ایران)
```
Forward PORT (e.g., 80,443,2053):
```

---

## ✨ ویژگی‌های کلیدی

| ویژگی | توضیح |
|-----|------|
| 🚀 ایجاد آسان تونل | ساخت GRE در چند مرحله |
| 🛡️ ضد فیلترینگ سه‌لایه | HAProxy + Restart + Dummy Traffic |
| 🌐 فوروارد هوشمند | شبیه‌سازی HTTPS واقعی |
| 🔄 ری‌استارت خودکار | Cron job دوره‌ای |
| 📊 مدیریت کامل | start / stop / restart / status |
| ⚙️ MTU و Network | قابل تنظیم |

---

## 🧠 سیستم ضد فیلترینگ

1. **بهینه‌سازی HAProxy**  
   شبیه‌سازی ترافیک HTTPS واقعی

2. **ری‌استارت دوره‌ای تونل**  
   جلوگیری از الگوی پایدار DPI

3. **Dummy Traffic به Google**  
   حفظ ترافیک نرمال روی پورت

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

## 🛠 تکنولوژی‌ها

- Bash
- systemd
- iproute2
- HAProxy
- cron
- netcat

---

## 💰 حمایت مالی

**TRON (TRC20):**
```
TXN5w8E2akLDZEswqcxCjNkJdNQnYRp78H
```

---

## 📬 تماس

- GitHub: https://github.com/efikhan/Truma-Tunnel  
- Telegram: @efikhan_jr  
- Email: efikhanjr@gmail.com  

---

## 📝 مجوز

MIT License

---

<p align="center">
  <i>تقدیم به شهدای راه آزادی</i>
</p>
```
