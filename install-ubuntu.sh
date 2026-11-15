#!/bin/bash
# ==============================================================
# اسکریپت نصب و راه‌اندازی خودکار همکار هاب روی سرور اوبونتو
# سازگار با: Ubuntu 20.04 / 22.04 / 24.04 LTS
# ==============================================================
set -e

echo "🚀 در حال آماده‌سازی و نصب سامانه همکار هاب روی سرور اوبونتو..."

# ۱. به‌روزرسانی مخازن اوبونتو
sudo apt-get update -y
sudo apt-get install -y curl ufw unzip git nginx openssl certbot python3-certbot-nginx

# ۲. بررسی و نصب Node.js نسخه ۲۰ LTS
if ! command -v node &> /dev/null; then
    echo "📦 در حال نصب Node.js 20..."
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

# ۳. نصب وابستگی‌های پروژه
echo "📦 در حال نصب پکیج‌های پروژه..."
npm install --legacy-peer-deps

# ۴. کامپایل و بیلد فرانت‌اند با بهینه‌سازی حافظه و ۴ هسته پردازنده
echo "🔨 در حال کامپایل پروژه..."
export UV_THREADPOOL_SIZE=4
NODE_OPTIONS="--max-old-space-size=1536" npm run build

# ۵. باز کردن پورت‌های ۸۰/۴۴۳ و ۳۰۰۰ در فایروال اوبونتو (UFW)
sudo ufw allow 80/tcp || true
sudo ufw allow 443/tcp || true
sudo ufw allow 3000/tcp || true

# ۶. ثبت سرویس خودکار پس‌زمینه در systemd برای اجرای دائمی
CURRENT_DIR=$(pwd)
NODE_EXEC=$(which node)
SERVICE_USER="${SUDO_USER:-$(whoami)}"

echo "⚙️ در حال پیکربندی سرویس daemon در systemd با کاربر $SERVICE_USER..."

sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$CURRENT_DIR" || true

sudo bash -c "cat <<EOF > /etc/systemd/system/hamkarhub.service
[Unit]
Description=HamkarHub Coworking Local Chat and MikroTik Hotspot Server
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$CURRENT_DIR
ExecStart=$NODE_EXEC $CURRENT_DIR/server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=UV_THREADPOOL_SIZE=4
Environment=NODE_OPTIONS=--max-old-space-size=1024

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable hamkarhub.service
sudo systemctl restart hamkarhub.service

# ۷. پیکربندی Nginx به‌عنوان پروکسی روی پورت‌های ۸۰ و ۴۴۳
echo "⚙️ در حال پیکربندی Nginx روی پورت‌های ۸۰ و ۴۴۳..."

sudo bash -c "cat <<'EOF' > /etc/nginx/sites-available/hamkarhub
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    client_max_body_size 12m;

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

sudo rm -f /etc/nginx/sites-enabled/default || true
sudo ln -sf /etc/nginx/sites-available/hamkarhub /etc/nginx/sites-enabled/hamkarhub
if sudo nginx -t; then
    sudo systemctl enable nginx >/dev/null 2>&1 || true
    sudo systemctl restart nginx || true
fi

SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "=========================================================="
echo "🎉 سامانه همکار هاب با موفقیت نصب و فعال شد!"
echo "🌐 آدرس دسترسی در شبکه وای‌فای: http://$SERVER_IP"
echo "🔐 پنل مدیریت ادمین: http://$SERVER_IP (رمز عبور اولیه: admin123)"
echo "🔒 فعال‌سازی SSL (HTTPS روی ۴۴۳): sudo bash setup-ssl.sh"
echo "📌 وضعیت سرویس‌ها: sudo systemctl status hamkarhub nginx"
echo "=========================================================="
