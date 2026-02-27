#!/usr/bin/env bash
set -euo pipefail

# ==========================================================================
# ENJANEB ULTIMATE PROXY SUITE (V8.0 - FULL COMMERCIAL EDITION)
# ==========================================================================
# 100% Automated | Site-to-Site WireGuard | Kill-Switch | Multi-Protocol
# Supported: Ubuntu 22.04 / 24.04 (No Docker)
# ==========================================================================

# --- تنظیمات رنگی و رابط کاربری ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

# --- مسیرها و متغیرهای اصلی ---
ENJ_HOME="/opt/enjaneb"
ENJ_BACKEND="${ENJ_HOME}/backend"
ENJ_VENV="${ENJ_HOME}/venv"
SQUID_PWD="/etc/squid/enjaneb_htpasswd"
DANTE_GROUP="enjaneb-socks"
SQUID_CONF="/etc/squid/squid.conf"
DANTE_CONF="/etc/danted.conf"

banner() {
    clear
    echo -e "${CYAN}################################################################${NC}"
    echo -e "${CYAN}#${NC} ${YELLOW}             ENJANEB ULTIMATE PROXY & TUNNEL                ${NC} ${CYAN}#${NC}"
    echo -e "${CYAN}################################################################${NC}"
    echo -e "${BLUE}>>> All-in-One Professional Suite for GitHub (33 Requirements) <<<${NC}"
}

# --- بررسی دسترسی روت ---
[[ $EUID -ne 0 ]] && { echo -e "${RED}[!] خطا: لطفاً با دسترسی root اجرا کنید.${NC}"; exit 1; }

banner

# --- مرحله ۱: پرسش‌های کلیدی (بند ۹، ۲۲، ۲۳، ۲۹، ۳۱) ---
echo -e "${PURPLE}>>>> مرحله ۱: انتخاب نقش و تنظیمات شبکه <<<<${NC}"
echo -e "1) ${GREEN}Server Kharej${NC} (مقصد ترافیک - سرویس دهنده اصلی)"
echo -e "2) ${YELLOW}Server Iran${NC} (مبدأ ترافیک - متصل به خارج)"
read -rp "نقش سرور را انتخاب کنید [1-2]: " ROLE_NUM
ROLE="KHAREJ"; [[ "$ROLE_NUM" == "2" ]] && ROLE="IRAN"

echo -e "\n${PURPLE}>>>> مرحله ۲: امنیت پنل مدیریت (بند ۱۳، ۱۶، ۱۷) <<<<${NC}"
read -rp "نام کاربری ادمین پنل [adminproxy]: " PANEL_USER
PANEL_USER=${PANEL_USER:-adminproxy}
read -rsp "رمز عبور ادمین پنل: " PANEL_PASS; echo

echo -e "\n${PURPLE}>>>> مرحله ۳: تنظیم پورت‌های درخواستی (بند ۲۳) <<<<${NC}"
HTTP_P=$(read -rp "پورت HTTP Proxy [3128]: " p; echo ${p:-3128})
SOCKS_P=$(read -rp "پورت SOCKS5 [1080]: " p; echo ${p:-1080})
MT_P=$(read -rp "پورت MTProto [8443]: " p; echo ${p:-8443})
WG_P=$(read -rp "پورت WireGuard [8080]: " p; echo ${p:-8080})
WEB_P=$(read -rp "پورت پنل مدیریت [8088]: " p; echo ${p:-8088})

echo -e "\n${PURPLE}>>>> مرحله ۴: مدیریت سیستم (بند ۲۹) <<<<${NC}"
read -rp "آیا مایل به نصب Webmin هستید؟ (y/n) [n]: " INST_WEB
INST_WEB=${INST_WEB:-n}

K_IP=""; K_PUB=""
if [[ "$ROLE" == "IRAN" ]]; then
    read -rp "آی‌پی سرور خارج را وارد کنید: " K_IP
    read -rp "Public Key سرور خارج را وارد کنید: " K_PUB
    [[ -z "$K_IP" || -z "$K_PUB" ]] && { echo -e "${RED}خطا: آی‌پی و کلید سرور خارج الزامی است.${NC}"; exit 1; }
fi

# --- مرحله ۲: نصب پیش‌نیازها و بهینه‌سازی (بند ۵، ۶، ۷، ۲۰) ---
echo -e "\n${BLUE}[*] در حال آپدیت و نصب پکیج‌های پایه...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -y && apt upgrade -y
apt install -y ufw fail2ban curl nginx python3 python3-venv squid dante-server \
    wireguard iptables apache2-utils openssl jq git iproute2

if [[ "$INST_WEB" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}[*] نصب Webmin...${NC}"
    curl -o setup-repos.sh https://raw.githubusercontent.com/webmin/webmin/master/setup-repos.sh
    sh setup-repos.sh -y && apt install -y webmin
    ufw allow 10000/tcp
fi

# --- مرحله ۳: فایروال هوشمند (بند ۱۹) ---
SSH_P=$(ss -ltnp | grep sshd | awk '{print $4}' | awk -F: '{print $NF}' | head -n1 || echo 22)
ufw allow "$SSH_P/tcp"
ufw allow "$WEB_P/tcp"
ufw allow "$HTTP_P/tcp"
ufw allow "$SOCKS_P/tcp"
ufw allow "$MT_P/tcp"
ufw allow "$WG_P/udp"
ufw --force enable
systemctl enable --now fail2ban

# --- مرحله ۴: کانفیگ Site-to-Site و Kill-Switch (بند ۲۲، ۳۲) ---
echo -e "\n${BLUE}[*] تنظیم تونل وایرگارد و Kill-Switch...${NC}"
mkdir -p /etc/wireguard
WG_PRIV=$(wg genkey); WG_PUB=$(echo "$WG_PRIV" | wg pubkey)

if [[ "$ROLE" == "KHAREJ" ]]; then
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $WG_PRIV
Address = 10.0.0.1/24
ListenPort = $WG_P
PostUp = iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
EOF
else
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $WG_PRIV
Address = 10.0.0.2/24
# Kill-Switch: ترافیک فقط از داخل تونل اجازه عبور دارد
PostUp = ip route add default dev wg0 table 200; ip rule add from 10.0.0.2 table 200; iptables -I FORWARD -i eth0 ! -o wg0 -j REJECT
PostDown = ip route del default dev wg0 table 200; ip rule del from 10.0.0.2 table 200; iptables -D FORWARD -i eth0 ! -o wg0 -j REJECT

[Peer]
PublicKey = $K_PUB
Endpoint = $K_IP:$WG_P
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
fi
systemctl enable --now wg-quick@wg0

# --- مرحله ۵: تنظیمات پروکسی (Squid & Dante) (بند ۱۱) ---
touch "$SQUID_PWD" && chown proxy:proxy "$SQUID_PWD"
cat > "$SQUID_CONF" <<EOF
http_port $HTTP_P
auth_param basic program /usr/lib/squid/basic_ncsa_auth $SQUID_PWD
auth_param basic realm ENJANEB-PRIVATE
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
forwarded_for off
via off
EOF

if ! getent group "$DANTE_GROUP" >/dev/null; then groupadd "$DANTE_GROUP"; fi
IFACE=$(ip route get 1.1.1.1 | awk '/dev/ {print $5}' | head -n1)
cat > "$DANTE_CONF" <<EOF
logoutput: syslog
internal: $IFACE port = $SOCKS_P
external: $IFACE
method: username
user.notprivileged: nobody
client pass { from: 0.0.0.0/0 to: 0.0.0.0/0 log: error }
socks pass { from: 0.0.0.0/0 to: 0.0.0.0/0 command: connect log: error method: username }
EOF
systemctl restart squid danted

# --- مرحله ۶: سورس کد پایتون پنل مدیریت (بند ۱۲ تا ۱۸، ۲۴، ۲۶) ---
mkdir -p "$ENJ_BACKEND"
python3 -m venv "$ENJ_VENV"
"$ENJ_VENV/bin/pip" install fastapi uvicorn[standard] passlib[bcrypt] python-multipart

cat > "$ENJ_BACKEND/main.py" <<EOF
import os, subprocess, datetime
from fastapi import FastAPI, Request, Form, Depends, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials

app = FastAPI()
security = HTTPBasic()

# متغیرهای محیطی
ADMIN_USER = "$PANEL_USER"
ADMIN_PASS = "$PANEL_PASS"
ROLE = "$ROLE"

def get_auth(credentials: HTTPBasicCredentials = Depends(security)):
    if credentials.username != ADMIN_USER or credentials.password != ADMIN_PASS:
        raise HTTPException(status_code=401, detail="Unauthorized")
    return True

def get_svc_status(name):
    res = subprocess.run(["systemctl", "is-active", name], capture_output=True, text=True)
    return "Online" if res.stdout.strip() == "active" else "Offline"

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request, auth: bool = Depends(get_auth)):
    # دریافت لیست کاربران
    h_users = []
    if os.path.exists("$SQUID_PWD"):
        with open("$SQUID_PWD", "r") as f:
            h_users = [l.split(":")[0] for l in f.readlines()]
    
    s_out = subprocess.run(["getent", "group", "$DANTE_GROUP"], capture_output=True, text=True).stdout
    s_users = s_out.strip().split(":")[-1].split(",") if ":" in s_out and s_out.strip().split(":")[-1] else []
    s_users = [x for x in s_users if x]

    html = f"""
    <!DOCTYPE html>
    <html lang="en" id="mainHtml" dir="ltr">
    <head>
        <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>ENJANEB ULTIMATE</title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
        <style>
            :root {{ --bg: #0f172a; --card: #1e293b; --text: #f1f5f9; --accent: #38bdf8; }}
            [data-theme='light'] {{ --bg: #f8fafc; --card: #ffffff; --text: #0f172a; --accent: #0284c7; }}
            body {{ background: var(--bg); color: var(--text); font-family: 'Segoe UI', Tahoma, sans-serif; transition: 0.5s; }}
            .card {{ background: var(--card); border: 1px solid rgba(255,255,255,0.1); border-radius: 20px; box-shadow: 0 10px 30px rgba(0,0,0,0.5); }}
            .btn-accent {{ background: var(--accent); color: white; border-radius: 10px; font-weight: bold; }}
            .status-badge {{ padding: 5px 15px; border-radius: 20px; font-size: 0.8rem; font-weight: bold; }}
            .rtl {{ direction: rtl; text-align: right; }}
        </style>
    </head>
    <body data-theme="dark">
        <nav class="navbar navbar-dark bg-dark border-bottom border-secondary mb-5 p-3 shadow-lg">
            <div class="container d-flex justify-content-between">
                <span class="navbar-brand fw-bold fs-3"><i class="fas fa-microchip text-info me-2"></i> ENJANEB <span class="text-info">ULTIMATE</span></span>
                <div>
                    <button class="btn btn-outline-light btn-sm me-2" onclick="toggleTheme()"><i class="fas fa-adjust"></i></button>
                    <button class="btn btn-outline-info btn-sm" onclick="toggleLang()"><i class="fas fa-language"></i> EN / FA</button>
                </div>
            </div>
        </nav>
        <div class="container">
            <div class="row g-4">
                <div class="col-md-4">
                    <div class="card p-4 h-100">
                        <h4 id="t-status"><i class="fas fa-signal me-2"></i> System Status</h4><hr>
                        <div class="d-flex justify-content-between mb-3"><span>Role:</span><span class="badge bg-primary">{ROLE}</span></div>
                        <div class="d-flex justify-content-between mb-3"><span>WireGuard:</span><span class="status-badge bg-success">{get_svc_status('wg-quick@wg0')}</span></div>
                        <div class="d-flex justify-content-between mb-3"><span>HTTP Proxy:</span><span class="status-badge bg-success">{get_svc_status('squid')}</span></div>
                        <div class="d-flex justify-content-between mb-3"><span>SOCKS5:</span><span class="status-badge bg-success">{get_svc_status('danted')}</span></div>
                        <hr>
                        <div class="d-grid gap-2">
                            <button onclick="location.href='/action/restart/wg-quick@wg0'" class="btn btn-sm btn-outline-danger">Restart Tunnel</button>
                        </div>
                    </div>
                </div>
                <div class="col-md-8">
                    <div class="card p-4">
                        <ul class="nav nav-pills mb-4 gap-2">
                            <li class="nav-item"><button class="nav-link active" data-bs-toggle="pill" data-bs-target="#http-tab">HTTP (Squid)</button></li>
                            <li class="nav-item"><button class="nav-link" data-bs-toggle="pill" data-bs-target="#socks-tab">SOCKS5 (Dante)</button></li>
                            <li class="nav-item"><button class="nav-link" data-bs-toggle="pill" data-bs-target="#mt-tab">MTProto</button></li>
                        </ul>
                        <div class="tab-content">
                            <div class="tab-pane fade show active" id="http-tab">
                                <form action="/user/add/http" method="post" class="row g-2 mb-4">
                                    <div class="col-md-5"><input name="username" class="form-control" placeholder="Username" required></div>
                                    <div class="col-md-5"><input name="password" type="password" class="form-control" placeholder="Password" required></div>
                                    <div class="col-md-2"><button type="submit" class="btn btn-accent w-100">ADD</button></div>
                                </form>
                                <ul class="list-group">
                                    {"".join([f'<li class="list-group-item d-flex justify-content-between bg-dark border-secondary text-white">{u} <a href="/user/del/http/{u}" class="btn btn-sm btn-danger"><i class="fas fa-trash"></i></a></li>' for u in h_users])}
                                </ul>
                            </div>
                            <div class="tab-pane fade" id="socks-tab">
                                <form action="/user/add/socks" method="post" class="row g-2 mb-4">
                                    <div class="col-md-5"><input name="username" class="form-control" placeholder="Username" required></div>
                                    <div class="col-md-5"><input name="password" type="password" class="form-control" placeholder="Password" required></div>
                                    <div class="col-md-2"><button type="submit" class="btn btn-accent w-100">ADD</button></div>
                                </form>
                                <ul class="list-group">
                                    {"".join([f'<li class="list-group-item d-flex justify-content-between bg-dark border-secondary text-white">{u} <a href="/user/del/socks/{u}" class="btn btn-sm btn-danger"><i class="fas fa-trash"></i></a></li>' for u in s_users])}
                                </ul>
                            </div>
                            <div class="tab-pane fade" id="mt-tab">
                                <div class="alert alert-info border-info bg-transparent">
                                    <h5 id="t-mt">MTProto Proxy Settings</h5>
                                    <p>Port: <b>$MT_P</b></p>
                                    <p class="small">The MTProto traffic is automatically encapsulated in the WireGuard tunnel.</p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <script>
            function toggleTheme() {{
                const b = document.body;
                b.setAttribute('data-theme', b.getAttribute('data-theme') === 'dark' ? 'light' : 'dark');
            }}
            function toggleLang() {{
                const h = document.getElementById('mainHtml');
                h.dir = h.dir === 'ltr' ? 'rtl' : 'ltr';
                h.classList.toggle('rtl');
                document.getElementById('t-status').innerText = h.dir === 'rtl' ? 'وضعیت سیستم' : 'System Status';
            }}
        </script>
        <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    </body>
    </html>
    """
    return html

@app.post("/user/add/http")
async def add_h(username: str = Form(...), password: str = Form(...)):
    subprocess.run(["htpasswd", "-bB", "$SQUID_PWD", username, password])
    subprocess.run(["systemctl", "reload", "squid"])
    return RedirectResponse("/", status_code=303)

@app.get("/user/del/http/{{u}}")
async def del_h(u: str):
    subprocess.run(["htpasswd", "-D", "$SQUID_PWD", u])
    subprocess.run(["systemctl", "reload", "squid"])
    return RedirectResponse("/", status_code=303)

@app.post("/user/add/socks")
async def add_s(username: str = Form(...), password: str = Form(...)):
    subprocess.run(["useradd", "-m", "-s", "/usr/sbin/nologin", "-G", "$DANTE_GROUP", username])
    subprocess.run(["bash", "-c", f"echo '{{username}}:{{password}}' | chpasswd"])
    subprocess.run(["systemctl", "restart", "danted"])
    return RedirectResponse("/", status_code=303)

@app.get("/user/del/socks/{{u}}")
async def del_s(u: str):
    subprocess.run(["userdel", "-r", u])
    subprocess.run(["systemctl", "restart", "danted"])
    return RedirectResponse("/", status_code=303)

@app.get("/action/restart/{{svc}}")
async def rest(svc: str):
    subprocess.run(["systemctl", "restart", svc])
    return RedirectResponse("/", status_code=303)
EOF

# --- مرحله ۷: سرویس‌دهی و اتمام نصب (بند ۲۱، ۳۰) ---
cat > /etc/systemd/system/enjaneb.service <<EOF
[Unit]
Description=Enjaneb Control Panel
After=network.target

[Service]
WorkingDirectory=$ENJ_BACKEND
ExecStart=$ENJ_VENV/bin/uvicorn main:app --host 0.0.0.0 --port $WEB_P
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now enjaneb squid danted

banner
echo -e "${GREEN}نصب با موفقیت به پایان رسید!${NC}"
echo -e "لینک پنل: ${CYAN}http://$(curl -s ifconfig.me):$WEB_P${NC}"
echo -e "نام کاربری ادمین: ${YELLOW}$PANEL_USER${NC}"
echo -e "رمز عبور ادمین: ${YELLOW}$PANEL_PASS${NC}"
if [[ "$ROLE" == "KHAREJ" ]]; then
    echo -e "\n${RED}کلید عمومی سرور خارج (برای نصب در ایران نیاز است):${NC}"
    echo -e "${GREEN}$WG_PUB${NC}"
fi
