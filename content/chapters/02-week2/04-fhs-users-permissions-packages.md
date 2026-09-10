---
title: FHS، کاربران، مجوزها و Package Manager
weight: 4
description: جای فایل‌ها در Linux، هویت و دسترسی کاربران، مالکیت فایل‌ها و نصب امن بسته‌ها با apt و dnf
---

## فایل‌ها کجا هستند؟

**Filesystem Hierarchy Standard (FHS)** قراردادی برای محل قرارگیری فایل‌ها در Linux است. همهٔ توزیع‌ها دقیقاً یکسان نیستند، اما دانستن مسیرهای اصلی کمک می‌کند پیکربندی، لاگ و فایل اجرایی را در جای درست پیدا کنید.

<div dir="ltr">

- `/etc` — پیکربندی سراسری سامانه و سرویس‌ها؛ مانند `/etc/ssh/sshd_config`
- `/var` — داده‌ای که در طول کار سامانه تغییر می‌کند؛ مانند لاگ‌ها در `/var/log`
- `/home` — دایرکتوری خانگی کاربران عادی
- `/tmp` — فایل‌های موقت؛ برای نگهداری دادهٔ مهم مناسب نیست
- `/usr` — برنامه‌ها، کتابخانه‌ها و دادهٔ مشترک نصب‌شده توسط توزیع
- `/usr/local` — برنامه‌ها و اسکریپت‌هایی که مدیر سامانه به‌صورت محلی اضافه می‌کند
- `/opt` — نرم‌افزارهای جانبی و مستقل از `package manager` توزیع
- `/proc` — نمای مجازی از اطلاعات هسته و فرایندها، نه فایل‌های معمولی روی دیسک

</div>

برای اینکه بدانید یک برنامه از کجا اجرا می‌شود، از `command -v` استفاده کنید. برای مشاهدهٔ فضای فایل‌سیستم و mount point ها نیز `df` و `mount` مفیدند:

```bash
command -v bash
df -h
mount | less
```

## کاربران و گروه‌ها

هر فرایند با هویت یک کاربر اجرا می‌شود. این هویت تعیین می‌کند فرایند به کدام فایل‌ها و عملیات دسترسی دارد. گروه‌ها راهی برای اشتراک‌گذاری دسترسی بین چند کاربر هستند.

```bash
whoami
id
groups
getent passwd "$USER"
```

فایل‌های محلی اطلاعات کاربر و گروه معمولاً در `/etc/passwd` و `/etc/group` دیده می‌شوند، اما برای خواندن آن‌ها بهتر است از `getent` استفاده کنید؛ ممکن است سامانه هویت‌ها را از LDAP یا سرویس دیگری دریافت کند.

نمونهٔ ایجاد یک کاربر سرویس در محیط آزمایشی:

```bash
sudo useradd --create-home --shell /bin/bash deploy
sudo groupadd appteam
sudo usermod -aG appteam deploy
id deploy
```

گزینهٔ `-aG` کاربر را به گروه‌های جدید **اضافه** می‌کند. حذف `-a` می‌تواند گروه‌های فعلی کاربر را جایگزین کند و دسترسی او را ناخواسته تغییر دهد.

## مالکیت و مجوزها

هر فایل یک مالک، یک گروه و سه مجموعه مجوز دارد: برای مالک (`u`)، گروه (`g`) و دیگران (`o`). خروجی `ls -l` این اطلاعات را نشان می‌دهد:

```bash
ls -l deploy.sh
# -rwxr-x--- 1 deploy appteam 842 Sep 4 12:00 deploy.sh
```

ده نویسهٔ ابتدایی به‌ترتیب نوع فایل و مجوزهای مالک، گروه و دیگران را نشان می‌دهند. `r` برای خواندن، `w` برای نوشتن و `x` برای اجرا یا عبور از دایرکتوری است.

با نمادها یا به‌صورت عددی مجوزها را تغییر دهید:

```bash
chmod u+x deploy.sh
chmod g-w secrets.txt
chmod 640 app.conf
sudo chown deploy:appteam /srv/app/app.conf
```

در حالت عددی، `r` برابر 4، `w` برابر 2 و `x` برابر 1 است. بنابراین `640` یعنی مالک خواندن و نوشتن (`6`)، گروه فقط خواندن (`4`) و دیگران هیچ دسترسی‌ای (`0`) ندارند.

{{% notice style="yellow" title="هشدار: استفاده از sudo" %}}
`sudo` دستور را با دسترسی کاربر دیگر، معمولاً root، اجرا می‌کند. از آن فقط برای یک دستور مشخص استفاده کنید، نه برای اجرای shell دائمی. پیش از اجرای دستورهای دارای `sudo`، مسیر و اثر آن را بررسی کنید.
{{% /notice %}}

## Package Manager

`package manager`، نرم‌افزار را همراه وابستگی‌ها و به‌روزرسانی‌های امنیتی مدیریت می‌کند. بسته‌ها را از مخزن‌های رسمی یا مورد اعتماد نصب کنید؛ اسکریپت‌های نصب ناشناس را مستقیم با دسترسی root اجرا نکنید.

در Debian و Ubuntu از `apt` استفاده می‌شود:

```bash
sudo apt update
apt search nginx
apt show nginx
sudo apt install nginx
sudo apt remove nginx
sudo apt upgrade
```

در Fedora و RHEL از `dnf` استفاده می‌شود:

```bash
sudo dnf check-update
dnf search nginx
dnf info nginx
sudo dnf install nginx
sudo dnf remove nginx
sudo dnf upgrade
```

ابتدا فهرست یا فرادادهٔ بسته را به‌روز کنید، سپس بسته را نصب کنید. تفاوت‌های نسخهٔ توزیع‌ها را در مستندات همان توزیع بررسی کنید و به جای حدس‌زدن، نام دقیق بسته را با `search` پیدا کنید.

## منابع یادگیری

**مستندات و مقالات**

- [User management - Ubuntu Server Documentation](https://ubuntu.com/server/docs/how-to/security/user-management/) — مدیریت کاربر و گروه در Ubuntu
- [Permissions - Ubuntu Community Help Wiki](https://help.ubuntu.com/community/FilePermissions) — شرح مفصل مجوز و مالکیت
- [۱۰۴.۵ - مدیریت مجوز و مالکیت فایل‌ها - کتاب LPIC1 جادی](https://linux1st.com/1045-manage-file-permissions-and-ownership.html) — مقالهٔ مرتبط با مجوزها، مالکیت و دسترسی فایل‌ها
- [۱۰۴.۶ - ساخت و تغییر hard link و symbolic link - کتاب LPIC1 جادی](https://linux1st.com/1046-create-and-change-hard-and-symbolic-links.html) — مقالهٔ مرتبط با linkها و تفاوت hard و soft link
- [۱۰۴.۷ - پیدا کردن فایل‌های سیستم و قرار دادن فایل‌ها در محل درست - کتاب LPIC1 جادی](https://linux1st.com/1047-find-system-files-and-place-files-in-the-correct-location.html) — مقالهٔ مرتبط با FHS و محل فایل‌ها در لینوکس
- [۱۰۲.۴ - استفاده از مدیریت بستهٔ Debian - کتاب LPIC1 جادی](https://linux1st.com/1024-use-debian-package-management.html) — مقالهٔ مرتبط با `apt` و مدیریت بسته در توزیع‌های Debian

**ویدیو**

- [Linux File Permissions - freeCodeCamp](https://www.youtube.com/watch?v=LnKoncbQBsM) — مرور عملی مالکیت و `chmod`
- [الپیک ۱ - ۰۴۶ - ۱۰۴.۵ - یوزر و گروه و دسترسی‌ها در دنیای لینوکس (۲ قسمت) - جادی](https://www.youtube.com/watch?v=CEW_ozeLeK0&list=PL7ePwBdxM4nswZ62DvL58yJZ9W4-hOLLB&index=47) — آموزش userها، groupها و permissionها در Linux
- [الپیک ۱ - ۰۴۸ - ۱۰۴.۶ - هارد و سافت لینک‌ها در لینوکس؛ مفهوم، استفاده و کاربرد](https://www.youtube.com/watch?v=35vB01RcqgM&list=PL7ePwBdxM4nswZ62DvL58yJZ9W4-hOLLB&index=48) — آموزش کار با soft link و hard link و تفاوت آن‌ها
- [الپیک ۱ - ۰۴۹ - ۱۰۴.۷ - ساختار سلسله‌مراتبی فایل‌سیستم یونیکس و لینوکس و پیدا کردن جای فایل‌ها - جادی](https://www.youtube.com/watch?v=hO6qK-i3cXc&list=PL7ePwBdxM4nswZ62DvL58yJZ9W4-hOLLB&index=50) — مرور ساختار فایل‌سیستم و پیدا کردن فایل‌ها با ابزارهای لینوکسی
- [الپیک ۱ - ۰۱۷ - کار با package managerهای دبیانی - درک مفهوم منابع نرم‌افزاری و repository (۲ قسمت) - جادی](https://www.youtube.com/watch?v=6Hu4EtLuHo0&list=PL7ePwBdxM4nswZ62DvL58yJZ9W4-hOLLB&index=17) — آشنایی با مدیریت منابع نرم‌افزاری در توزیع‌های مبتنی بر Debian
