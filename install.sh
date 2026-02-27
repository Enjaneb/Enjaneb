#!/usr/bin/env bash

# خاموش کردن تمام محدودیت‌های Bash
set +u
set +e

# رنگ‌ها
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

clear
echo -e "${BLUE}################################################################${NC}"
echo -e "${BLUE}#${NC} ${YELLOW}          ENJANEB ULTIMATE - THE UNSTOPPABLE V17            ${NC} ${BLUE}#${NC}"
echo -e "${BLUE}################################################################${NC}"

# --- مرحله ۱: دریافت اطلاعات با پیش‌فرض‌های آماده ---
echo -e "${BLUE}>>>> STEP 1: CONFIGURATION <<<<${NC}"

echo -n "Select Role (1: Kharej, 2: Iran) [1]: "
read CHOICE
# استفاده از مقدار پیش‌فرض اگر کاربر چیزی وارد نکرد
CHOICE=${CHOICE:-1}

echo -n "Admin User [admin]: "
read ADMIN_U
ADMIN_U=${ADMIN_U:-admin}

echo -n "Admin Pass: "
read -s ADMIN_P; echo

# بنادر (Ports)
read -p "HTTP Port [3128]: " P_H; P_H=${P_H:-3128}
read -p "SOCKS5 Port [1080]: " P_S; P_S=${P_S:-1080}
read -p "MTProto Port [8443]: " P_M; P_M=${P_M:-8443}
read -p "Web Panel Port [8088]: " P_W; P_W=${P_W:-8088}
read -p "WireGuard Port [8080]: " P_WG; P_WG=${P_WG:-8080}

K_IP="0.0.0.0"
K_PUB="NONE"

if [ "$CHOICE" = "2" ]; then
    echo -n "Enter Kharej IP: "
    read K_IP
    echo -n "Enter Kharej Public Key: "
    read K_PUB
fi

# --- مرحله ۲: نصب پیش‌نیازها ---
echo -e "${GREEN}[*] Installing dependencies...${NC}"
apt-get update && apt-get install -y ufw fail2ban curl squid dante-server wireguard python3 python3-venv apache2-utils iptables openssl

# --- مرحله ۳: کانفیگ تونل ---
mkdir -p /etc/wireguard
W_PRIV=$(wg genkey); W_PUB=$(echo "$W_PRIV" | wg pubkey)

if [ "$CHOICE" = "1" ]; then
    # کانفیگ خارج
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $W_PRIV
Address = 10.0.0.1/24
ListenPort = $P_WG
PostUp = iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
EOF
else
    # کانفیگ ایران
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $W_PRIV
Address = 10.0.0.2/24
PostUp = ip route add default dev wg0 table 200; ip rule add from 10.0.0.2 table 200
[Peer]
PublicKey = $K_PUB
Endpoint = $K_IP:$P_WG
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
fi
systemctl enable --now wg-quick@wg0

# --- مرحله ۴: ساخت پنل مدیریت (کامل) ---
mkdir -p /opt/enjaneb/backend
python3 -m venv /opt/enjaneb/venv
/opt/enjaneb/venv/bin/pip install fastapi uvicorn[standard] python-multipart

cat > /opt/enjaneb/backend/app.py <<EOF
import os, subprocess
from fastapi import FastAPI, Form, Depends, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials

app = FastAPI()
security = HTTPBasic()

def auth(c: HTTPBasicCredentials = Depends(security)):
    if c.username != "$ADMIN_U" or c.password != "$ADMIN_P": raise HTTPException(401)
    return True

@app.get("/", response_class=HTMLResponse)
async def home(a=Depends(auth)):
    # لود کردن لیست یوزرها
    h_users = []
    if os.path.exists("/etc/squid/enjaneb_htpasswd"):
        with open("/etc/squid/enjaneb_htpasswd", "r") as f: h_users = [l.split(":")[0] for l in f.readlines() if ":" in l]
    
    return f"""
    <html>
    <head>
        <title>ENJANEB V17</title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <style>
            body {{ background: #0f172a; color: white; padding: 50px; font-family: Tahoma; }}
            .card {{ background: #1e293b; border: none; border-radius: 15px; padding: 20px; }}
            .btn-info {{ background: #0ea5e9; color: white; }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1 class="text-info">مدیریت پروکسی انچنب</h1>
            <div class="row mt-4">
                <div class="col-md-4">
                    <div class="card shadow">
                        <h4>وضعیت سرویس</h4><hr>
                        <p>HTTP Port: $P_H</p>
                        <p>SOCKS Port: $P_S</p>
                        <p>MTProto: $P_M</p>
                    </div>
                </div>
                <div class="col-md-8">
                    <div class="card shadow">
                        <h4>افزودن کاربر جدید</h4>
                        <form action="/add" method="post" class="row g-3">
                            <div class="col-md-5"><input name="u" class="form-control" placeholder="نام کاربری"></div>
                            <div class="col-md-5"><input name="p" class="form-control" placeholder="رمز عبور"></div>
                            <div class="col-md-2"><button class="btn btn-info w-100">ثبت</button></div>
                        </form>
                        <hr>
                        <h4>لیست کاربران (HTTP)</h4>
                        {"".join([f'<div class="d-flex justify-content-between p-2 border-bottom border-secondary">{{u}} <a href="/del/{{u}}" class="text-danger">حذف</a></div>' for u in h_users])}
                    </div>
                </div>
            </div>
        </div>
    </body>
    </html>
    """

@app.post
