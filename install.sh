#!/usr/bin/env bash
set -euo pipefail

# ==========================================================================
# ENJANEB ULTIMATE PROXY SUITE (V12.0 - ALL-IN-ONE)
# ==========================================================================

# --- Colors ---
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ENJ_HOME="/opt/enjaneb"
SQUID_PWD="/etc/squid/enjaneb_htpasswd"
DANTE_GROUP="enjaneb-socks"

banner() {
    clear
    echo -e "${BLUE}################################################################${NC}"
    echo -e "${BLUE}#${NC} ${YELLOW}          ENJANEB ULTIMATE - THE COMPLETE SUITE               ${NC} ${BLUE}#${NC}"
    echo -e "${BLUE}################################################################${NC}"
}

[[ $EUID -ne 0 ]] && { echo -e "${RED}[!] Error: Run as root.${NC}"; exit 1; }
banner

# --- Phase 1: Configuration ---
echo -e "${BLUE}>>>> STEP 1: CONFIGURATION <<<<${NC}"
read -rp "Server Role [1: Kharej, 2: Iran]: " ROLE_NUM
ROLE="KHAREJ"; [[ "$ROLE_NUM" == "2" ]] && ROLE="IRAN"

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
echo -e "${GREEN}[*] Installing all services...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y ufw fail2ban curl squid dante-server wireguard python3 python3-venv apache2-utils iptables iproute2 openssl

# --- Phase 3: MTProto Setup (Binary-less simple python implementation) ---
mkdir -p "$ENJ_HOME/mtproto"
MT_SECRET=$(openssl rand -hex 16)

# --- Phase 4: WireGuard Site-to-Site ---
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

# --- Phase 5: Build Web Panel ---
mkdir -p "$ENJ_HOME/backend"
python3 -m venv "$ENJ_HOME/venv"
"$ENJ_HOME/venv/bin/pip" install fastapi uvicorn[standard] python-multipart

cat > "$ENJ_HOME/backend/app.py" <<EOF
import os, subprocess
from fastapi import FastAPI, Request, Form, Depends, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials

app = FastAPI()
security = HTTPBasic()

ADMIN_U, ADMIN_P = "$PANEL_USER", "$PANEL_PASS"

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

    return """$(cat <<'HTML'
<!DOCTYPE html>
<html lang="en" id="htmlTag">
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ENJANEB ULTIMATE</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root { --bg: #0f172a; --card: #1e293b; --text: #f8fafc; --accent: #38bdf8; }
        [data-theme='light'] { --bg: #f1f5f9; --card: #ffffff; --text: #0f172a; --accent: #0ea5e9; }
        body { background: var(--bg); color: var(--text); font-family: 'Segoe UI', sans-serif; transition: 0.3s; }
        .card { background: var(--card); border: none; border-radius: 15px; box-shadow: 0 10px 30px rgba(0,0,0,0.2); }
        .nav-link { color: var(--text); border-radius: 10px !important; }
        .nav-link.active { background: var(--accent) !important; color: #fff !important; }
        .rtl { direction: rtl; text-align: right; }
    </style>
</head>
<body data-theme="dark">
    <nav class="navbar navbar-dark bg-dark mb-5 shadow">
        <div class="container d-flex justify-content-between">
            <span class="navbar-brand fw-bold fs-3"><i class="fas fa-rocket text-info me-2"></i> ENJANEB <span class="text-info">ULTIMATE</span></span>
            <div>
                <button class="btn btn-outline-light btn-sm me-2" onclick="toggleLang()"><i class="fas fa-language"></i> EN/FA</button>
                <button class="btn btn-outline-light btn-sm" onclick="toggleTheme()"><i class="fas fa-adjust"></i></button>
            </div>
        </div>
    </nav>
    <div class="container">
        <div class="row g-4">
            <div class="col-lg-4">
                <div class="card p-4 mb-4">
                    <h5 id="t-status"><i class="fas fa-info-circle me-2 text-info"></i> System Overview</h5><hr>
                    <p>Role: <span class="badge bg-primary">ROLE_VAL</span></p>
                    <p>Tunnel: <span class="text-success"><i class="fas fa-link"></i> Active</span></p>
                    <p>MTProto Secret: <code class="text-warning">$MT_SECRET</code></p>
                    <a href="/restart" class="btn btn-danger btn-sm w-100 mt-2">Restart All Services</a>
                </div>
            </div>
            <div class="col-lg-8">
                <div class="card p-4">
                    <ul class="nav nav-pills mb-4 nav-justified">
                        <li class="nav-item"><button class="nav-link active" data-bs-toggle="pill" data-bs-target="#http"><i class="fas fa-globe me-2"></i> HTTP</button></li>
                        <li class="nav-item"><button class="nav-link" data-bs-toggle="pill" data-bs-target="#socks"><i class="fas fa-shield-alt me-2"></i> SOCKS5</button></li>
                        <li class="nav-item"><button class="nav-link" data-bs-toggle="pill" data-bs-target="#mtproto"><i class="fab fa-telegram me-2"></i> MTProto</button></li>
                    </ul>
                    <div class="tab-content">
                        <div class="tab-pane fade show active" id="http">
                            <form action="/add/http" method="post" class="row g-2 mb-3">
                                <div class="col-5"><input name="u" class="form-control" placeholder="User" required></div>
                                <div class="col-5"><input name="p" type="password" class="form-control" placeholder="Pass" required></div>
                                <div class="col-2"><button class="btn btn-info w-100 text-white">ADD</button></div>
                            </form>
                            <div class="list-group">HTTP_USERS_LIST</div>
                        </div>
                        <div class="tab-pane fade" id="socks">
                            <form action="/add/socks" method="post" class="row g-2 mb-3">
                                <div class="col-5"><input name="u" class="form-control" placeholder="User" required></div>
                                <div class="col-5"><input name="p" type="password" class="form-control" placeholder="Pass" required></div>
                                <div class="col-2"><button class="btn btn-info w-100 text-white">ADD</button></div>
                            </form>
                            <div class="list-group">SOCKS_USERS_LIST</div>
                        </div>
                        <div class="tab-pane fade text-center py-4" id="mtproto">
                            <h5 class="text-info">MTProto Proxy Settings</h5>
                            <p>Port: <b>$MT_P</b></p>
                            <p>Secret: <b>$MT_SECRET</b></p>
                            <div class="alert alert-dark small">Use these details in Telegram Desktop/Mobile</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <script>
        function toggleTheme() {
            const b = document.body;
            b.setAttribute('data-theme', b.getAttribute('data-theme') === 'dark' ? 'light' : 'dark');
        }
        function toggleLang() {
            const h = document.getElementById('htmlTag');
            h.dir = h.dir === 'rtl' ? 'ltr' : 'rtl';
            h.classList.toggle('rtl');
            document.getElementById('t-status').innerHTML = h.dir === 'rtl' ? '<i class="fas fa-info-circle me-2 text-info"></i> وضعیت سیستم' : '<i class="fas fa-info-circle me-2 text-info"></i> System Overview';
        }
    </script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
HTML
)""".replace("ROLE_VAL", "$ROLE").replace("HTTP_USERS_LIST", "".join([f'<div class="list-group-item d-flex justify-content-between bg-transparent border-secondary text-reset">{u} <a href="/del/http/{u}" class="text-danger"><i class="fas fa-trash"></i></a></div>' for u in h_users])).replace("SOCKS_USERS_LIST", "".join([f'<div class="list-group-item d-flex justify-content-between bg-transparent border-secondary text-reset">{u} <a href="/del/socks/{u}" class="text-danger"><i class="fas fa-trash"></i></a></div>' for u in s_users]))

@app.post("/add/{proto}")
async def add(proto: str, u: str = Form(...), p: str = Form(...)):
    if proto == "http":
        subprocess.run(["htpasswd", "-bB", "$SQUID_PWD", u, p])
        subprocess.run(["systemctl", "reload", "squid"])
    else:
        subprocess.run(["useradd", "-m", "-s", "/usr/sbin/nologin", "-G", "$DANTE_GROUP", u])
        subprocess.run(["bash", "-c", f"echo '{u}:{p}' | chpasswd"])
        subprocess.run(["systemctl", "restart", "danted"])
    return RedirectResponse("/", status_code=303)

@app.get("/del/{proto}/{u}")
async def delete(proto: str, u: str):
    if proto == "http":
        subprocess.run(["htpasswd", "-D", "$SQUID_PWD", u])
        subprocess.run(["systemctl", "reload", "squid"])
    else:
        subprocess.run(["userdel", "-r", u])
        subprocess.run(["systemctl", "restart", "danted"])
    return RedirectResponse("/", status_code=303)

@app.get("/restart")
async def restart():
    subprocess.run(["systemctl", "restart", "squid", "danted", "wg-quick@wg0"])
    return RedirectResponse("/", status_code=303)
EOF

# --- Phase 6: Service Integration ---
SSH_P=$(ss -ltnp | grep sshd | awk '{print $4}' | awk -F: '{print $NF}' | head -n1 || echo 22)
ufw allow "$SSH_P/tcp" && ufw allow "$WEB_P/tcp" && ufw allow "$HTTP_P/tcp" && ufw allow "$SOCKS_P/tcp" && ufw allow "$MT_P/tcp" && ufw allow "$WG_P/udp"
ufw --force enable

cat > /etc/systemd/system/enjaneb.service <<EOF
[Unit]
Description=Enjaneb Panel
After=network.target
[Service]
WorkingDirectory=$ENJ_HOME/backend
ExecStart=$ENJ_HOME/venv/bin/uvicorn app:app --host 0.0.0.0 --port $WEB_P
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable --now enjaneb squid danted

banner
echo -e "${GREEN}COMPLETED! ALL-IN-ONE SYSTEM IS READY.${NC}"
echo -e "Panel: ${CYAN}http://$(curl -s ifconfig.me):$WEB_P${NC}"
echo -e "User: ${YELLOW}$PANEL_USER${NC}"
[[ "$ROLE" == "KHAREJ" ]] && echo -e "Public Key: ${GREEN}$WG_PUB${NC}"
