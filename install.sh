#!/usr/bin/env bash
# set -e حذف شد تا در صورت خطاهای کوچک نصب متوقف نشود

# --- Colors ---
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ENJ_HOME="/opt/enjaneb"
SQUID_PWD="/etc/squid/enjaneb_htpasswd"
DANTE_GROUP="enjaneb-socks"

clear
echo -e "${BLUE}################################################################${NC}"
echo -e "${BLUE}#${NC} ${YELLOW}          ENJANEB ULTIMATE - BUG FIXED VERSION              ${NC} ${BLUE}#${NC}"
echo -e "${BLUE}################################################################${NC}"

[[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Error: Run as root.${NC}"; exit 1; }

# --- Phase 1: Configuration ---
echo -e "${BLUE}>>>> STEP 1: CONFIGURATION <<<<${NC}"
read -rp "Server Role [1: Kharej, 2: Iran]: " ROLE_NUM
if [[ "$ROLE_NUM" == "2" ]]; then
    ROLE="IRAN"
else
    ROLE="KHAREJ"
fi

read -rp "Admin User [adminproxy]: " PANEL_USER
PANEL_USER=${PANEL_USER:-adminproxy}
read -rsp "Admin Pass: " PANEL_PASS; echo

HTTP_P=$(read -rp "HTTP Port [3128]: " p; echo ${p:-3128})
SOCKS_P=$(read -rp "SOCKS5 Port [1080]: " p; echo ${p:-1080})
MT_P=$(read -rp "MTProto Port [8443]: " p; echo ${p:-8443})
WG_P=$(read -rp "WireGuard Port [8080]: " p; echo ${p:-8080})
WEB_P=$(read -rp "Web Panel Port [8088]: " p; echo ${p:-8088})

K_IP=""; K_PUB=""
if [[ "$ROLE" == "IRAN" ]]; then
    read -rp "Server Kharej IP: " K_IP
    read -rp "Server Kharej Public Key: " K_PUB
fi

# --- Phase 2: Core Install ---
echo -e "${GREEN}[*] Installing packages...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ufw fail2ban curl squid dante-server wireguard python3 python3-venv apache2-utils iptables iproute2 openssl

# --- Phase 3: WireGuard ---
mkdir -p /etc/wireguard
WG_PRIV=$(wg genkey); WG_PUB=$(echo "$WG_PRIV" | wg pubkey)
if [[ "$ROLE" == "KHAREJ" ]]; then
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $WG_PRIV
Address = 10.0.0.1/24
ListenPort = $WG_P
PostUp = iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
EOF
else
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $WG_PRIV
Address = 10.0.0.2/24
PostUp = ip route add default dev wg0 table 200; ip rule add from 10.0.0.2 table 200; iptables -I FORWARD -i eth0 ! -o wg0 -j REJECT
[Peer]
PublicKey = $K_PUB
Endpoint = $K_IP:$WG_P
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
fi
systemctl enable --now wg-quick@wg0

# --- Phase 4: Web Panel Backend ---
mkdir -p "$ENJ_HOME/backend"
python3 -m venv "$ENJ_HOME/venv"
"$ENJ_HOME/venv/bin/pip" install fastapi uvicorn[standard] python-multipart

# ایجاد سورس کد پایتون با متغیرهای ثابت شده
cat > "$ENJ_HOME/backend/app.py" <<EOF
import os, subprocess
from fastapi import FastAPI, Request, Form, Depends, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials

app = FastAPI()
security = HTTPBasic()

ADMIN_U, ADMIN_P = "$PANEL_USER", "$PANEL_PASS"
MY_ROLE = "$ROLE"

def get_auth(credentials: HTTPBasicCredentials = Depends(security)):
    if credentials.username != ADMIN_U or credentials.password != ADMIN_P:
        raise HTTPException(status_code=401)
    return True

@app.get("/", response_class=HTMLResponse)
async def dashboard(auth: bool = Depends(get_auth)):
    h_users = []
    if os.path.exists("$SQUID_PWD"):
        with open("$SQUID_PWD", "r") as f:
            h_users = [line.split(":")[0] for line in f.readlines() if ":" in line]
    
    s_out = subprocess.run(["getent", "group", "$DANTE_GROUP"], capture_output=True, text=True).stdout
    s_users = s_out.strip().split(":")[-1].split(",") if ":" in s_out else []
    s_users = [x for x in s_users if x]

    html_content = """$(cat <<'HTML'
<!DOCTYPE html>
<html lang="en" id="htmlTag">
<head>
    <meta charset="UTF-8">
    <title>ENJANEB ULTIMATE</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root { --bg: #0f172a; --card: #1e293b; --text: #f8fafc; --accent: #38bdf8; }
        [data-theme='light'] { --bg: #f1f5f9; --card: #ffffff; --text: #0f172a; --accent: #0ea5e9; }
        body { background: var(--bg); color: var(--text); transition: 0.3s; font-family: sans-serif; }
        .card { background: var(--card); border: none; border-radius: 15px; }
        .nav-link.active { background: var(--accent) !important; }
    </style>
</head>
<body data-theme="dark" class="p-3">
    <nav class="navbar navbar-dark bg-dark mb-4 rounded shadow">
        <div class="container">
            <span class="navbar-brand fw-bold">ENJANEB <span class="text-info">ULTIMATE</span></span>
            <button class="btn btn-outline-light btn-sm" onclick="document.body.setAttribute('data-theme', document.body.getAttribute('data-theme') === 'dark' ? 'light' : 'dark')">Theme</button>
        </div>
    </nav>
    <div class="container">
        <div class="row g-4">
            <div class="col-md-4">
                <div class="card p-3">
                    <h5>Status</h5><hr>
                    <p>Role: <span class="badge bg-info">ROLE_PLACEHOLDER</span></p>
                    <p>MTProto: Port $MT_P</p>
                </div>
            </div>
            <div class="col-md-8">
                <div class="card p-4">
                    <ul class="nav nav-pills mb-3">
                        <li class="nav-item"><button class="nav-link active" data-
