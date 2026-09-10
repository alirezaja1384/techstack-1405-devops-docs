---
title: فرایندها، systemd و journalctl
weight: 5
description: مشاهده و کنترل فرایندها، مدیریت سرویس‌ها با systemd و عیب‌یابی از طریق لاگ‌های journal
---

## فرایند چیست؟

هر برنامهٔ در حال اجرا یک یا چند **فرایند** دارد. هر فرایند شناسه‌ای به نام **PID** دارد و معمولاً از یک فرایند والد ایجاد شده است. هنگام عیب‌یابی، ابتدا باید بدانید چه چیزی اجرا می‌شود، با کدام کاربر اجرا می‌شود و چه مقدار CPU یا حافظه مصرف می‌کند.

```bash
ps aux
ps -ef
pgrep -a sshd
top
```

- `ps aux` نمایی کامل از فرایندهای فعلی می‌دهد.
- `pgrep -a` فرایندهای منطبق با نام را همراه آرگومان‌های اجرای آن‌ها پیدا می‌کند.
- `top` نمای زنده از مصرف منابع است؛ با `q` از آن خارج شوید.

یک دستور طولانی را با `&` در پس‌زمینه اجرا کنید. `jobs` فقط کارهای shell فعلی را نشان می‌دهد؛ `fg` کار را به پیش‌زمینه می‌آورد:

```bash
sleep 300 &
jobs
fg %1
```

## سیگنال‌ها و توقف فرایند

برای درخواست توقف یک فرایند از سیگنال استفاده می‌شود. `SIGTERM` درخواست مودبانه برای پایان کار است و به برنامه فرصت می‌دهد فایل‌ها و اتصال‌ها را ببندد. `SIGKILL` قابل‌مدیریت نیست و فقط باید آخرین راه باشد:

```bash
kill -TERM <pid>
kill -KILL <pid>
```

پیش از ارسال سیگنال، PID و مالک فرایند را بررسی کنید. `kill -9` بدون بررسی می‌تواند داده را خراب کند یا سرویس وابسته را از کار بیندازد. برای سرویس‌های systemd، از `systemctl` استفاده کنید تا مدیر سرویس وضعیت را درست نگه دارد.

## systemd و unitها

در بسیاری از توزیع‌های امروز، **systemd** فرایند آغازین و مدیر سرویس است. systemd رفتار مؤلفه‌های سامانه را در فایل‌هایی به نام **unit** تعریف می‌کند. رایج‌ترین نوع‌ها `service`، `socket`، `timer` و `target` هستند.

برای مشاهده و کنترل یک سرویس، نام unit را کامل بنویسید. نام سرویس SSH بسته به توزیع می‌تواند `ssh.service` یا `sshd.service` باشد:

```bash
sudo systemctl status ssh.service
sudo systemctl start ssh.service
sudo systemctl restart ssh.service
sudo systemctl stop ssh.service
sudo systemctl enable ssh.service
sudo systemctl enable --now ssh.service
sudo systemctl disable ssh.service
```

- `start` و `stop` وضعیت اکنون را تغییر می‌دهند.
- `enable` اجرای سرویس را در راه‌اندازی بعدی فعال می‌کند؛ به‌تنهایی سرویس را همین حالا اجرا نمی‌کند.
- `enable --now` سرویس را برای راه‌اندازی‌های بعدی فعال و هم‌زمان همین حالا اجرا می‌کند.
- `restart` برای اعمال پیکربندی جدید یا بازگرداندن سرویس پس از خطا مفید است، اما پیش از آن اثر وقفهٔ کوتاه را در نظر بگیرید.

فهرست سرویس‌های ناموفق، نقطهٔ شروع خوبی برای بررسی وضعیت سامانه است:

```bash
systemctl --failed
systemctl list-units --type=service --state=running
```

## خواندن لاگ‌ها با journalctl

**journald** رویدادهای systemd، هسته و سرویس‌هایی که به journal می‌نویسند را جمع می‌کند. `journalctl` به جای جست‌وجوی پراکنده در چند فایل لاگ، راهی یکپارچه برای بررسی این رویدادهاست.

```bash
journalctl -u ssh.service
journalctl -u ssh.service -b
journalctl --since "2026-09-04 09:00" --until "2026-09-04 10:00"
journalctl -p warning..alert -b
sudo journalctl -u ssh.service -f
```

- `-u` لاگ یک unit را محدود می‌کند.
- `-b` فقط رویدادهای راه‌اندازی فعلی را نشان می‌دهد؛ `-b -1` راه‌اندازی قبلی است.
- `-p warning..alert` سطح‌های warning و شدیدتر را انتخاب می‌کند.
- `-f` مانند `tail -f` منتظر رویدادهای جدید می‌ماند.

برای عیب‌یابی یک سرویس، این ترتیب ساده را دنبال کنید: `systemctl status` را بخوانید، لاگ همان unit را با `journalctl -u` ببینید، زمان رویداد را محدود کنید، پیکربندی را بررسی کنید و سپس تنها در صورت نیاز سرویس را بازراه‌اندازی کنید.

## منابع یادگیری

**مستندات و مقالات**

- [systemd for Administrators](https://gist.github.com/bcremer/8cdf6900c35dda65f387) — آموزش جامع مفاهیم و کاربردهای systemd
- [۱۰۳.۵ - ایجاد، پایش و پایان‌دادن به فرایندها - کتاب LPIC1 جادی](https://linux1st.com/1035-create-monitor-and-kill-processes.html) — مقالهٔ مرتبط با مدیریت فرایندها و سیگنال‌ها
- [۱۰۸.۲ - لاگ‌های سیستم - کتاب LPIC1 جادی](https://linux1st.com/1082-system-logging.html) — مقالهٔ مرتبط با لاگ‌های سیستمی، rsyslog و journal - بخش journalctl مدنظر است

**ویدیو**

- [الپیک ۱ - ۰۳۳ - ۱۰۳.۵ - مدیریت پروسه‌ها در لینوکس (۳ قسمت) - جادی](https://www.youtube.com/watch?v=PUc24E2PTa8&list=PL7ePwBdxM4nswZ62DvL58yJZ9W4-hOLLB&index=34) — آشنایی با مدیریت processها در Linux
- [ الپیک ۱ - ۰۶۵ - ۱۰۸.۲ - ۳/۳ - لاگ‌های سیستم، بررسی و مدیریت لاگ‌ها با journalctl از systemd](https://www.youtube.com/watch?v=1_wf9O9QHCA&list=PL7ePwBdxM4nswZ62DvL58yJZ9W4-hOLLB&index=65) — آشنایی با مدیریت لا‌گ‌ها با journalctl در لینوکس
- [systemd Explained - Learn Linux TV](https://www.youtube.com/watch?v=Kzpm-rGAXos) — معرفی نقش systemd در مدیریت سرویس‌ها
