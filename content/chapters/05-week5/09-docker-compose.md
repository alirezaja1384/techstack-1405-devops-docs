---
title: مدیریت سرویس‌های چندکانتینری با Docker Compose
weight: 9
description: تعریف Declarative برنامه‌های چندکانتینری، پیکربندی compose.yaml و دستورهای Compose CLI
---

## چرا به Docker Compose نیاز داریم؟

تا به اینجا یاد گرفتید که چطور برای هر سرویس یک دستور `docker run` اجرا کنید، برایش شبکه بسازید، والیوم متصل کنید و متغیرهای محیطی را پاس بدهید. اما فرض کنید یک برنامه‌ی وب معمولی شامل بخش‌های زیر باشد:
1. یک سرویس فرانت‌اند (React)
2. یک وب‌سرویس بک‌اند (Node.js یا FastAPI)
3. یک پایگاه داده (PostgreSQL)
4. یک کش موقت (Redis)

برای بالا آوردن این سیستم، باید هر بار ۴ دستور طولانی `docker run` با ده‌ها فلگ و پارامتر بنویسید، مراقب ترتیب اجرای آن‌ها باشید و اگر سرور ریستارت شد همه را دوباره دستی اجرا کنید!

در [هفته‌ی چهارم](../04-week4/06-imperative-vs-declarative.md) با تفاوت رویکرد Imperative (دستوری) و Declarative (توصیفی) آشنا شدید. **Docker Compose** ابزاری Declarative است که به شما اجازه می‌دهد کل معماری چندکانتینری پروژه را در یک فایل متنی با فرمت YAML (به نام `compose.yaml`) تعریف کنید و مجموعه‌ی سرویس‌ها را با دستوراتی یکپارچه مدیریت و اجرا نمایید.

---

## ساختار فایل `compose.yaml`

طبق استاندارد مدرن Compose Specification، نام پیش‌فرض فایل **`compose.yaml`** است (اگرچه نام قدیمی `docker-compose.yml` نیز همچنان پشتیبانی می‌شود).

یک فایل استاندارد از بخش‌های زیر تشکیل شده است:

```yaml
services:
  # سرویس دیتابیس
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: secretpassword
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - backend-net

  # سرویس وب اپلیکیشن
  web:
    build:
      context: .
      dockerfile: Dockerfile
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      DATABASE_HOST: db
      DATABASE_PORT: 5432
      DATABASE_NAME: myapp
    depends_on:
      - db
    networks:
      - backend-net

volumes:
  db_data:

networks:
  backend-net:
```

### تحلیل بخش‌های کلیدی:

1. **`services`:** کانتینرهایی که باید اجرا شوند. در مثال بالا دو سرویس `db` و `web` داریم.
2. **`image` در مقابل `build`:** برای دیتابیس مستقیماً ایمیج آماده را از داکر هاب دانلود می‌کنیم (`image`)، اما برای وب‌سرویس، داکر آن را از روی Dockerfile محلی بیلد می‌کند (`build`).
3. **ارتباط شبکه و کشف خودکار:** هر دو سرویس به شبکه‌ی `backend-net` متصل هستند. سرویس `web` بدون نیاز به دانستن IP دیتابیس، مستقیماً از نام سرویس یعنی `db` به‌عنوان آدرس میزبان استفاده می‌کند (`DATABASE_HOST: db`).
4. **`ports`:** پورت `8080` هاست به پورت `80` کانتینر وب متصل شده است. دقت کنید که پورت دیتابیس را اصلاً به سیستم میزبان باز نکردیم تا از بیرون در دسترس نباشد و امنیت حفظ شود!
5. **`depends_on`:** ترتیب روشن شدن سرویس‌ها را تعیین می‌کند؛ ابتدا `db` و سپس `web` اجرا خواهد شد.
6. **`volumes` و `networks` سراسری:** تعریف والیوم ماندگار `db_data` و شبکه‌ی ایزوله‌ی `backend-net`.

---

## مدیریت متغیرهای محیطی با فایل‌های `.env` و `env_file`

هرگز کلمات عبور و متغیرهای حساس را مستقیماً داخل فایل `compose.yaml` هاردکد نکنید. Docker Compose روش‌های منعطفی برای تزریق متغیرهای محیطی در اختیارتان قرار می‌دهد:

### ۱. جایگزینی متغیرها در فایل Compose با فایل پیش‌فرض `.env`

داکر کامپوز به‌صورت پیش‌فرض و خودکار فایلی به نام `.env` را در همان دایرکتوری جست‌وجو کرده و مقادیر آن را در متغیرهای `${VARIABLE}` جایگزین (Interpolate) می‌کند:

فایل `.env`:
```env
DB_USER=appuser
DB_PASSWORD=SuperSecretPassword123!
DB_NAME=production_db
APP_PORT=8080
```

فایل `compose.yaml`:
```yaml
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
  web:
    image: myapp:1.0
    ports:
      - "${APP_PORT}:80"
```

---

### ۲. تزریق مستقیم فایل env به داخل کانتینر با `env_file`

گاهی نمی‌خواهید تک‌تک متغیرها را در بخش `environment` فایل YAML لیست کنید، بلکه می‌خواهید ده‌ها متغیر را مستقیماً از یک فایل مجزا وارد محیط کانتینر کنید. برای این کار از کلید `env_file` استفاده می‌شود:

```yaml
services:
  web:
    image: myapp:1.0
    env_file:
      - .env.web
      - .env.secrets
```

در این حالت، تمام خطوط داخل `.env.web` مستقیماً به‌عنوان متغیر محیطی داخل کانتینر `web` در دسترس خواهند بود.

---

### ۳. استفاده از فایل‌های سفارشی با فلگ `--env-file` (محیط‌های مختلف: Dev، Staging، Prod)

در پروژه‌های واقعی، تنظیمات دیتابیس و متغیرها در محیط توسعه (Local) با محیط تست یا پروداکشن متفاوت است. به‌جای داشتن چندین فایل Compose، می‌توانید فایل‌های متغیر اختصاصی (Custom Env Files) بسازید:

<div dir="ltr">

- `.env.development`
- `.env.staging`
- `.env.production`

</div>

برای مشخص کردن این فایل سفارشی در دستورات Compose، از فلگ `--env-file` استفاده کنید:

```bash
# اجرا با متغیرهای محیط توسعه
docker compose --env-file .env.development up -d

# اجرا با متغیرهای محیط Production
docker compose --env-file .env.production up -d
```

همچنین می‌توانید برای اعتبارسنجی مقادیر جایگزین‌شده قبل از اجرا، دستور زیر را بزنید:

```bash
docker compose --env-file .env.production config
```

این دستور خروجی نهایی و ترکیب‌شده‌ی فایل YAML را با متغیرهای پرشده در ترمینال نمایش می‌دهد.

---

## دستورهای پرکاربرد Docker Compose CLI

در نگارش مدرن داکر (Docker Compose V2)، دستورات با خط فاصله‌ی فاصله (`docker compose`) اجرا می‌شوند (به‌جای ابزار پایتونی قدیمی `docker-compose`).

### ۱. راه‌اندازی و اجرای کل پشته (Stack)

```bash
# ساخت ایمیج‌ها (در صورت نیاز) و اجرای تمام سرویس‌ها در پس‌زمینه
docker compose up -d

# اجرای مجدد همراه با بیلد مجدد اجباری ایمیج‌ها
docker compose up -d --build
```

### ۲. بررسی وضعیت سرویس‌ها

```bash
# مشاهده‌ی وضعیت سرویس‌ها و پورت‌های فعال
docker compose ps
```

### ۳. بررسی لاگ‌های یکپارچه

```bash
# مشاهده‌ی زنده و رنگی لاگ‌های همه‌ی کانتینرها به‌صورت هم‌زمان
docker compose logs -f

# مشاهده‌ی لاگ‌های یک سرویس خاص (مثلاً web)
docker compose logs -f web
```

### ۴. اجرای دستور داخل کانتینر سرویس

```bash
# ورود به شل سرویس web
docker compose exec web sh

# اجرای migration در پایگاه داده
docker compose exec web npm run db:migrate
```

### ۵. خاموش کردن و جمع‌آوری پشته

```bash
# توقف و حذف کانتینرها و شبکه‌ها (والیوم‌ها حفظ می‌شوند)
docker compose down

# توقف کامل همراه با پاک کردن کامل والیوم‌های دیسک (داده‌ها پاک می‌شوند)
docker compose down -v
```

---

## بررسی سلامت سرویس‌ها (Healthchecks)

دستور `depends_on` به‌تنهایی فقط مطمئن می‌شود که پردازش دیتابیس استارت خورده است، اما پردازش دیتابیس چند ثانیه طول می‌کشد تا آماده‌ی پذیرش اتصال (Ready for connections) شود.

برای رفع این مشکل، از `healthcheck` استفاده می‌شود:

```yaml
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: secret
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  web:
    image: myapp:1.0
    depends_on:
      db:
        condition: service_healthy
```

با این تنظیم هوشمند، سرویس `web` تا زمانی که دیتابیس کاملاً آماده و سالم (`healthy`) نشده باشد، استارت نمی‌خورد.

---

## منابع یادگیری

**ویدیو**
- [Ultimate Docker Compose Tutorial — TechWorld with Nana](https://www.youtube.com/watch?v=SXwC9fSwct8) — آموزش جامع و عملی Docker Compose، ساختار فایل‌های YAML و سناریوهای چندکانتینری

**مستندات و مقالات**
- [Docker Compose Getting Started — Official Docs](https://docs.docker.com/compose/gettingstarted/) — راهنمای رسمی شروع سریع و پروژه‌محور با Docker Compose
- [What is Docker Compose & How to Use It — freeCodeCamp](https://www.freecodecamp.org/news/what-is-docker-compose-how-to-use-it/) — راهنمای جامع و گام‌به‌گام کار با Docker Compose برای مبتدیان
