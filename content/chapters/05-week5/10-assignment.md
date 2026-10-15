---
title: تمرین هفته ۵
weight: 10
description: داکرایز کردن یک وب‌سرویس پایتونی با Multi-stage Dockerfile، انتشار ایمیج در GHCR و راه‌اندازی با Docker Compose متصل به PostgreSQL
---

در این تمرین، مجموعه‌ای از مهارت‌های کلیدی هفته‌ی پنجم را در قالب یک پروژه‌ی واقعی و استاندارد پیاده‌سازی می‌کنید: **ساخت ایمیج بهینه با رویکرد Multi-stage Build**، **انتشار ایمیج در رجیستری ابری (GitHub Container Registry - GHCR)**، **مدیریت Secretها و متغیرها با `.env`** و در نهایت **ارکستراسیون و راه‌اندازی Declarative سرویس‌ها (وب‌سرویس پایتون + پایگاه‌داده‌ی PostgreSQL) با Docker Compose**.

در [هفته‌ی چهارم](../04-week4/08-assignment.md) وب‌سرویس را مستقیماً روی سیستم‌عامل میزبان با استفاده از `systemd` و `venv` مستقر کردید. در این هفته وارد دنیای مدرن Cloud-Native می‌شوید؛ برنامه‌ی خود را بسته‌بندی (Containerize) می‌کنید تا مستقل از بستر میزبان، روی هر سروری با یک دستور بالا بیاید.

پیش از شروع، درس‌های این هفته به‌ویژه [ساخت Image با Dockerfile و بهینه‌سازی لایه‌ها](07-dockerfiles-and-images.md)، [کار با Registryها](08-container-registries.md) و [مدیریت سرویس‌های چندکانتینری با Docker Compose](09-docker-compose.md) را مرور کنید.

---

## مشخصات فنی و استانداردهای تمرین

پیاده‌سازی شما باید دقیقاً مطابق با مشخصات فنی زیر باشد:

| مولفه / نیازمندی | مقدار استاندارد الزامی | توضیحات |
| :--- | :--- | :--- |
| **وب‌سرویس پایتون** | `app/app.py` | مبتنی بر Flask، با اندپوینت‌های بررسی سلامت و اتصال به دیتابیس |
| **ساختار Dockerfile** | `Multi-stage Build` | تفکیک مرحله‌ی ساخت وابستگی‌ها (`builder`) از مرحله‌ی نهایی و سبک (`runtime`) |
| **کاربر غیر روت (اختیاری)** | `USER <username>` | اجرای پروسه‌ی کانتینر با کاربر غیر روت جهت ارتقای امنیت (اختیاری/بونس) |
| **رجیستری انتشار** | `ghcr.io` (GHCR) | ایمیج باید در رجیستری گیت‌هاب منتشر و دسترسی آن عمومی (`Public`) باشد |
| **آدرس ایمیج در Compose** | `image: ghcr.io/<username>/<image>:<tag>` | فایل Compose نباید ایمیج وب را به‌صورت محلی (`build: .`) بسازد؛ بلکه باید مستقیماً ایمیج GHCR را فراخوانی کند |
| **پایگاه‌داده** | `postgres:16-alpine` | سرویس دیتابیس در فایل Compose همراه با Named Volume ماندگار |
| **بررسی سلامت دیتابیس (اختیاری)** | `healthcheck` با `pg_isready` | اطمینان از بالا آمدن کامل دیتابیس پیش از استارت وب‌سرویس (اختیاری/بونس) |
| **پورت‌های ارتباطی** | وب: `8080` (هاست) ◄ `5000` (کانتینر)<br>دیتابیس: فقط داخلی روی پورت `5432` | پورت دیتابیس به دلایل امنیتی **نباید** روی هاست منتشر (`ports`) شود |
| **مدیریت Secretها و متغیرها** | `.env` و `.env.example` | مقادیر واقعی در `.env` (ignore شده در گیت) و نمونه‌ی تمپلیت در `.env.example` |
| **شبکه‌ی ارتباطی** | Custom Bridge Network | ارتباط دو کانتینر از طریق نام سرویس در شبکه‌ی اختصاصی Compose |

---

## گام ۱ — آماده‌سازی وب‌سرویس پایتون

در این مرحله ساختار اولیه‌ی پروژه‌ی پایتونی را آماده می‌کنید. این وب‌سرویس وظیفه دارد با پایگاه‌داده‌ی PostgreSQL ارتباط برقرار کند، وضعیت سلامت اتصال را بسنجد و تعداد درخواست‌های ثبت‌شده را در جدولی درون پایگاه‌داده ذخیره و شمارش کند.

ابتدا دایرکتوری کار تمرین را در ماشین لینوکسی خود بسازید:

```bash
mkdir -p ~/week-5-lab/app
cd ~/week-5-lab
```

### ۱. فایل نیازمندی‌ها (`app/requirements.txt`)

فایل `app/requirements.txt` را با محتویات زیر ایجاد کنید:

```text
Flask==3.1.3
psycopg2-binary==2.9.13
```

### ۲. کد وب‌سرویس (`app/app.py`)

فایل `app/app.py` را بسازید. این برنامه مشخصات اتصال به پایگاه‌داده را از متغیرهای محیطی دریافت می‌کند:

```python
import os
import time
import socket
import psycopg2
from psycopg2 import OperationalError
from flask import Flask, jsonify

app = Flask(__name__)

# Read database connection parameters from environment variables
DB_HOST = os.getenv("DB_HOST", "db")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "devops_db")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")

def get_db_connection(max_retries=5, delay=2):
    """Establish connection to PostgreSQL with retry logic."""
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(
                host=DB_HOST,
                port=DB_PORT,
                dbname=DB_NAME,
                user=DB_USER,
                password=DB_PASSWORD,
                connect_timeout=3
            )
            return conn
        except OperationalError:
            if attempt < max_retries - 1:
                time.sleep(delay)
            else:
                raise

def init_db():
    """Create the visits counter table if it does not exist."""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS visits (
                id SERIAL PRIMARY KEY,
                visited_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        app.logger.error(f"Database initialization error: {e}")

# Initialize table at application startup
try:
    init_db()
except Exception:
    pass

@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint to verify database connectivity."""
    try:
        conn = get_db_connection(max_retries=1)
        cur = conn.cursor()
        cur.execute("SELECT 1;")
        cur.close()
        conn.close()
        return jsonify({
            "status": "healthy",
            "database": "connected"
        }), 200
    except Exception as e:
        return jsonify({
            "status": "unhealthy",
            "database": f"disconnected: {str(e)}"
        }), 500

@app.route("/", methods=["GET"])
def index():
    """Record a new visit and return total visit count."""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS visits (
                id SERIAL PRIMARY KEY,
                visited_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        cur.execute("INSERT INTO visits DEFAULT VALUES;")
        conn.commit()

        cur.execute("SELECT COUNT(*) FROM visits;")
        count = cur.fetchone()[0]
        cur.close()
        conn.close()

        return jsonify({
            "service": "techstack-1405-python-app",
            "hostname": socket.gethostname(),
            "visits": count,
            "database": "connected"
        }), 200
    except Exception as e:
        return jsonify({
            "service": "techstack-1405-python-app",
            "error": str(e)
        }), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
```

---

## گام ۲ — ساخت Dockerfile چندمرحله‌ای (Multi-stage Build)

هدف این گام، نوشتن یک `Dockerfile` استاندارد با تکنیک **Multi-stage Build** است تا ایمیج نهایی فاقد کامپایلرها، پکیج‌های بیلد اضافه و فایل‌های کش `pip` باشد.

### ۱. ایجاد فایل `.dockerignore`

در ریشه‌ی پروژه (`~/week-5-lab/.dockerignore`) فایلی بسازید تا فایل‌های غیرضروری و حساس وارد Build Context نشوند:

```text
.git
.gitignore
.env
__pycache__
*.pyc
*.pyo
*.pyd
.pytest_cache
```

### ۲. الزامات و الگوی مفهومی فایل `Dockerfile`

در مسیر `~/week-5-lab/Dockerfile` یک فایل داکرفایل دومرحله‌ای طراحی کنید که نیازمندی‌های زیر را برآورده سازد:

1. **مرحله‌ی اول — ساخت و وابستگی‌ها (`Builder Stage`):**
   - از یک ایمیج پایه‌ی رسمی و پایدار پایتون (مانند `python:3.11-slim`) با یک شناسه (مانند `AS builder`) استفاده کنید.
   - یک مسیر کاری (`WORKDIR`) مشخص کنید.
   - یک محیط مجازی (`venv`) بسازید و مسیر باینری‌های آن را در متغیر محیطی `PATH` قرار دهید تا نیازمندی‌ها درون آن نصب شوند.
   - فایل وابستگی‌ها (`app/requirements.txt`) را پیش از کدهای سورس کپی کرده و وابستگی‌ها را با سوئیچ `--no-cache-dir` نصب کنید تا از قابلیت Caching لایه‌ها نهایت استفاده را ببرید.
2. **مرحله‌ی دوم — زمان اجرای نهایی (`Runtime Stage`):**
   - از یک ایمیج سبک و تمیز (مانند `python:3.11-slim`) به عنوان پایه‌ی مرحله‌ی نهایی استفاده کنید.
   - صرفاً پوشه‌ی محیط مجازی آماده را با دستور `COPY --from=builder ...` از مرحله‌ی بیلد به ایمیج نهایی منتقل کنید.
   - متغیر `PATH` را به مسیر محیط مجازی کپی‌شده تنظیم کنید تا دستور `python` مستقیماً پکیج‌های نصب‌شده را شناسایی کند.
   - کدهای برنامه (`app/`) را به کانتینر منتقل کنید.
   - پورت وب‌سرویس (`5000`) را با `EXPOSE` مشخص کنید و دستور اجرای وب‌سرویس (`CMD`) را به فرمت استاندارد Exec Form تعریف نمایید.

**قالب مفهومی (Conceptual Skeleton):**

```dockerfile
# ==========================================
# Stage 1: Build & Dependencies (Builder)
# ==========================================
FROM python:3.11-slim AS builder

WORKDIR /app

# TODO: ساخت محیط مجازی و تنظیم PATH
# ...

# TODO: کپی requirements.txt و نصب پکیج‌ها بدون کش
# ...

# ==========================================
# Stage 2: Runtime Image (Lean & Minimal)
# ==========================================
FROM python:3.11-slim

WORKDIR /app

# TODO: انتقال پوشه venv از استیج builder و تنظیم مجدد PATH
# COPY --from=builder ...
# ENV PATH=...

# TODO: کپی کدهای برنامه به مسیر کاری
# COPY ...

# TODO: مستندسازی پورت و دستور اجرای برنامه
# EXPOSE ...
# CMD [...]
```

### بخش اختیاری — اجرای امن با کاربر غیر روت (Non-root User)

{{% notice style="tip" title="چالش اختیاری: امنیت بیشتر کانتینر" %}}
به‌طور پیش‌فرض، پردازه‌ی درون کانتینر با کاربر `root` اجرا می‌شود. در محیط‌های واقعی Production، توصیه می‌شود یک کاربر و گروه سیستمی بدون دسترسی روت بسازید و اجرای برنامه را با دستور `USER` به آن واگذار کنید:

```dockerfile
# ایجاد کاربر و گروه سیستمی و اعطای دسترسی به دایرکتوری کار
RUN groupadd -r appuser && useradd -r -g appuser -d /app -s /sbin/nologin appuser \
    && chown -R appuser:appuser /app

USER appuser
```
پیاده‌سازی این بخش در تمرین **اختیاری** است.
{{% /notice %}}

### ۳. آزمایش ساخت ایمیج به‌صورت محلی و بررسی لایه‌ها

ایمیج را با یک تگ محلی بسازید و مشخصات آن را بررسی کنید:

```bash
docker build -t techstack-1405-python-app:test .
docker images techstack-1405-python-app:test
```

با دستور `docker history`، لایه‌های ساخته‌شده و میزان حجم هر لایه را مشاهده کنید:

```bash
docker history techstack-1405-python-app:test
```

بررسی کنید که کدام لایه‌ها بیشترین فضا را اشغال کرده‌اند و چگونه انتقال تمیز فایل‌های محیط مجازی (`/opt/venv`) باعث شده تا ابزارهای بیلد در ایمیج نهایی قرار نگیرند. خروجی کوتاه دستورهای بالا را برای ثبت در `01-dockerfile.md` یادداشت کنید.

---

## گام ۳ — آشنایی با GHCR و انتشار ایمیج (Image Push)

{{% notice style="info" title="رجیستری GHCR چیست و چرا از آن استفاده می‌کنیم؟" %}}
**GitHub Container Registry (GHCR)** با آدرس دامنه `ghcr.io`، سرویس میزبانی کانتینر اختصاصی گیت‌هاب است که با استاندارد OCI مطابقت دارد.

چرا به‌جای Docker Hub از GHCR استفاده می‌کنیم؟
1. **محدودیت‌ها و تحریم‌های داکر هاب برای کاربران ایران:** همان‌طور که در [درس سوم](03-docker-installation-mirrors-proxy.md) دیدید، سرویس داکر هاب به‌دلیل تحریم‌ها دسترسی مستقیم کاربران و سرورهای با IP ایران را مسدود کرده است (`403 Forbidden` یا خطای دسترسی جغرافیایی). ثبت اکانت، ورود و ارسال (`docker push`) به Docker Hub نیازمند استفاده‌ی مداوم از ابزارهای تغییر IP و پروکسی‌های اختصاصی است؛ در حالی که رجیستری **GHCR** به‌صورت مستقیم و پایدار از طریق اکانت گیت‌هاب در دسترس است و در بسیاری از محیط‌ها دردسرهای تحریم Docker Hub را ندارد.
2. **یکپارچگی مستقیم با گیت‌هاب:** مخزن کدهای شما، دسترسی‌ها و پکیج‌های کانتینری همگی ذیل یک حساب کاربری قرار می‌گیرند و برای پایپ‌لاین‌های CI/CD (هفته‌های آینده) نیاز به اتصال به سرویس شخص ثالث مجزا ندارید.
3. **سقف درخواست بسیار بالاتر (Rate Limits):** داکر هاب برای کاربران ناشناس محدودیت سخت‌گیرانه‌ی ۱۰۰ پول در ۶ ساعت اعمال می‌کند؛ در حالی که GHCR در تیم‌های DevOps پایداری و ظرفیت به مراتب بالاتری دارد.
4. **هم‌نامی سازمانی با مخزن پروژه:** نام ایمیج مستقیماً شامل نام کاربری شما در گیت‌هاب می‌شود: `ghcr.io/<your-github-username>/techstack-1405-python-app:1.0.0`.
{{% /notice %}}

برای انتشار ایمیج در GHCR مراحل زیر را دنبال کنید:

### ۱. ساخت توکن دسترسی شخصی (Personal Access Token - PAT)

برای ورود به GHCR با خط فرمان داکر، نمی‌توانید از رمز عبور عادی گیت‌هاب استفاده کنید. باید یک Personal Access Token بسازید:

1. در مرورگر وارد حساب کاربری **GitHub** خود شوید.
2. به بخش **Settings** (پروفایل شخصی) بروید.
3. در منوی سمت چپ به پایین صفحه اسکرول کرده و روی **Developer settings** کلیک کنید.
4. روی **Personal access tokens** و سپس **Tokens (classic)** کلیک کنید.
5. روی **Generate new token** ◄ **Generate new token (classic)** کلیک کنید.
6. یک نام در بخش `Note` وارد کنید (مانند `GHCR Token Week 5`).
7. تیک گزینه‌های زیر را فعال کنید:
   - `write:packages` (آپلود و انتشار پکیج‌ها در GitHub Package Registry)
   - `read:packages` (دانلود و دریافت پکیج‌ها)
   - `delete:packages` (اختیاری - برای مدیریت و حذف پکیج‌های قدیمی)
8. روی دکمه‌ی سبز رنگ **Generate token** کلیک کرده و رشته‌ی توکن ایجادشده (که با `ghp_` آغاز می‌شود) را در جایی امن کپی کنید.

{{% notice style="caution" title="هشدار امنیتی توکن‌ها" %}}
هرگز مقدار توکن PAT را در مخزن گیت کامیت نکنید یا آن را در فایل‌های متنی داخل ریپازیتوری ذخیره نسازید. توکن‌ها معادل رمز عبور شما هستند.
{{% /notice %}}

### ۲. لاگین در GHCR با دستور `docker login`

روی ماشین لینوکس خود، دستور `docker login` را برای رجیستری `ghcr.io` اجرا کنید:

```bash
docker login ghcr.io
```

داکر به‌صورت تعاملی (Interactive) نام کاربری و رمز عبور را از شما درخواست می‌کند:
1. **Username:** نام کاربری حساب کاربری GitHub خود را وارد کنید (با حروف کوچک انگلیسی).
2. **Password:** مقدار **Personal Access Token (PAT)** که در مرحله‌ی قبل کپی کردید را Paste کنید (رمز عبور اصلی اکانت کار نخواهد کرد و در ترمینال کاراکترهای آن نمایش داده نمی‌شوند).

{{% notice style="tip" title="نکته در مورد نام کاربری در GHCR" %}}
در مراحل لاگین و نام‌گذاری ایمیج‌ها، حتماً `<your-github-username>` را با حروف کوچک انگلیسی بنویسید؛ زیرا استاندارد رجیستری‌های کانتینر نسبت به حروف بزرگ حساس است.
{{% /notice %}}

در صورت موفقیت، پیام `Login Succeeded` در ترمینال نمایش داده می‌شود.

### ۳. تگ‌گذاری و ارسال ایمیج (Tag & Push)

ایمیج محلی را مطابق الگوی GHCR برچسب بزنید و به سرورهای گیت‌هاب ارسال کنید:

```bash
# برچسب‌گذاری ایمیج (استفاده از نسخه‌بندی معنایی مانند 1.0.0)
docker tag techstack-1405-python-app:test ghcr.io/<your-github-username>/techstack-1405-python-app:1.0.0

# ارسال لایه‌ها به رجیستری GHCR
docker push ghcr.io/<your-github-username>/techstack-1405-python-app:1.0.0
```

### ۴. الزامی: عمومی‌سازی دسترسی پکیج (Change Package Visibility to Public)

به‌صورت پیش‌فرض، ایمیج‌هایی که برای نخستین بار به GHCR ارسال می‌شوند ممکن است در وضعیت **Private** قرار گیرند. اگر ایمیج Private بماند، تیم داوری یا همکاران نمی‌توانند بدون لاگین به اکانت شما آن را Pull کنند.

برای عمومی کردن ایمیج:
1. در وب‌سایت گیت‌هاب به صفحه اصلی پروفایل خود بروید: `https://github.com/<your-github-username>`
2. به زبانه‌ی **Packages** بروید.
3. پکیج تازه‌تولیدشده‌ی `techstack-1405-python-app` را انتخاب کنید.
4. در سمت راست، روی **Package settings** کلیک کنید.
5. به انتهای صفحه بخش **Danger Zone** بروید و روی دکمه‌ی **Change visibility** کلیک کنید.
6. گزینه‌ی **Public** را انتخاب کرده و با تایپ نام پکیج، تغییر را تأیید نمایید.

برای آزمودن عمومی بودن، می‌توانید از طریق یک نشست یا شل بدون لاگین امتحان کنید:

```bash
docker pull ghcr.io/<your-github-username>/techstack-1405-python-app:1.0.0
```

---

## گام ۴ — مدیریت متغیرهای محیطی با `.env` و `.env.example`

یکی از اصول بنیادین متدولوژی [Twelve-Factor App](https://12factor.net/) (به‌ویژه اصل سوم: [III. Config](https://12factor.net/config))، تفکیک کامل پیکربندی‌ها و Secretها از کد برنامه است:
- **فایل `.env`:** حاوی مقادیر واقعی محیط جاری شماست و **هرگز نباید کامیت شود**.
- **فایل `.env.example`:** یک فایل الگو شامل نام تمام متغیرها و مقادیر پیش‌فرض یا ساختگی است که در مخزن گیت کامیت می‌شود تا دیگران بدانند چه متغیرهایی برای راه‌اندازی پروژه لازم است.

در مسیر `~/week-5-lab/.env.example` فایل زیر را بسازید:

```env
# تنظیمات پایگاه‌داده PostgreSQL
POSTGRES_DB=devops_db
POSTGRES_USER=postgres
POSTGRES_PASSWORD=change_this_to_a_secure_password
POSTGRES_PORT=5432

# تنظیمات پورت وب‌سرویس روی سیستم میزبان
APP_PORT=8080
```

سپس برای اجرای محلی خودتان، یک کپی از آن به نام `.env` ایجاد کرده و پسورد دلخواه خود را تعیین کنید:

```bash
cp .env.example .env
```

---

## گام ۵ — تدوین `compose.yaml` و راه‌اندازی یکپارچه‌ی سرویس‌ها

اکنون در ریشه‌ی پروژه، فایل `~/week-5-lab/compose.yaml` را طراحی کنید. این فایل زیرساخت دو کانتینری پروژه (دیتابیس PostgreSQL و وب‌سرویس پایتون) را به‌صورت توصیفی مدیریت می‌کند.

{{% notice style="caution" title="قانون مهم در مورد مرجع ایمیج وب‌سرویس" %}}
در فایل `compose.yaml` برای سرویس وب، **نباید** از کلید `build: .` استفاده کنید!
سرویس وب باید مستقیماً ایمیج عمومی شما در GHCR را فراخوانی کند:
```yaml
image: ghcr.io/<your-github-username>/techstack-1405-python-app:1.0.0
```
این کار تضمین می‌کند که ایمیج روی رجیستری ابری با موفقیت پابلیش شده، قابل دانلود عمومی است و بدون نیاز به کدهای سورس محلی روی سرور اجرا می‌شود.
{{% /notice %}}

### الزامات پیاده‌سازی `compose.yaml`:

1. **سرویس دیتابیس (`db`):**
   - استفاده از ایمیج سبک و پایدار `postgres:16-alpine`.
   - دریافت متغیرهای نام دیتابیس، کاربر و رمز عبور از فایل `.env` (مانند `${POSTGRES_DB}`).
   - اتصال داده‌های پایگاه‌داده (`/var/lib/postgresql/data`) به یک Named Volume جهت جلوگیری از حذف اطلاعات با خاموش شدن کانتینر.
   - اتصال به شبکه‌ی اختصاصی کانتینرها.
   - **نکته امنیتی:** به هیچ وجه پورت `5432` را به هاست نگاشت نکنید (`ports`)؛ ارتباط دیتابیس فقط باید در شبکه‌ی داخلی کانتینرها برقرار باشد.
2. **سرویس وب (`web`):**
   - فراخوانی ایمیج ساخته‌شده از GHCR (`ghcr.io/...`).
   - اتصال پورت هاست (از متغیر `${APP_PORT}`) به پورت کانتینر (`5000`).
   - تنظیم متغیرهای محیطی اتصال به پایگاه‌داده (`DB_HOST` برابر با نام سرویس دیتابیس یعنی `db`، `DB_PORT` برابر با `5432` و سایر مشخصات از `.env`).
   - تعریف وابستگی به دیتابیس (`depends_on: - db`).
   - اتصال به همان شبکه‌ی اختصاصی کانتینرها.
3. **تعریف سراسری منابع:**
   - بخش‌های `volumes:` و `networks:` در انتهای فایل تعریف شوند.

**قالب مفهومی (Conceptual Skeleton):**

```yaml
services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      # TODO: تنظیم متغیرهای POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD با ارجاع به .env
      POSTGRES_DB: ${POSTGRES_DB}
      # ...
    volumes:
      # TODO: اتصال Named Volume به مسیر دیتای پستگرس
      - <named_volume>:/var/lib/postgresql/data
    networks:
      - <custom_network>

  web:
    # الزامی: استفاده از ایمیج پابلیک GHCR (از build: . استفاده نکنید)
    image: ghcr.io/<your-github-username>/techstack-1405-python-app:1.0.0
    restart: unless-stopped
    ports:
      # TODO: مپ کردن پورت هاست به پورت 5000 کانتینر
      - "${APP_PORT}:5000"
    environment:
      # TODO: آدرس‌دهی نام سرویس دیتابیس (db) و ارسال مقادیر اتصال
      DB_HOST: db
      # ...
    depends_on:
      - db
    networks:
      - <custom_network>

volumes:
  # TODO: تعریف Named Volume برای ماندگاری اطلاعات
  <named_volume>:

networks:
  # TODO: تعریف شبکه‌ی اختصاصی Bridge
  <custom_network>:
```

### بخش اختیاری — سلامت‌سنجی دیتابیس (Healthcheck)

{{% notice style="tip" title="چالش اختیاری: راه‌اندازی مطمئن با Healthcheck" %}}
در داکر کامپوز، استفاده‌ی ساده از `depends_on: - db` فقط ترتیب استارت کانتینر را تعیین می‌کند، اما تضمین نمی‌کند که پروسه‌ی PostgreSQL در لحظه‌ی شروع وب‌سرویس کاملاً بالا آمده و آماده‌ی پذیرش اتصال باشد.

برای پیاده‌سازی حرفه‌ای این سازوکار، می‌توانید یک `healthcheck` روی کانتینر دیتابیس با باینری `pg_isready` تعریف کنید و در سرویس وب با شرط `condition: service_healthy` به آن وابسته شوید:

```yaml
  db:
    # ...
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 5

  web:
    # ...
    depends_on:
      db:
        condition: service_healthy
```
{{% notice style="info" title="چرا $$ به جای $ در دستور test استفاده شده؟" %}}
در فایلهای Compose، نماد `$` برای جایگزینی متغیرهای سیستم میزبان (Compose Variable Interpolation) به کار می‌رود. با نوشتن `$$` به داکر کامپوز اعلام می‌کنید که متغیر را در سطح هاست Expand نکند (`$$` به `$` خروجی داده می‌شود) تا شلِ داخل خود کانتینر در زمان اجرای دستور، مقدار متغیر محیطی داخل کانتینر را بخواند.
{{% /notice %}}

استفاده از این مکانیزم در تمرین **اختیاری** است و باعث پایداری و خودترمیمی بیشتر سرویس‌های شما در محیط‌های عملیاتی می‌شود.
{{% /notice %}}

---

## گام ۶ — تست، راه‌اندازی و اعتبارسنجی پایداری داده‌ها

### ۱. حذف ایمیج‌های محلی (تضمین Pull واقعی از GHCR)

برای اینکه مطمئن شوید فایل `compose.yaml` واقعاً ایمیج را از رجیستری ابری GHCR دانلود می‌کند و به کدهای محلی یا ایمیج کش‌شده روی سیستمتان وابسته نیست، تگ‌های محلی ساخته‌شده را از سیستم خود پاک کنید:

```bash
# حذف تگ‌های محلی ایمیج
docker rmi ghcr.io/<your-github-username>/techstack-1405-python-app:1.0.0
docker rmi techstack-1405-python-app:test
```

اکنون هنگام اجرای داکر کامپوز، لاگ دانلود لایه‌ها (`Pulling from ...`) را به وضوح در خروجی مشاهده خواهید کرد.

### ۲. راه‌اندازی سرویس‌ها با Docker Compose

```bash
# راه‌اندازی در پس‌زمینه (دانلود ایمیج‌ها و ایجاد کانتینرها)
docker compose up -d
```

### ۳. بررسی وضعیت و لاگ‌ها

```bash
docker compose ps
docker compose logs -f web
```

وضعیت سرویس دیتابیس و وب باید فعال (`Up` یا `healthy`) باشد.

### ۴. تست اندپوینت سلامت

در ترمینال، صحت ارتباط با پایگاه‌داده را با `curl` بیازمایید:

```bash
curl -i http://localhost:8080/health
```

خروجی باید کد وضعیت `200 OK` و پاسخ JSON زیر باشد:
```json
{"database":"connected","status":"healthy"}
```

### ۵. تست ثبت و شمارش داده‌ها

چند بار اندپوینت اصلی را فراخوانی کنید:

```bash
curl http://localhost:8080/
curl http://localhost:8080/
curl http://localhost:8080/
```

با هر درخواست، مقدار کلید `visits` باید یک واحد افزایش یابد (مثلاً `"visits": 3`).

### ۶. آزمون ماندگاری داده‌ها (Data Persistence Test)

اکنون کانتینرها را به‌طور کامل متوقف کرده و حذف نمایید:

```bash
docker compose down
```

توجه داشته باشید که دستور بالا کانتینرها را حذف می‌کند اما Named Volume حاوی اطلاعات دیتابیس حفظ می‌شود. دوباره کانتینرها را استارت کنید:

```bash
docker compose up -d
```

مجدداً اندپوینت را صدا بزنید:

```bash
curl http://localhost:8080/
```

مقدار `visits` باید ادامه‌ی ارقام قبلی (مثلاً `4`) باشد و از ۱ شروع نشود. این آزمایش تأیید می‌کند که والیوم داکر به درستی کار می‌کند.

---

## گام ۷ — ساختار تحویل تمرین و ارسال Pull Request

مستندات و فایل‌های تمرین را در فورک مخزن دوره‌ی تمرین‌ها روی شاخه‌ی `week-5` و درون ساختار پوشه‌ی زیر قرار دهید:

```text
<your-github-username>/
└── 5/
    ├── 01-dockerfile.md
    ├── 02-ghcr-publish.md
    ├── 03-compose-setup.md
    └── assets/
        ├── Dockerfile
        ├── compose.yaml
        ├── .env.example
        ├── .dockerignore
        └── app/
            ├── app.py
            └── requirements.txt
```

### شرح محتوای فایل‌های Markdown (کوتاه و متنی):

نیازی به گزارش‌نویسی طولانی، ارائه‌ی لاگ‌های مفصل یا اسکرین‌شات نیست؛ کافی است خروجی‌های متنی کوتاه زیر را در فایل‌ها قرار دهید:

1. **`01-dockerfile.md`**:
   - توضیح کوتاه (چند خط) درباره‌ی دو مرحله‌ی Dockerfile.
   - خروجی متنی دستورهای `docker images` و `docker history` برای ایمیج ساخته‌شده.
2. **`02-ghcr-publish.md`**:
   - آدرس لینک عمومی پکیج شما در GHCR (مثلاً `https://github.com/<username>/techstack-1405-python-app/pkgs/container/techstack-1405-python-app`).
   - خروجی چند خطی دستور `docker push`.
3. **`03-compose-setup.md`**:
   - خروجی متنی دستور `docker compose ps`.
   - خروجی دستورهای `curl` برای تست اندپوینت‌های `/health` و `/`.
   - خروجی تست ماندگاری بازدیدها پس از اجرای مجدد کانتینرها.

---

## چک‌لیست نهایی تحویل تمرین

پیش از باز کردن Pull Request، موارد زیر را بررسی و تأیید کنید:

- [ ] فایل `Dockerfile` از تکنیک Multi-stage Build استفاده کرده و حجم آن بهینه شده است.
- [ ] فایل `.dockerignore` در کنار Dockerfile قرار گرفته و مانع ارسال فایل‌های غیرضروری به کانتینر شده است.
- [ ] (اختیاری) اجرای پروسه‌ی کانتینر با کاربر غیر روت (`USER`) در فایل Dockerfile پیاده‌سازی شده است.
- [ ] ایمیج به رجیستری GHCR با تگ مشخص (مانند `1.0.0`) پوش شده و تنظیم دسترسی آن روی **Public** قرار دارد.
- [ ] در فایل `compose.yaml` از `image: ghcr.io/...` استفاده شده و کلید `build:` وجود ندارد.
- [ ] پایگاه‌داده PostgreSQL به یک Named Volume متصل است و پورت آن مستقیماً به هاست باز نشده است.
- [ ] فایل `.env.example` حاوی متغیرهای نمونه در پوشه `assets/` قرار داده شده و فایل واقعی `.env` در گیت کامیت نشده است.
- [ ] (اختیاری) سلامت‌سنجی (`healthcheck`) دیتابیس در فایل Compose کانفیگ شده و سرویس وب با شرط `condition: service_healthy` به آن وابسته است.
- [ ] آزمون ماندگاری داده‌ها (شمارش بازدیدها پس از `docker compose down`) با موفقیت انجام شده است.
- [ ] ساختار دایرکتوری در ریپازیتوری تمرین‌ها دقیقا در مسیر `<your-github-username>/5/` ایجاد شده است.
- [ ] شاخه‌ی گیت `week-5` آماده و Pull Request ارسال شده است.
