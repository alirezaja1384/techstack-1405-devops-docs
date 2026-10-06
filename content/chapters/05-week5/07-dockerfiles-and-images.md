---
title: ساخت Image با Dockerfile و بهینه‌سازی لایه‌ها
weight: 7
description: ساخت ایمیج‌های استاندارد با Dockerfile، درک لایه‌ها، کش بیلد و Multi-stage Builds
---

## ماهیت یک Docker Image و مفهوم لایه‌ها (Layers)

ایمیج یک قالب فقط‌خواندنی (Read-Only) شامل سیستم‌عامل پایه، وابستگی‌ها، کد برنامه و تنظیمات پیش‌فرض است. کانتینر در حقیقت یک نمونه‌ی در حال اجرا (Instance) از یک ایمیج است که داکر روی آن یک لایه‌ی نازک و موقت برای خواندن و نوشتن (**Read/Write Container Layer**) قرار می‌دهد.

```text
┌───────────────────────────────────────────────┐
│ [R/W] Container Layer (تغییرات موقت کانتینر)  │ ◄── پاک با حذف کانتینر
├───────────────────────────────────────────────┤
│ [R/O] Layer 4: CMD ["python", "app.py"]       │
├───────────────────────────────────────────────┤
│ [R/O] Layer 3: COPY . /app                    │ ◄── ایمیج (فقط‌خواندنی)
├───────────────────────────────────────────────┤
│ [R/O] Layer 2: RUN pip install -r reqs.txt    │
├───────────────────────────────────────────────┤
│ [R/O] Layer 1: FROM python:3.11-slim          │
└───────────────────────────────────────────────┘
```

هر دستوری در فایل `Dockerfile` (مانند `RUN`، `COPY`، `ADD`) یک لایه‌ی مجزا به ایمیج اضافه می‌کند. به لطف مکانیزم **Copy-on-Write (CoW)**، اگر دو یا چند کانتینر از یک ایمیج ساخته شوند، همه‌ی آن‌ها لایه‌های ایمیج را به‌صورت مشترک می‌خوانند و هیچ فضای اضافه‌ای مصرف نمی‌شود.

---

## دستورهای اصلی در Dockerfile

یک `Dockerfile` فایلی متنی بدون پسوند است که گام‌های ساخت یک ایمیج را به صورت خودکار تعریف می‌کند:

- **`FROM`**: مشخص کردن ایمیج پایه (مثلاً `python:3.11-slim` یا `node:20-alpine`). همیشه اولین دستور غیراز کامنت یا `ARG` است.
- **`WORKDIR`**: تعیین دایرکتوری کاری درون کانتینر برای اجرای دستورات بعدی (به‌جای استفاده‌ی نامنظم از دایرکتوری روت `/`).
- **`COPY`**: کپی کردن فایل‌ها یا دایرکتوری‌ها از سیستم میزبان به داخل ایمیج.
- **`ADD`**: شبیه `COPY`، اما توانایی اکسترکت خودکار آرشیوهای `tar` و دانلود از URL را دارد. در عمل برای جلوگیری از رفتارهای غیرمنتظره، معمولا استفاده از **`COPY`** توصیه می‌شود.
- **`RUN`**: اجرای دستور در زمان ساخت ایمیج (مانند نصب پکیج‌ها با `apt-get` یا `npm install`).
- **`ENV`**: تعریف متغیرهای محیطی که هم در زمان ساخت و هم در زمان اجرای کانتینر در دسترس خواهند بود.
- **`ARG`**: متغیرهای موقتی که فقط در زمان ساخت ایمیج (`docker build --build-arg`) معتبرند و در ایمیج نهایی ذخیره نمی‌شوند.
- **`EXPOSE`**: صرفاً یک برچسب مستندسازی (Documentation) برای اعلام پورتی که برنامه روی آن گوش می‌دهد.
- **`CMD` و `ENTRYPOINT`**: دستوری که هنگام استارت کانتینر اجرا می‌شود:
  - فرم استاندارد (Exec Form): `CMD ["python", "app.py"]` (توصیه‌شده، بدون ایجاد شل میانی).
  - فرم شل (Shell Form): `CMD python app.py` (تحت پردازش `/bin/sh -c` اجرا می‌شود).

---

## فایل `.dockerignore` و Build Context

هنگام اجرای دستور `docker build .`، نقطه‌ی پایانی (`.`) نشان‌دهنده‌ی **Build Context** است. داکر کلاینت ابتدا تمام فایل‌های این مسیر را بسته‌بندی کرده و برای دیمن داکر می‌فرستد.

اگر دایرکتوری شما شامل پوشه‌های حجیمی مانند `.git/`، `node_modules/` یا فایل‌های حساسی مانند `.env` باشد، حجم و زمان بیلد بسیار بالا می‌رود و احتمال نشت اطلاعات محرمانه وجود دارد.

همیشه در کنار Dockerfile یک فایل به نام `.dockerignore` بسازید:

```text
.git
.gitignore
.env
node_modules
*.log
__pycache__
```

---

## بهینه‌سازی کش لایه‌ها (Layer Caching)

داکر هنگام بیلد، اگر دستوری و فایل‌های مرتبط با آن تغییر نکرده باشند، از کش بیلد قبلی استفاده می‌کند. ترتیب دستورات در Dockerfile بسیار تعیین‌کننده است:

### روش غیراصولی:

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
CMD ["python", "app.py"]
```
در این حالت، با هر تغییر کوچک در کدهای برنامه، خط `COPY . .` بیلد کش را باطل می‌کند و دستور سنگین `pip install` باید هر بار از اول اجرا و دانلود شود!

### روش اصولی و بهینه:

```dockerfile
FROM python:3.11-slim
WORKDIR /app

# ابتدا فقط فایل تعریف وابستگی‌ها را کپی و نصب می‌کنیم
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# در مرحله آخر کدهای پروژه را کپی می‌کنیم
COPY . .

CMD ["python", "app.py"]
```
در این حالت، تا زمانی که فایل `requirements.txt` تغییر نکند، داکر مرحله‌ی نصب وابستگی‌ها را از کش فوری می‌خواند و زمان بیلد به زیر چند ثانیه کاهش می‌یابد.

---

## چندمرحله‌ای ساختن ایمیج‌ها (Multi-stage Builds)

در زبان‌های کامپایلری (مانند Go، Rust یا Java) یا برنامه‌های فرانت‌اند (React، Vue)، ابزارهای بیلد، کامپایلرها و کدهای سورس حجم بسیار بالایی (چند صد مگابایت یا گیگابایت) دارند، در حالی که در محیط Production فقط به فایل باینری کامپایل‌شده یا فایل‌های خروجی HTML/JS نیاز داریم.

با **Multi-stage Build** می‌توانید چند ایمیج مجزا در یک Dockerfile تعریف کنید و فقط خروجی تمیز را به ایمیج نهایی منتقل کنید:

```dockerfile
# مرحله اول: بیلد و کامپایل برنامه (Build Stage)
FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /bin/myapp .

# مرحله دوم: محیط اجرایی نهایی و سبک (Production Stage)
FROM alpine:3.19
WORKDIR /app
COPY --from=builder /bin/myapp /app/myapp
EXPOSE 8080
CMD ["/app/myapp"]
```

نتیجه؟ حجم ایمیج نهایی به‌جای ۶۰۰ مگابایت به کمتر از ۲۰ مگابایت کاهش می‌یابد و هیچ ابزار اضافی یا سورس کدی در محیط پروداکشن وجود ندارد که سطح حملات امنیتی را بالا ببرد.

---

> ### ℹ️ نکته و راهنمای امنیتی: اجرای کانتینر با کاربر غیر روت (`USER`)
> 
> به‌طور پیش‌فرض، کانتینرها با کاربر `root` اجرا می‌شوند. در محیط‌های واقعی و استانداردهای امنیتی Production، اجرای کانتینر با دسترسی root به‌دلیل خطرات امنیتی توصیه نمی‌شود؛ زیرا اگر مهاجم بتواند از برنامه‌ی داخل کانتینر سوءاستفاده کند، ممکن است شانس بیشتری برای فرار از کانتینر (Container Escape) و نفوذ به سیستم‌عامل میزبان داشته باشد.
> 
> برای اجرای امن با کاربر غیر روت در `Dockerfile`:
> 
> ```dockerfile
> FROM python:3.11-slim
> 
> # ایجاد گروه و کاربر سیستمی بدون دسترسی روت
> RUN groupadd -r appuser && useradd -r -g appuser -d /app -s /sbin/nologin appuser
> 
> WORKDIR /app
> COPY requirements.txt .
> RUN pip install --no-cache-dir -r requirements.txt
> 
> COPY . .
> 
> # تغییر مالکیت فایل‌ها به کاربر جدید
> RUN chown -R appuser:appuser /app
> 
> # تغییر کاربر فعال کانتینر
> USER appuser
> 
> CMD ["python", "app.py"]
> ```
> 
> همچنین در توزیع‌های مبتنی بر Alpine می‌توانید از `adduser` استفاده کنید:
> 
> ```dockerfile
> RUN addgroup -S appgroup && adduser -S appuser -G appgroup
> USER appuser
> ```
> 
> **توجه:** به دلیل محدودیت زمان دوره‌ی هفتگی و برای جلوگیری از درگیر شدن با خطاهای پیچیده‌ی دسترسی فایل‌ها (`Permission Denied`) در گام‌های اولیه، استفاده از این تنظیم در تمرین‌های این هفته **اختیاری** است، اما شناخت آن برای محیط‌های واقعی سازمانی ضروری است.

---

## آزمایش عملی: ساخت و اجرای ایمیج با `docker build`

بیایید یک پروژه‌ی ساده‌ی پایتونی ایجاد کنیم، برای آن Dockerfile بنویسیم، ایمیج را بسازیم و کانتینر آن را اجرا کنیم:

### گام ۱: ایجاد دایرکتوری و فایل برنامه‌ی پایتون

یک دایرکتوری به نام `python-demo` بسازید و وارد آن شوید:

```bash
mkdir -p ~/python-demo
cd ~/python-demo
```

یک اسکریپت پایتون ساده به نام `app.py` ایجاد کنید:

```python
# app.py
import os
import sys

course_name = os.getenv("COURSE_NAME", "DevOps Course")
print(f"Hello from inside Docker Container!")
print(f"Welcome to {course_name} (Week 5: Docker & Images)")
print(f"Python Version: {sys.version.split()[0]}")
```

### گام ۲: نوشتن فایل `Dockerfile`

در همان دایرکتوری، فایلی به نام `Dockerfile` بسازید:

```dockerfile
# استفاده از ایمیج سبک پایتون
FROM python:3.11-slim

# تعیین مسیر کاری درون کانتینر
WORKDIR /app

# کپی کردن اسکریپت برنامه به داخل کانتینر
COPY app.py .

# تعریف متغیر محیطی پیش‌فرض
ENV COURSE_NAME="TechStack DevOps"

# دستوری که با استارت کانتینر اجرا می‌شود
CMD ["python", "app.py"]
```

### گام ۳: ساخت ایمیج با دستور `docker build`

دستور زیر را در همان مسیر اجرا کنید (نقطه‌ی انتهایی نشان‌دهنده‌ی مسیر فعلی است):

```bash
docker build -t myapp:1.0.0 .
```

برای مشاهده‌ی ایمیج ساخته‌شده در لیست ایمیج‌های سیستم:

```bash
docker images
```

### گام ۴: اجرای کانتینر از روی ایمیج ساخته‌شده

اکنون کانتینر را از روی ایمیج محلی خود اجرا کنید:

```bash
docker run --rm myapp:1.0.0
```

خروجی مشابه زیر در ترمینال چاپ می‌شود:

```text
Hello from inside Docker Container!
Welcome to TechStack DevOps (Week 5: Docker & Images)
Python Version: 3.11.x
```

همچنین می‌توانید با فلگ `-e` مقدار متغیر محیطی را تغییر دهید:

```bash
docker run --rm -e COURSE_NAME="CESSA's TechStack" myapp:1.0.0
```

### گام ۵: حذف ایمیج (در صورت عدم نیاز)

```bash
docker rmi myapp:1.0.0
```

---

## منابع یادگیری

**ویدیو**
- [آشنایی و کارهای مقدماتی با داکر قسمت سه از سه — جادی](https://www.youtube.com/watch?v=QrcCZHVlleg) — آموزش فارسی شامل ساخت ایمیج با Dockerfile و مباحث تکمیلی شبکه در داکر

**مستندات و مقالات**
- [Best practices for writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/) — الگوهای بهینه‌سازی لایه‌ها، حجم و امنیت ایمیج‌ها
- [Multi-stage builds Guide](https://docs.docker.com/build/building/multi-stage/) — راهنمای رسمی پیاده‌سازی ایمیج‌های چندمرحله‌ای
