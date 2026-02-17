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

## ✨ ویژگی‌های اصلی

| ویژگی | توضیح |
|-------|-------|
| 🚀 **ایجاد تونل GRE** | ایجاد آسان تونل در دو سمت ایران (میزبان) و خارج (مهمان) |
| 🔄 **ری‌استارت خودکار** | کرون‌جاب هوشمند برای ری‌استارت دوره‌ای تونل (پیش‌فرض ۱۵ دقیقه) |
| 🛡️ **سیستم ضد فیلترینگ سه‌لایه** | شبیه‌سازی ترافیک HTTPS + ری‌استارت دوره‌ای + ترافیک ساختگی به Google |
| 🌐 **HAProxy پیشرفته** | کانفیگ خودکار HAProxy با تنظیمات HTTPS-like برای دور زدن فیلترینگ |
| 📦 **مدیریت پورت** | افزودن یا حذف پورت‌های فوروارد شده به تونل |
| 🔧 **تنظیم MTU** | تغییر MTU تونل برای بهینه‌سازی performance |
| 📊 **مدیریت سرویس‌ها** | مشاهده وضعیت، ری‌استارت، توقف و فعال‌سازی تونل‌ها |
| ⚙️ **تنظیمات پیشرفته** | انتخاب منطقه زمانی، تشخیص خودکار IP محلی، شبکه پایه دلخواه |

---

## 🖥️ پیش‌نمایش منو

```bash
[1] 🚀 Create New Tunnel
[2] 🔍 Show Active Tunnels
[3] ⚙️ Settings
[4] 🧹 Uninstall Tunnel
[5] ➕ Add Port to Tunnel
[6] 🛡️ Anti-Filter System
[7] 📦 Change MTU
[0] ❌ Exit
