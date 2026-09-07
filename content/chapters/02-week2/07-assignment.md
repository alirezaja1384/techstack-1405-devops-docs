---
title: تمرین هفته ۲
weight: 7
description: ساخت یک گزارش‌گیر سبک Linux با Bash، systemd timer، jq و logrotate
---

در این تمرین یک گزارش‌گیر کوچک برای وضعیت سرور می‌سازید. خروجی نهایی یک اسکریپت Bash است که با کاربر سرویس اجرا می‌شود، در بازه‌های زمانی مشخص گزارش می‌نویسد و لاگ‌هایش با `logrotate` مدیریت می‌شوند.

پیش از شروع، درس‌های هفته را مرور کنید؛ به‌ویژه [Pipe و Redirection](03-pipes-redirection-search-text-processing.md)، [systemd و journalctl](05-processes-systemd-journalctl.md) و [Bash و خودکارسازی](06-bash-scripting-automation.md). همه‌ی دستورهای دارای `sudo` را پیش از اجرا بخوانید و مسیرها را با سامانه‌ی خودتان تطبیق دهید.

## گام ۱ — پردازش متن و Redirection

یک دایرکتوری آزمایشی بسازید و فایل لاگ زیر را در آن قرار دهید:

```bash
mkdir -p ~/week-2-lab

cat > ~/week-2-lab/access.log <<'EOF'
10.20.0.4 GET / 200
10.20.0.8 GET /health 200
10.20.0.4 GET /login 401
10.20.0.4 ERROR database timeout
10.20.0.8 GET / 200
10.20.0.12 ERROR upstream unavailable
EOF
```

پاسخ این پرسش‌ها را با کامندهای کوچک و `pipeline` بنویسید و دستور و خروجی را در `01-text-processing.md` تحویل ثبت کنید:

1. چند کاربر در `/etc/passwd` shellی برابر با `nologin` دارند؟ از `cut`، `grep` و `wc` استفاده کنید.
2. نام shellها در `/etc/passwd` را همراه با تعداد هرکدام، به‌ترتیب نزولی نمایش دهید.
3. IPهای پرتکرار در `access.log` را با `awk`، `sort` و `uniq -c` پیدا کنید.
4. تعداد خط‌های دارای `ERROR` را با `grep` به دست آورید.

سپس تفاوت `stdout` و `stderr` را آزمایش کنید. یکی از مسیرها در دستور زیر وجود ندارد؛ خروجی عادی و خطا را در دو فایل جدا ذخیره و محتوای هر دو را بررسی کنید:

```bash
ls /etc/hostname /path/that-does-not-exist > ~/week-2-lab/stdout.txt 2> ~/week-2-lab/stderr.txt
```

کد خروج دستور را با `echo $?` ببینید. در `01-text-processing.md` توضیح دهید چرا با وجود داشتن خروجی در `stdout.txt`، کد خروج غیرصفر است. یک نمونه از `tee` نیز اجرا کنید تا خروجی `df -h /` را هم‌زمان در ترمینال و یک فایل ببینید.

## گام ۲ — کاربر سرویس و مجوزها

گزارش‌گیر نباید با `root` اجرا شود. یک کاربر سیستمی به نام `sysmon` با shell غیرتعاملی بسازید. مسیر واقعی `nologin` را در سیستم خود پیدا کنید و از راهنمای `useradd` برای انتخاب گزینه‌های درست کمک بگیرید.

دایرکتوری `/var/log/sysmon` را طوری بسازید که مالک و گروه آن `sysmon` باشند و فقط `sysmon` و `root` بتوانند محتوایش را ببینند یا تغییر دهند. با `id`، `getent passwd` و `ls -ld` نتیجه را بررسی و خروجی را در `02-user-management.md` ثبت کنید.

## گام ۳ — نصب و استفاده از jq

در این تمرین از `jq` برای تولید یک خلاصه‌ی JSON استفاده می‌کنید. ابتدا وجود آن را بررسی کنید، سپس با پکیج منیجر توزیع خود جست‌وجو و نصبش کنید.

با `apt` یا `dnf`، لیست پکیج‌ها را به‌روز کنید، `jq` را جست‌وجو و اطلاعات آن را بررسی کنید، سپس آن را نصب کنید. وجود نصب صحیح را هم با `command -v jq` و هم با دیتابیس مربوط به پکیج منیجر توزیعتان تأیید کنید. کامند‌های استفاده‌شده را در `03-package-management.md` بنویسید.

{{% notice style="info" title="نکته" %}}
`dnf check-update` در صورت وجود به‌روزرسانی می‌تواند با کد خروج `100` تمام شود؛ این به‌تنهایی خطا نیست.
{{% /notice %}}

پس از نصب، با این دستور نام interfaceهای شبکه را از JSON خروجی `ip` بخوانید:

```bash
ip -j address | jq -r '.[].ifname'
```

{{% notice style="info" title="آشنایی با jq" %}}
`jq` یک ابزار خط فرمان سبک برای خواندن، فیلترکردن و تبدیل داده‌های JSON است. اگر با APIها، فایل‌های پیکربندی یا خروجی ابزارهای DevOps کار می‌کنید، احتمالاً با `jq` زیاد برخورد خواهید داشت. در این تمرین فقط به استفاده‌های ساده از آن بسنده می‌کنیم.
{{% /notice %}}


## گام ۴ — اسکریپت گزارش‌گیر

اسکریپت `sysmon-report.sh` را ابتدا در دایرکتوری آزمایشی خود بنویسید و پس از آزمایش، آن را با نام `sysmon-report` در `/usr/local/bin/` قرار دهید. مالک آن باید `root` باشد و همه بتوانند آن را بخوانند و اجرا کنند. کامندهای نصب فایل و تنظیم مجوزها را خودتان انتخاب کنید.

اسکریپت باید این ویژگی‌ها را داشته باشد:

- با `#!/usr/bin/env bash` شروع و `set -euo pipefail` داشته باشد.
- هیچ آرگومانی نپذیرد؛ اگر آرگومان دریافت کرد، پیام `Usage` را به `stderr` بفرستد و با کد خروج `2` تمام شود.
- یک گزارش خوانا را به `stdout` چاپ کند که دست‌کم شامل زمان تولید، `uptime`، مصرف فایل‌سیستم `root` با `df -h /`، حافظه با `free -h`، پنج فرایند اول از نظر CPU با `ps`، و unitهای ناموفق `systemd` باشد.
- در پایان، یک خط JSON فشرده با `jq -cn` به `stdout` چاپ کند. این خط دست‌کم کلیدهای `generated_at`، `root_disk_used` و `failed_units` را داشته باشد.
- پیام خطا یا راهنما را فقط با `>&2` به `stderr` بفرستد؛ خروجی عادی نباید به `stderr` برود.

اسکریپت را یک بار با آرگومان نامعتبر و یک بار با کاربر `sysmon` اجرا کنید. کد خروج و تفکیک `stdout` و `stderr` را در هر دو حالت بررسی کنید.

برای خروجی JSON می‌توانید از الگوی زیر استفاده کنید؛ مقدار متغیرها را خودتان از کامندهای گزارش به دست آورید:

```bash
jq -cn \
  --arg generated_at "$generated_at" \
  --arg root_disk_used "$root_disk_used" \
  --argjson failed_units "$failed_units" \
  '{generated_at: $generated_at, root_disk_used: $root_disk_used, failed_units: $failed_units}'
```

## گام ۵ — systemd service و timer

یک unit از نوع `oneshot service` در `/etc/systemd/system/sysmon-report.service` بسازید. این سرویس باید اسکریپت را با `User=sysmon` و `Group=sysmon` اجرا کند. `ExecStart` باید مسیر مطلق `/usr/local/bin/sysmon-report` باشد.

برای جدا نگه‌داشتن دو جریان استاندارد، این دو گزینه را در بخش `[Service]` قرار دهید:

```ini
StandardOutput=append:/var/log/sysmon/stats.log
StandardError=append:/var/log/sysmon/error.log
```

یک timer هم‌نام در `/etc/systemd/system/sysmon-report.timer` بسازید که هر ۱۰ دقیقه service را اجرا کند. از `OnCalendar` و `Persistent=true` استفاده کنید. برای زمان‌بندی هر ۱۰ دقیقه، مقدار زیر معتبر است:

```ini
OnCalendar=*-*-* *:00/10:00
```

timer باید بخش `[Install]` با `WantedBy=timers.target` داشته باشد تا قابل فعال‌سازی باشد. service به `enable` شدن یا بخش `[Install]` نیاز ندارد؛ timer آن را اجرا می‌کند.

پس از ساخت unitها، daemon را reload کنید، timer را فعال کنید و سرویس را یک بار دستی اجرا کنید. با `systemctl list-timers`، `systemctl status` و `journalctl -u` وضعیت را بررسی کنید. بررسی کنید که گزارش در `stats.log` و پیام‌های خطا در `error.log` قرار می‌گیرند. اگر اجرای موفق خطایی نداشته باشد، خالی‌بودن `error.log` طبیعی است. خروجی کوتاه این بررسی‌ها را در `04-sysmon-service.md` ثبت کنید.

## گام ۶ — مدیریت لاگ با logrotate (اختیاری)

در برخی نصب‌های Ubuntu، `logrotate` از قبل وجود دارد. ابتدا وجود آن را با کامند مناسب بررسی کنید و فقط اگر نصب نبود، با پکیج منیجر توزیع خود نصبش کنید. روش بررسی و نصب را در `05-logrotate.md` بنویسید.

یک فایل پیکربندی به نام `/etc/logrotate.d/sysmon` بسازید که هر دو فایل `/var/log/sysmon/*.log` را روزانه rotate کند، هفت نسخه نگه دارد و فایل‌های قدیمی را فشرده کند. پیکربندی باید `missingok` و `notifempty` داشته باشد و با `create 0640 sysmon sysmon` فایل جدید را قابل نوشتن برای کاربر سرویس بسازد.

پیش از اعمال پیکربندی، آن را با گزینه‌ی debug `logrotate` بررسی کنید. سپس با گزینه‌ی force یک بار rotation را اجبار و نام فایل‌های ایجادشده را بررسی کنید.

در پایان، با `systemctl cat` و `systemctl status`، unitهای `logrotate.service` و `logrotate.timer` را بررسی کنید و تفاوت آن‌ها با service و timer خودتان را در `05-logrotate.md` بنویسید.

## گام ۷ — تحویل Pull Request

مانند تمرین هفته‌ی قبل، در فورک خود یک branch با نام `week-2` بسازید و Pull Request باز کنید. ساختار تحویل باید به این شکل باشد:

```text
<your-github-username>/
└── 2/
    ├── 01-text-processing.md
    ├── 02-user-management.md
    ├── 03-package-management.md
    ├── 04-sysmon-service.md
    ├── 05-logrotate.md
    └── assets/
        ├── sysmon-report.sh
        ├── sysmon-report.service
        ├── sysmon-report.timer
        └── sysmon
```

هر مرحله فقط یک فایل Markdown دارد و باید این موارد را داشته باشد:

- `01-text-processing.md`: پاسخ و کامندهای گام ۱، شامل دلیل کد خروج غیرصفر در مثال Redirection
- `02-user-management.md`: توزیع و نسخه‌ی Linux، خروجی بررسی کاربر `sysmon` و مجوزهای `/var/log/sysmon`
- `03-package-management.md`: کامندهای نصب و تأیید `jq` و خروجی آن‌ها
- `04-sysmon-service.md`: خروجی کوتاه `systemctl list-timers` و `journalctl -u sysmon-report.service`
- `05-logrotate.md`: نام فایل‌های rotateشده و تفاوت مشاهده‌شده بین `logrotate.timer` و timer خودتان (اختیاری)

فایل‌های داخل `assets/` باید دقیقاً با نسخه‌ی نصب‌شده در سیستم یکسان باشند: اسکریپت، دو unit و پیکربندی `logrotate`. لاگ‌های حجیم و اطلاعات حساس را وارد مخزن نکنید.

با الگوی Conventional Commits حداقل یک commit روی برنچ `week-2` بسازید؛ چند commit کوچک و معنادار بهتر از یک کامیت بزرگ شامل همه‌ی موارد است. branch را push کنید و از آن به `main` مخزن اصلی دوره Pull Request باز کنید. مانند هفته‌ی قبل منتظر بررسی منتور بمانید.

## چک‌لیست - نمایشی - لطفا برای تیک زدن PR نفرستید :)

- [ ] خروجی و خطای یک دستور را در دو فایل جدا دیده‌ام.
- [ ] `jq` را با پکیج منیجر نصب و روی JSON خروجی یک کامند استفاده کرده‌ام.
- [ ] اسکریپت با کاربر `sysmon` و بدون دسترسی `root` اجرا می‌شود.
- [ ] `sysmon-report.timer` فعال است و اجرای سرویس در `journalctl` دیده می‌شود.
- [ ] `stats.log` و `error.log` به درستی در `/var/log/sysmon` ایجاد شده‌اند.
- [ ] Pull Request هفته‌ی دوم را باز کرده‌ام.
