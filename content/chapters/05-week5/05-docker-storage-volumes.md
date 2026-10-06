---
title: مدیریت داده‌ها و Volumeها در Docker
weight: 5
description: ذخیره‌سازی داده‌های ماندگار در کانتینرها با Volumeها، Bind Mountها و tmpfs
---

## ماهیت موقت کانتینرها (Ephemeral Nature)

لایه‌ی خواندن و نوشتن کانتینرها به‌گونه‌ای طراحی شده است که **موقت (Ephemeral)** باشد. این یعنی:
- اگر کانتینر یک پایگاه داده بدون متصل کردن Volume حذف شود (`docker rm`)، داده‌ها و تغییرات ثبت‌شده در لایه‌ی کانتینر از بین خواهند رفت.
- کانتینرها به‌گونه‌ای طراحی شده‌اند که در صورت نیاز، بدون نگرانی از دست رفتن داده‌های اصلی بتوان آن‌ها را بازآفرینی یا با نسخه‌ی جدید جایگزین کرد (**Stateless vs Stateful**).

برای حل این مسئله و ذخیره‌سازی ماندگار داده‌ها (Persistent Storage)، داکر ۳ مکانیزم اصلی ارائه می‌دهد:

```text
       ┌────────────────────────────────────────────────────────┐
       │                      Docker Host                       │
       │                                                        │
       │   [ Bind Mount ]         [ Named Volume ]   [ tmpfs ]  │
       │   /home/ubuntu/app       /var/lib/docker/   (Host RAM) │
       │          │                      │               │      │
       └──────────┼──────────────────────┼───────────────┼──────┘
                  │                      │               │
       ┌──────────▼──────────────────────▼───────────────▼──────┐
       │                   Running Container                    │
       └────────────────────────────────────────────────────────┘
```

---

## انواع ذخیره‌سازی در Docker

### ۱. داکر والیوم (Named Volumes) - گزینه‌ی استاندارد و توصیه‌شده
والیوم‌ها دایرکتوری‌هایی هستند که مستقیماً توسط داکر مدیریت می‌شوند (به‌طور پیش‌فرض در مسیر `/var/lib/docker/volumes/` روی سرور لینوکس).
- سیستم‌عامل میزبان یا کاربران معمولی به محتوای آن دسترسی مستقیم ندارند.
- مستقل از چرخه‌ی حیات کانتینرها هستند؛ اگر کانتینر پاک شود، Volume دست‌نخورده باقی می‌ماند.
- گزینه‌ی استاندارد و توصیه‌شده برای ذخیره‌سازی ماندگار پایگاه‌های داده (مانند PostgreSQL، MySQL، MongoDB).

### ۲. بایند مانت (Bind Mounts)
اتصال مستقیم یک دایرکتوری یا فایل دلخواه از هاست لینوکسی به مسیری داخل کانتینر (مانند نگاشت `/home/ubuntu/app/src` به `/app/src`).
- هر تغییری در فایل‌های سیستم میزبان داخل کانتینر دیده می‌شود و برعکس.
- گزینه‌ی عالی برای محیط‌های توسعه (Live Reload کدهای برنامه‌نویسی) و قرار دادن فایل‌های تنظیماتی سرور (مانند کانفیگ Nginx).

### ۳. مانت موقت در رم (tmpfs Mount)
ذخیره‌سازی فایل‌ها روی حافظه‌ی موقت (RAM) سرور میزبان بدون نوشتن روی دیسک.
- سرعت خواندن و نوشتن فوق‌العاده بالا.
- با خاموش شدن کانتینر، داده‌ها پاک می‌شوند؛ مناسب نگهداری توکن‌های امنیتی موقت یا کش‌های پرسرعت.

---

## دستورهای مدیریت Volume

```bash
# ایجاد یک والیوم جدید
docker volume create pg_data

# مشاهده‌ی فهرست والیوم‌های موجود
docker volume ls

# دیدن جزئیات و مسیر فیزیکی والیوم روی دیسک
docker volume inspect pg_data

# حذف یک والیوم خاص
docker volume rm pg_data

# پاک کردن تمام والیوم‌هایی که توسط هیچ کانتینری استفاده نمی‌شوند
docker volume prune
```

---

## نحوه‌ی اتصال Volume به کانتینر: `-v` در مقابل `--mount`

در داکر دو سینتکس برای اتصال فضای ذخیره‌سازی وجود دارد:

1. **سینتکس کلاسیک `-v` (کوتاه):**
   ```bash
   -v volume_name:/container/path
   # یا برای Bind Mount:
   -v /host/path:/container/path:ro
   ```
2. **سینتکس مدرن و خواناتر `--mount` (پیشنهاد در اتوماسیون و اسکریپت‌ها):**
   ```bash
   --mount type=volume,source=volume_name,target=/container/path
   # یا برای Bind Mount:
   --mount type=bind,source=/host/path,target=/container/path,readonly
   ```

---

## آزمایش عملی: پایداری دیتابیس PostgreSQL با Named Volume

بیایید ماندگاری داده‌ها را با اجرای یک کانتینر دیتابیس تست کنیم:

### گام ۱: اجرای دیتابیس با اتصال یک Volume اختصاصی

```bash
docker run -d \
  --name mydb \
  -e POSTGRES_PASSWORD=mysecretpassword \
  -v pgdata:/var/lib/postgresql/data \
  postgres:16-alpine
```

### گام ۲: ورود به دیتابیس و ایجاد یک جدول و رکورد

```bash
docker exec -it mydb psql -U postgres
```

داخل محیط psql دستورات SQL زیر را وارد کنید:

```sql
CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(50));
INSERT INTO users (name) VALUES ('TechStack Learner');
SELECT * FROM users;
\q
```

### گام ۳: حذف کانتینر دیتابیس!
اکنون با اطمینان کانتینر را به اجبار متوقف و حذف می‌کنیم:

```bash
docker rm -f mydb
```

### گام ۴: اجرای یک کانتینر کاملاً جدید با همان والیوم قبلی

```bash
docker run -d \
  --name mydb_v2 \
  -e POSTGRES_PASSWORD=mysecretpassword \
  -v pgdata:/var/lib/postgresql/data \
  postgres:16-alpine
```

### گام ۵: بررسی بقای داده‌ها

```bash
docker exec -it mydb_v2 psql -U postgres -c "SELECT * FROM users;"
```

خروجی نشان می‌دهد که اطلاعات دقیقاً در جای خود باقی مانده‌اند:

```text
 id |       name        
----+-------------------
  1 | TechStack Learner
(1 row)
```

با این آزمایش دیدیم که با تخریب کانتینرها هیچ آسیبی به داده‌های پایدار وارد نمی‌شود.

---

## مثال عملی Bind Mount در محیط توسعه

فرض کنید می‌خواهید صفحه‌ی اول یک وب‌سرور Nginx را بدون نیاز به ساخت مجدد ایمیج (`docker build`) به صورت زنده ویرایش کنید:

### گام ۱: ساخت فایل اولیه و اجرای کانتینر با Bind Mount

```bash
mkdir -p ~/site
echo "<h1>Hello from Host Filesystem!</h1>" > ~/site/index.html

docker run -d --name web -p 8080:80 \
  -v /home/ubuntu/site:/usr/share/nginx/html:ro \
  nginx:alpine
```

(پسوند `:ro` دسترسی کانتینر به فایل‌های سرور را Read-Only می‌کند تا امنیت حفظ شود).

### گام ۲: تست خروجی اولیه با `curl`

```bash
curl http://localhost:8080
```

خروجی زیر دریافت می‌شود:

```html
<h1>Hello from Host Filesystem!</h1>
```

### گام ۳: تغییر مستقیم محتوای فایل روی هاست و بررسی زنده با `curl`

اکنون بدون ریستارت یا تغییر کانتینر، فایل `index.html` را روی هاست تغییر دهید:

```bash
echo "<h1>Updated content without rebuilding container!</h1>" > ~/site/index.html
```

مجدداً با `curl` وضعیت را بسنجید:

```bash
curl http://localhost:8080
```

خروجی بلافاصله تغییر را نمایش می‌دهد:

```html
<h1>Updated content without rebuilding container!</h1>
```

این آزمایش نشان می‌دهد که با Bind Mount، کانتینر مستقیماً فایل‌های مسیر هاست را می‌خواند؛ به همین دلیل این روش بهترین ابزار برای توسعه‌ی زنده (Live Development) بدون اتلاف وقت برای بازسازی ایمیج است.

---

## منابع یادگیری

**ویدیو**
- [آشنایی و کارهای مقدماتی با داکر قسمت دو از سه — جادی](https://www.youtube.com/watch?v=5OIOFIeHTkQ) — سناریوی کار با فایل‌ها و ذخیره‌سازی پایدار داده‌ها در داکر
- [Learn Docker Storage (Volumes & Bind Mounts) — Network Direction](https://www.youtube.com/watch?v=r1tIdACdJeE) — راهنمای بصری و جامع درک سازوکار انواع Volumeها و Bind Mountها در داکر

**مستندات و مقالات**
- [Manage data in Docker — Official Docs](https://docs.docker.com/storage/) — بررسی انواع ذخیره‌سازی در مستندات رسمی
