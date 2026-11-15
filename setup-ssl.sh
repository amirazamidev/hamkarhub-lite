#!/usr/bin/env bash
# ==============================================================
# 🔒 HamkarHub SSL Installer
# فعال‌سازی HTTPS روی پورت ۴۴۳ برای سرویس همکار هاب
# پشتیبانی از Let's Encrypt (گواهی معتبر) و self-signed (خودامضا)
# ==============================================================
set -e

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
echo "  🔒 نصب گواهی SSL برای همکار هاب (پورت ۴۴۳)"
echo "=========================================================="
echo ""

MODE="le"          # le = Let's Encrypt | self = خودامضا
DOMAIN=""
EMAIL=""
SSL_DIR="/etc/ssl/hamkarhub"
NGINX_SITE="/etc/nginx/sites-available/hamkarhub"
NGINX_SSL_SITE="/etc/nginx/sites-available/hamkarhub-ssl"

usage() {
    echo "راهنمای استفاده:"
    echo "  sudo bash setup-ssl.sh                      # حالت تعاملی (پرسش از دامنه)"
    echo "  sudo bash setup-ssl.sh --domain hub.example.com --email admin@example.com"
    echo "  sudo bash setup-ssl.sh --self-signed        # ساخت گواهی خودامضا (بدون دامنه)"
    echo ""
    echo "توجه: Let's Encrypt نیازمند دامنه‌ای است که به آی‌پی عمومی این سرور اشاره کند."
}

while [ $# -gt 0 ]; do
    case "$1" in
        --self-signed) MODE="self"; shift;;
        --domain) DOMAIN="$2"; shift 2;;
        --domain=*) DOMAIN="${1#*=}"; shift;;
        --email) EMAIL="$2"; shift 2;;
        --email=*) EMAIL="${1#*=}"; shift;;
        -h|--help) usage; exit 0;;
        *) echo "❌ آرگومان ناشناخته: $1"; usage; exit 1;;
    esac
done

# نصب پیش‌نیازها در صورت نیاز
if ! command -v nginx &> /dev/null || ! command -v certbot &> /dev/null; then
    echo "📦 در حال نصب nginx و certbot..."
    $SUDO apt-get update -y
    $SUDO apt-get install -y nginx openssl certbot python3-certbot-nginx
fi

if [ "$MODE" = "le" ] && [ -z "$DOMAIN" ]; then
    echo "برای دریافت گواهی معتبر به دامنه نیاز است."
    read -r -p "دامنه (مثال: hub.example.com) — برای انصراف Enter بزنید: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        echo "⚠️ دامنه‌ای وارد نشد؛ گواهی خودامضا (self-signed) ساخته می‌شود."
        MODE="self"
    fi
fi

if [ "$MODE" = "le" ]; then
    if [ -z "$EMAIL" ]; then
        read -r -p "ایمیل (برای هشدارهای Let's Encrypt) [admin@${DOMAIN}]: " EMAIL
        EMAIL="${EMAIL:-admin@$DOMAIN}"
    fi

    echo "🔐 در حال دریافت گواهی Let's Encrypt برای دامنه ${DOMAIN} ..."
    if $SUDO certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect; then
        echo "✅ گواهی معتبر نصب شد و HTTP به HTTPS هدایت می‌شود."
    else
        echo "❌ دریافت گواهی Let's Encrypt ناموفق بود (بررسی کنید دامنه به این سرور اشاره می‌کند و پورت ۸۰ باز است)."
        echo "   می‌توانید با گزینه --self-signed یک گواهی خودامضا بسازید."
        exit 1
    fi
else
    CN="${DOMAIN:-$(hostname -f 2>/dev/null || hostname)}"
    echo "🔐 در حال ساخت گواهی خودامضا برای ${CN} ..."
    $SUDO mkdir -p "$SSL_DIR"
    $SUDO openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$SSL_DIR/privkey.pem" \
        -out "$SSL_DIR/fullchain.pem" \
        -subj "/C=IR/O=HamkarHub/CN=${CN}"

    echo "⚙️ در حال افزودن بلوک HTTPS به Nginx..."
    $SUDO bash -c "cat <<'EOF' > $NGINX_SSL_SITE
# HamkarHub HTTPS (self-signed) -> Node app on 127.0.0.1:3000
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;

    ssl_certificate $SSL_DIR/fullchain.pem;
    ssl_certificate_key $SSL_DIR/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

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
        proxy_read_timeout 3600s;
    }
}
EOF"

    $SUDO ln -sf "$NGINX_SSL_SITE" /etc/nginx/sites-enabled/hamkarhub-ssl
    echo "✅ گواهی خودامضا ساخته شد و HTTPS فعال گردید."
    echo "ℹ️ مرورگرها به این گواهی هشدار «not trusted» می‌دهند که طبیعی است."
fi

if $SUDO nginx -t; then
    $SUDO systemctl reload nginx || $SUDO systemctl restart nginx
else
    echo "❌ پیکربندی Nginx نامعتبر است. لطفاً خطاها را بررسی کنید."
    exit 1
fi

# باز کردن پورت ۴۴۳ در فایروال
$SUDO ufw allow 443/tcp 2>/dev/null || true

SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "=========================================================="
echo "🎉 SSL با موفقیت نصب شد!"
echo "   https://${DOMAIN:-$SERVER_IP}"
echo "=========================================================="
echo ""
