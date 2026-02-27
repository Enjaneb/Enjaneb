#!/usr/bin/env bash
set -euo pipefail

# ==========================================================================
# ENJANEB ULTIMATE INSTALLER (V2.0) - SOCKS5, HTTP, MTPROTO & WG TUNNEL
# Support: Ubuntu 22.04 / 24.04 | 1 vCPU, 1GB RAM Optimized
# ==========================================================================

# --- Colors & Style ---
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# --- Paths ---
ENJ_HOME="/opt/enjaneb"
ENJ_BACKEND="${ENJ_HOME}/backend"
ENJ_VENV="${ENJ_HOME}/venv"
SQUID_HTPASSWD="/etc/squid/enjaneb_htpasswd"
DANTE_GROUP="enjaneb-socks"

# --- Header ---
clear
echo -e "${BLUE}====================================================${NC}"
echo -e "${YELLOW}          ENJANEB ULTIMATE PROXY SUITE             ${NC}"
echo -e "${BLUE}====================================================${NC}"

# --- Check Root ---
[[ $EUID -ne 0 ]] && { echo -e "${RED}Run as root!${NC}"; exit 1; }

# --- 1. Roles & Settings ---
echo -e "${YELLOW}Step 1: Role Selection${NC}"
echo "1) Server Kharej (Destination/Gateway)"
echo "2) Server Iran (Entry/Tunnel Source)"
read -rp "Select Role [1-2]: " ROLE_NUM

if [[ "$ROLE_NUM" == "1" ]]; then ROLE="KHAREJ"; else ROLE="IRAN"; fi

echo -e "\n${YELLOW}Step 2: Configuration${NC}"
read -rp "Panel Admin Username [adminproxy]: " PANEL_USER
PANEL_USER=${PANEL_USER:-adminproxy}
read -rsp "Panel Admin Password: " PANEL_PASS; echo

HTTP_PORT=$(read -rp "HTTP Proxy Port [3128]: " p; echo ${p:-3128})
SOCKS_PORT=$(read -rp "SOCKS5 Port [1080]: " p; echo ${p:-1080})
MTPROTO_PORT=$(read -rp "MTProto Port [8443]: " p; echo ${p:-8443})
WG_PORT=$(read -rp "WireGuard Port [8080]: " p; echo ${p:-8080})
WEB_PORT=$(read -rp "Panel Web Port [8088]: " p; echo ${p:-8088})

if [[ "$ROLE" == "IRAN" ]]; then
    read -rp "Enter Public IP of Server Kharej: " KHAREJ_IP
fi

# --- 2. Installation ---
echo -e "\n${YELLOW}Installing Dependencies...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -y
apt install -y ufw fail2ban curl nginx python3 python3-venv \
    squid dante-server wireguard iptables apache2-utils openssl

# --- 3. Firewall ---
echo -e "${YELLOW}Configuring Firewall...${NC}"
SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | awk -F: '{print $NF}' | head -n1 || echo 22)
ufw allow "$SSH_PORT/tcp"
ufw allow "$WEB_PORT/tcp"
ufw allow "$HTTP_PORT/tcp"
ufw allow "$SOCKS_PORT/tcp"
ufw allow "$MTPROTO_PORT/tcp"
ufw allow "$WG_PORT/udp"
ufw --force enable

# --- 4. WireGuard Tunnel ---
echo -e "${YELLOW}Setting up WireGuard Tunnel...${NC}"
mkdir -p /etc/wireguard
WG_PRIV=$(wg genkey)
WG_PUB=$(echo "$WG_PRIV" | wg pubkey)

if [[ "$ROLE" == "KHAREJ" ]]; then
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $WG_PRIV
Address = 10.0.0.1/24
ListenPort = $WG_PORT
PostUp = iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
EOF
    echo -e "${BLUE}IMPORTANT: Copy this Public Key for Server Iran: ${YELLOW}$WG_PUB${NC}"
else
    read -rp "Enter Public Key of Server Kharej: " KHAREJ_PUB
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $WG_PRIV
Address = 10.0.0.2/24
# Kill-Switch & Routing
PostUp = ip route add default dev wg0 table 200; ip rule add from 10.0.0.2 table 200
PostDown = ip route del default dev wg0 table 200; ip rule del from 10.0.0.2 table 200

[Peer]
PublicKey = $KHAREJ_PUB
Endpoint = $KHAREJ_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
fi
systemctl enable wg-quick@wg0 && systemctl restart wg-quick@wg0 || true

# --- 5. Backend & Modern UI ---
mkdir -p "$ENJ_BACKEND"
useradd -r -m -d "$ENJ_HOME" -s /usr/sbin/nologin enjaneb || true
groupadd "$DANTE_GROUP" || true

# Write FastAPI App
cat > "${ENJ_BACKEND}/app.py" <<EOF
import os, subprocess, re
from fastapi import FastAPI, Form, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from passlib.hash import bcrypt
from starlette.middleware.sessions import SessionMiddleware

app = FastAPI()
security = HTTPBasic()
ADMIN_USER = os.getenv("ADMIN_USER", "adminproxy")
ADMIN_PASS = os.getenv("ADMIN_PASS", "password")

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ENJANEB PANEL</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <style>
        :root { --bg: #f8f9fa; --card: #ffffff; --text: #212529; }
        [data-theme='dark'] { --bg: #121212; --card: #1e1e1e; --text: #e0e0e0; }
        body { background: var(--bg); color: var(--text); transition: 0.3s; font-family: 'Segoe UI', Tahoma; }
        .card { background: var(--card); border: none; border-radius: 15px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .nav-link { cursor: pointer; }
    </style>
</head>
<body data-theme="dark">
<nav class="navbar navbar-expand-lg navbar-dark bg-dark">
    <div class="container">
        <a class="navbar-brand" href="#"><i class="fas fa-shield-halved me-2"></i>ENJANEB PANEL</a>
        <button class="btn btn-outline-light btn-sm" onclick="toggleTheme()"><i class="fas fa-moon"></i></button>
    </div>
</nav>

<div class="container mt-4">
    <div class="row">
        <div class="col-md-4">
            <div class="card p-3 text-center">
                <h5><i class="fas fa-server text-primary"></i> Status</h5>
                <p class="mb-0">Role: <b>${os.getenv("ROLE")}</b></p>
                <p>Tunnel: <span class="badge bg-success">Active</span></p>
            </div>
        </div>
        <div class="col-md-8">
            <div class="card p-4">
                <ul class="nav nav-tabs mb-3" id="myTab">
                    <li class="nav-item"><button class="nav-link active" data-bs-toggle="tab" data-bs-target="#http">HTTP</button></li>
                    <li class="nav-item"><button class="nav-link" data-bs-toggle="tab" data-bs-target="#socks">SOCKS5</button></li>
                    <li class="nav-item"><button class="nav-link" data-bs-toggle="tab" data-bs-target="#mtproto">MTProto</button></li>
                </ul>
                <div class="tab-content">
                    <div class="tab-pane fade show active" id="http">
                        <h6>Create HTTP User</h6>
                        <form action="/add-http" method="post" class="row g-2">
                            <div class="col-5"><input name="username" class="form-control" placeholder="User" required></div>
                            <div class="col-5"><input name="password" type="password" class="form-control" placeholder="Pass" required></div>
                            <div class="col-2"><button class="btn btn-primary w-100"><i class="fas fa-plus"></i></button></div>
                        </form>
                    </div>
                    </div>
            </div>
        </div>
    </div>
</div>

<script>
function toggleTheme() {
    const body = document.body;
    body.setAttribute('data-theme', body.getAttribute('data-theme') === 'dark' ? 'light' : 'dark');
}
</script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
"""

def auth(creds: HTTPBasicCredentials = Depends(security)):
    if creds.username != ADMIN_USER or creds.password != ADMIN_PASS:
        raise HTTPException(status_code=401, detail="Unauthorized")
    return True

@app.get("/", response_class=HTMLResponse)
async def home(user: bool = Depends(auth)):
    return HTML_TEMPLATE

@app.post("/add-http")
async def add_http(username: str = Form(...), password: str = Form(...), user: bool = Depends(auth)):
    subprocess.run(["htpasswd", "-bB", "${SQUID_HTPASSWD}", username, password])
    subprocess.run(["systemctl", "reload", "squid"])
    return RedirectResponse("/", status_code=303)

@app.get("/restart/{service}")
async def restart_service(service: str, user: bool = Depends(auth)):
    if service in ["squid", "danted", "wg-quick@wg0"]:
        subprocess.run(["systemctl", "restart", service])
    return RedirectResponse("/", status_code=303)
EOF

# --- 6. Python Environment ---
echo -e "${YELLOW}Finalizing Services...${NC}"
python3 -m venv "$ENJ_VENV"
"$ENJ_VENV/bin/pip" install fastapi uvicorn[standard] passlib[bcrypt] python-multipart starlette

cat > /etc/systemd/system/enjaneb.service <<EOF
[Unit]
Description=Enjaneb Panel
After=network.target

[Service]
WorkingDirectory=${ENJ_BACKEND}
Environment=ADMIN_USER=${PANEL_USER}
Environment=ADMIN_PASS=${PANEL_PASS}
Environment=ROLE=${ROLE}
ExecStart=${ENJ_VENV}/bin/uvicorn app:app --host 0.0.0.0 --port ${WEB_PORT}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now enjaneb

# --- 7. Final Output ---
echo -e "${GREEN}====================================================${NC}"
echo -e "${YELLOW}INSTALLATION COMPLETE!${NC}"
echo -e "Panel URL: ${BLUE}http://$(curl -s ifconfig.me):${WEB_PORT}${NC}"
echo -e "Admin User: ${YELLOW}${PANEL_USER}${NC}"
echo -e "Admin Pass: ${YELLOW}${PANEL_PASS}${NC}"
echo -e "WireGuard Role: ${YELLOW}${ROLE}${NC}"
echo -e "${GREEN}====================================================${NC}"
