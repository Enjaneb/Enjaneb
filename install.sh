#!/usr/bin/env bash

# --- Basic Config ---
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ENJ_HOME="/opt/enjaneb"
SQUID_PWD="/etc/squid/enjaneb_htpasswd"
DANTE_GROUP="enjaneb-socks"

clear
echo -e "${BLUE}################################################################${NC}"
echo -e "${BLUE}#${NC} ${YELLOW}          ENJANEB ULTIMATE - BUG FIXED VERSION              ${NC} ${BLUE}#${NC}"
echo -e "${BLUE}################################################################${NC}"

# --- Phase 1: Interactive Questions ---
echo -e "${BLUE}>>>> STEP 1: CONFIGURATION <<<<${NC}"
read -rp "Server Role [1: Kharej, 2: Iran]: " ROLE_NUM

# تعریف متغیر ROLE بلافاصله بعد از ورودی برای جلوگیری از خطای unbound
if [[ "$ROLE_NUM" == "2" ]]; then
    FINAL_ROLE="IRAN"
else
    FINAL_ROLE="KHAREJ"
fi

read -rp "Admin User [adminproxy]: " PANEL_USER
PANEL_USER=${PANEL_USER:-adminproxy}
read -rsp "Admin Pass: " PANEL_PASS; echo

HTTP_P=$(read -rp "HTTP Port [3128]: " p; echo ${p:-3128})
SOCKS_P=$(read -rp "SOCKS5 Port [1080]: " p; echo ${p:-1080})
MT_P=$(read -rp "MTProto Port [8443]: " p; echo ${p:-8443})
WG_P=$(read -rp "WireGuard Port [8080]: " p; echo ${p:-8080})
WEB_P=$(read -rp "Web Panel Port [8088]: " p; echo ${p:-8088})

REMOTE_IP=""
REMOTE_PUB=""
if [[ "$FINAL_ROLE" == "IRAN" ]]; then
    read -rp "Server Kharej IP: " REMOTE_IP
    read -rp "Server Kharej Public Key: " REMOTE_PUB
fi

# --- Phase 2: System Install ---
echo -e "${GREEN}[*] Installing dependencies...${NC}"
apt-get update
apt-get install -y ufw fail2ban curl squid dante-server wireguard python3 python3-venv apache2-utils iptables iproute2 openssl

# --- Phase 3: WireGuard Setup ---
mkdir -p /etc/wireguard
WG_PRIV=$(wg genkey); WG_PUB=$(echo "$WG_PRIV" | wg pubkey)

if [[ "$FINAL_ROLE" == "KHAREJ" ]]; then
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
PublicKey = $REMOTE_PUB
Endpoint = $REMOTE_IP:$WG_P
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
fi
systemctl enable --now wg-quick@wg0

# --- Phase 4: Web Panel Build ---
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

U_ADMIN, P_ADMIN = "$PANEL_USER", "$PANEL_PASS"
ROLE_INFO = "$FINAL_ROLE"

def check_auth(credentials: HTTPBasicCredentials = Depends(security)):
    if credentials.username != U_ADMIN or credentials.password != P_ADMIN:
        raise HTTPException(status_code=401)
    return True

@app.get("/", response_class=HTMLResponse)
async def home(auth: bool = Depends(check_auth)):
    h_users = []
    if os.path.exists("$SQUID_PWD"):
        with open("$SQUID_PWD", "r") as f:
            h_users = [l.split(":")[0] for l in f.readlines() if ":" in l]
    
    s_out = subprocess.run(["getent", "group", "$DANTE_GROUP"], capture_output=True, text=True).stdout
    s_users = s_out.strip().split(":")[-1].split(",") if ":" in s_out else []
    s_users = [x for x in s_users if x]

    return f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8"><title>ENJANEB PANEL</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        body {{ background: #0f172a; color: #f8fafc; font-family: sans-serif; transition: 0.3s; }}
        .card {{ background: #1e293b; border: none; border-radius: 12px; }}
        .nav-link.active {{ background: #38bdf8 !important; }}
    </style>
</head>
<body class="p-4">
    <div class="container">
        <div class="d-flex justify-content-between align-items-center mb-4">
            <h2 class="text-info fw-bold">ENJANEB ULTIMATE</h2>
            <span class="badge bg-primary fs-6">Role: {{ROLE_INFO}}</span>
        </div>
        <div class="row g-4">
            <div class="col-md-4">
                <div class="card p-3 shadow">
                    <h5><i class="fas fa-signal me-2"></i> Service Status</h5><hr>
                    <p>MTProto: <span class="text-info">$MT_P</span></p>
                    <p>Tunnel: <span class="text-success">Connected</span></p>
                    <a href="/restart" class="btn btn-sm btn-outline-danger w-100">Restart Services</a>
                </div>
            </div>
            <div class="col-md-8">
                <div class="card p-4 shadow">
                    <ul class="nav nav-pills mb-3">
                        <li class="nav-item"><button class="nav-link active" data-bs-toggle="pill" data-bs-target="#h_tab">HTTP</button></li>
                        <li class="nav-item"><button class="nav-link" data-bs-toggle="pill" data-bs-target="#s_tab">SOCKS5</button></li>
                    </ul>
                    <div class="tab-content">
                        <div class="tab-pane fade show active" id="h_tab">
                            <form action="/add/http" method="post" class="row g-2 mb-3">
                                <div class="col-5"><input name="u" class="form-control bg-dark text-white border-secondary" placeholder="User" required></div>
                                <div class="col-5"><input name="p" class="form-control bg-dark text-white border-secondary" placeholder="Pass" required></div>
                                <div class="col-2"><button class="btn btn-info w-100 text-white">ADD</button></div>
                            </form>
                            <div class="list-group">
                                {"".join([f'<div class="list-group-item bg-transparent border-secondary text-white d-flex justify-content-between align-items-center">{u} <a href="/del/http/{u}" class="text-danger"><i class="fas fa-trash"></i></a></div>' for u in h_users])}
                            </div>
                        </div>
                        <div class="tab-pane fade" id="s_tab">
                            <form action="/add/socks" method="post" class="row g-2 mb-3">
                                <div class="col-5"><input name="u" class="form-control bg-dark text-white border-secondary" placeholder="User" required></div>
                                <div class="col-5"><input name="p" class="form-control bg-dark text-white border-secondary" placeholder="Pass" required></div>
                                <div class="col-2"><button class="btn btn-info w-100 text-white">ADD</button></div>
                            </form>
                            <div class="list-group">
                                {"".join([f'<div class="list-group-item bg-transparent border-secondary text-white d-flex justify-content-between align-items-center">{u} <a href="/del/socks/{u}" class="text-danger"><i class="fas fa-trash"></i></a></div>' for u in s_users])}
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
    """

@app.post("/add/{{proto}}")
async def add_user(proto: str, u: str = Form(...), p: str = Form(...)):
    if proto == "http":
        subprocess.run(["htpasswd", "-bB", "$SQUID_PWD", u, p])
        subprocess.run(["systemctl", "reload", "squid"])
    else:
        subprocess.run(["useradd", "-m", "-s", "/usr/sbin/nologin", "-G", "$DANTE_GROUP", u])
        subprocess.run(["bash", "-c", f"echo '{{u}}:{{p}}' | chpasswd"])
        subprocess.run(["systemctl", "restart", "danted"])
    return RedirectResponse("/", status_code=303)

@app.get("/del/{{proto}}/{{u}}")
async def del_user(proto: str, u: str):
    if proto == "http":
        subprocess.run(["htpasswd", "-D", "$SQUID_PWD", u])
        subprocess.run(["systemctl", "reload", "squid"])
    else:
        subprocess.run(["userdel", "-r", u])
        subprocess.run(["systemctl", "restart", "danted"])
    return RedirectResponse("/", status_code=303)

@app.get("/restart")
async def restart_srv():
    subprocess.run(["systemctl", "restart", "squid", "danted", "wg-quick@wg0"])
    return RedirectResponse("/", status_code=303)
EOF

# --- Phase 5: Services & Firewall ---
SSH_P=$(ss -ltnp | grep
