#!/usr/bin/env bash
# ==============================================================
# 🚀 HamkarHub Quick GitHub Installer
# اسکریپت نصب یک‌خطی همکار هاب مستقیم از گیت‌هاب روی اوبونتو
# ==============================================================
set -e

# بررسی مجوز روت یا sudo
if [ "$EUID" -ne 0 ]; then
    if ! command -v sudo &> /dev/null; then
        echo "❌ لطفاً این اسکریپت را با کاربر root یا با دستور sudo اجرا فرمایید."
        exit 1
    fi
    SUDO="sudo"
else
    SUDO=""
fi

echo ""
echo "=========================================================="
echo "  🚀 نصب خودکار سامانه همکار هاب از مخزن گیت‌هاب"
echo "  سازگار با: Ubuntu 20.04 / 22.04 / 24.04 LTS"
echo "=========================================================="
echo ""

# ۱. نصب پیش‌نیازهای اولیه
echo "📦 ۱/۶ نصب ابزارهای پایه (git, curl, ufw, build-essential, nginx, certbot)..."
$SUDO apt-get update -y
$SUDO apt-get install -y git curl ufw unzip build-essential nginx openssl certbot python3-certbot-nginx

# ۲. بررسی و نصب Node.js 20 LTS
echo "📦 ۲/۶ بررسی و نصب Node.js 20 LTS..."
NEED_NODE=0
if ! command -v node &> /dev/null; then
    NEED_NODE=1
else
    NODE_MAJOR=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_MAJOR" -lt 18 ]; then
        echo "نسخه Node.js فعلی ($NODE_MAJOR) قدیمی است، ارتقا به نسخه 20..."
        NEED_NODE=1
    fi
fi

if [ "$NEED_NODE" -eq 1 ]; then
    echo "⚡ در حال راه‌اندازی مخزن رسمی Node.js 20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x -o /tmp/nodesource_setup.sh
    if [ "$EUID" -ne 0 ]; then
        sudo bash /tmp/nodesource_setup.sh
        sudo apt-get install -y nodejs
    else
        bash /tmp/nodesource_setup.sh
        apt-get install -y nodejs
    fi
    rm -f /tmp/nodesource_setup.sh
fi

echo "✅ نسخه Node.js: $(node -v)"
echo "✅ نسخه NPM: $(npm -v)"

# ۳. تعیین دایرکتوری نصب یا کلون از گیت‌هاب
TARGET_DIR="/opt/hamkarhub"
BRANCH="main"

# اگر کاربر از داخل یک پوشه ریپو این اسکریپت را صدا زده باشد:
if [ -f "./server.ts" ] && [ -f "./package.json" ]; then
    TARGET_DIR=$(pwd)
    echo "📁 تشخیص داده شد که از قبل درون ریپو قرار دارید: $TARGET_DIR"
else
    # دریافت آدرس ریپو در صورت پاس دادن به عنوان متغیر یا آرگومان اول
    REPO_URL="${1:-${GITHUB_REPO:-}}"
    if [ -z "$REPO_URL" ]; then
        REPO_URL="https://github.com/amirazamidev/hamkarhub-lite.git"
    fi

    echo "📁 ۳/۶ آماده‌سازی دایرکتوری در $TARGET_DIR..."
    if [ -d "$TARGET_DIR/.git" ]; then
        echo "🔄 نسخه قبلی پیدا شد؛ در حال به‌روزرسانی به آخرین نسخه ($REPO_URL)..."
        cd "$TARGET_DIR"
        # جلوگیری از خطای «dubious ownership» هنگام اجرای git با root
        $SUDO git config --global --add safe.directory "$TARGET_DIR" 2>/dev/null || true
        # اتصال به مخزن جدید (حتی اگر قبلاً به مخزن دیگری وصل بود)
        $SUDO git remote set-url origin "$REPO_URL" 2>/dev/null || $SUDO git remote add origin "$REPO_URL"
        # به‌روزرسانی اجباری و نادیده‌گرفتن تغییرات محلی (فایل‌های بیلد مانند dist/server.js نادیده گرفته می‌شوند)
        if $SUDO git fetch origin --prune --tags && $SUDO git reset --hard "origin/$BRANCH"; then
            echo "✅ کد به آخرین نسخه به‌روزرسانی شد."
        else
            echo "⚠️ به‌روزرسانی خودکار ناموفق بود. برای نصب تمیز، مسیر $TARGET_DIR را حذف و مجدداً اسکریپت را اجرا کنید."
            exit 1
        fi
    else
        $SUDO rm -rf "$TARGET_DIR" 2>/dev/null || true
        echo "📥 در حال کلون کردن پروژه از گیت‌هاب ($REPO_URL)..."
        $SUDO git clone "$REPO_URL" "$TARGET_DIR" || {
            echo "⚠️ کلون از آدرس مستقیم ناموفق بود."
            echo "در صورت خصوصی بودن مخزن (Private)، ابتدا با دستور زیر کلون کنید:"
            echo "   git clone https://github.com/amirazamidev/hamkarhub-lite.git $TARGET_DIR"
            exit 1
        }
        cd "$TARGET_DIR"
    fi
fi

cd "$TARGET_DIR"

RUN_USER="${SUDO_USER:-$(whoami)}"
$SUDO chown -R "$RUN_USER:$RUN_USER" "$TARGET_DIR" || true

# ۴. نصب وابستگی‌های پکیج و ساخت بیلد فرانت‌اند
echo "📦 ۴/۶ در حال نصب پکیج‌های npm (این فرآیند ممکن است ۱ تا ۲ دقیقه طول بکشد)..."
npm install --legacy-peer-deps

echo "🔨 در حال ساخت بیلد نهایی پروژه (npm run build)..."
export UV_THREADPOOL_SIZE=4
NODE_OPTIONS="--max-old-space-size=1536" npm run build

# ۵. پیکربندی سرویس daemon دائمی systemd (برنامه به‌صورت داخلی روی پورت ۳۰۰۰ اجرا می‌شود)
echo "⚙️ ۵/۶ راه‌اندازی سرویس خودکار پس‌زمینه (systemd)..."

NODE_PATH=$(which node)
RUN_USER=$(logname 2>/dev/null || echo $SUDO_USER)
if [ -z "$RUN_USER" ]; then
    RUN_USER=$(whoami)
fi

$SUDO bash -c "cat <<EOF > /etc/systemd/system/hamkarhub.service
[Unit]
Description=HamkarHub Coworking Hotspot Chat Server
After=network.target

[Service]
Type=simple
User=$RUN_USER
WorkingDirectory=$TARGET_DIR
ExecStart=$NODE_PATH $TARGET_DIR/server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=UV_THREADPOOL_SIZE=4
Environment=NODE_OPTIONS=--max-old-space-size=1024

[Install]
WantedBy=multi-user.target
EOF"

$SUDO chown -R $RUN_USER:$RUN_USER "$TARGET_DIR" || true

$SUDO systemctl daemon-reload
$SUDO systemctl enable hamkarhub.service
$SUDO systemctl restart hamkarhub.service

# ۶. پیکربندی Nginx روی پورت‌های ۸۰ و ۴۴۳ و فایروال
echo "⚙️ ۶/۶ پیکربندی Nginx روی پورت‌های ۸۰ و ۴۴۳..."

$SUDO bash -c "cat <<'EOF' > /etc/nginx/sites-available/hamkarhub
# HamkarHub reverse proxy (80/443) -> Node app on 127.0.0.1:3000
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    client_max_body_size 12m;

    # Server-Sent Events (چت زنده)
    location /api/chat/stream {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding on;
        proxy_read_timeout 24h;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_read_timeout 3600s;
    }
}
EOF"

# حذف سایت پیش‌فرض Nginx و فعال‌سازی سایت همکار هاب
$SUDO rm -f /etc/nginx/sites-enabled/default || true
$SUDO ln -sf /etc/nginx/sites-available/hamkarhub /etc/nginx/sites-enabled/hamkarhub
if $SUDO nginx -t; then
    $SUDO systemctl enable nginx >/dev/null 2>&1 || true
    $SUDO systemctl restart nginx || true
else
    echo "⚠️ پیکربندی Nginx نامعتبر بود؛ لطفاً دستی بررسی کنید."
fi

# فایروال: پورت‌های وب (۸۰/۴۴۳) و پورت داخلی برنامه
$SUDO ufw allow 80/tcp || true
$SUDO ufw allow 443/tcp || true
$SUDO ufw allow 3000/tcp || true

SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "=========================================================="
echo "🎉 سامانه همکار هاب با یک کامند با موفقیت نصب و فعال شد!"
echo "=========================================================="
echo "🌐 آدرس دسترسی در شبکه وای‌فای: http://${SERVER_IP}"
echo "🔐 پنل ادمین و مدیریت میکروتیک: http://${SERVER_IP} (رمز پیش‌فرض: admin123)"
echo "🔒 برای فعال‌سازی SSL (HTTPS روی پورت ۴۴۳): sudo bash setup-ssl.sh"
echo "📊 وضعیت سرویس‌ها: sudo systemctl status hamkarhub nginx"
echo "🔄 ری‌استارت سرویس: sudo systemctl restart hamkarhub"
echo "=========================================================="
echo ""
