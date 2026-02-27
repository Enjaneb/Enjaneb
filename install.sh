#!/usr/bin/env bash

# --- Configuration & Colors ---
C_BLUE='\033[0;34m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[0;31m'; C_NC='\033[0m'
INSTALL_DIR="/opt/enjaneb"
SQUID_USERS="/etc/squid/enjaneb_htpasswd"
DANTE_GROUP="enjaneb-socks"

clear
echo -e "${C_BLUE}################################################################${C_NC}"
echo -e "${C_BLUE}#${C_NC} ${C_YELLOW}          ENJANEB ULTIMATE - NO-BUG VERSION                ${C_NC} ${C_BLUE}#${C_NC}"
echo -e "${C_BLUE}################################################################${C_NC}"

# --- Step 1: Manual Input (Fixed) ---
echo -e "${C_BLUE}>>>> STEP 1: SERVER CONFIG <<<<${C_NC}"
echo -n "Select Role (1 for Kharej, 2 for Iran): "
read role_choice

if [ "$role_choice" = "2" ]; then
    CURRENT_ROLE="IRAN"
else
    CURRENT_ROLE="KHAREJ"
fi

echo -n "Admin Panel Username [admin]: "
read admin_user
admin_user=${admin_user:-admin}

echo -n "Admin Panel Password: "
read -s admin_pass
echo

# Ports
read -p "HTTP Proxy Port [3128]: " p_http; p_http=${p_http:-3128}
read -p "SOCKS5 Port [1080]: " p_socks; p_socks=${p_socks:-1080}
read -p "MTProto Port [8443]: " p_mt; p_mt=${p_mt:-8443}
read -p "Web Panel Port [8088]: " p_web; p_web=${p_web:-8088}
read -p "WireGuard Port [8080]: " p_wg; p_wg=${p_wg:-8080}

remote_ip=""
remote_pub=""
if [ "$CURRENT_ROLE" = "IRAN" ]; then
    echo -n "Enter Server Kharej IP: "
    read remote_ip
    echo -n "Enter Server Kharej Public Key: "
    read remote_pub
fi

# --- Step 2: Installation ---
echo -e "${C_GREEN}[*] Installing dependencies...${C_NC}"
apt-get update
apt-get install -y ufw fail2ban curl squid dante-server wireguard python3 python3-venv apache2-utils iptables openssl

# --- Step 3: Tunnel & Kill-Switch ---
mkdir -p /etc/wireguard
w_priv=$(wg genkey); w_pub=$(echo "$w_priv" | wg pubkey)

if [ "$CURRENT_ROLE" = "KHAREJ" ]; then
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $w_priv
Address = 10.0.0.1/24
ListenPort = $p_wg
PostUp = iptables -t nat -A POSTROUTING -s 10.0.0.1/24 -o eth0 -j MASQUERADE
EOF
else
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $w_priv
Address = 10.0.0.2/24
PostUp = ip route add default dev wg0 table 200; ip rule add from 10.0.0.2 table 200; iptables -I FORWARD -i eth0 ! -o wg0 -j REJECT
[Peer]
PublicKey = $remote_pub
Endpoint = $remote_ip:$p_wg
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
fi
systemctl enable --now wg-quick@wg0

# --- Step 4: Full Web Dashboard (Python/FastAPI) ---
mkdir -p "$INSTALL_DIR/backend"
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install fastapi uvicorn[standard] python-multipart

cat > "$INSTALL_DIR/backend/app.py" <<EOF
import os, subprocess
from fastapi import FastAPI, Request, Form, Depends, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials

app = FastAPI()
security = HTTPBasic()

ADM_U, ADM_P = "$admin_user", "$admin_pass"

def auth(c: HTTPBasicCredentials = Depends(security)):
    if c.username != ADM_U or c.password != ADM_P: raise HTTPException(401)
    return True

@app.get("/", response_class=HTMLResponse)
async def home(a=Depends(auth)):
    h_list = []
    if os.path.exists("$SQUID_USERS"):
        with open("$SQUID_USERS", "r") as f: h_list = [l.split(":")[0] for l in f.readlines() if ":" in l]
    
    s_out = subprocess.run(["getent", "group", "$DANTE_GROUP"], capture_output=True, text=True).stdout
    s_list = s_out.strip().split(":")[-1].split(",") if ":" in s_out else []
    s_list = [x for x in s_list if x]

    return f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8"><title>ENJANEB ULTIMATE</title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <style>
            body {{ background: #0f172a; color: white; padding: 40px; font-family: sans-serif; }}
            .card {{ background: #1e293b; border: none; border-radius: 15px; margin-bottom: 20px; box-shadow: 0 4px 15px rgba(0,0,0,0.3); }}
            .nav-pills .nav-link.active {{ background: #0ea5e9; }}
            .user-item {{ background: rgba(255,255,255,0.05); padding: 10px; border-radius: 8px; margin-bottom: 5px; }}
        </style>
    </head>
    <body>
        <div class="container">
            <h2 class="text-info mb-4">ENJANEB DASHBOARD <small class="text-white fs-6">($CURRENT_ROLE)</small></h2>
            <div class="row">
                <div class="col-md-4">
                    <div class="card p-3">
                        <h5>System Status</h5><hr>
                        <p>HTTP Port: $p_http</p>
                        <p>SOCKS5 Port: $p_socks</p>
                        <p>MTProto: $p_mt</p>
                        <p>Tunnel: <span class="badge bg-success">ACTIVE</span></p>
                    </div>
                </div>
                <div class="col-md-8">
                    <div class="card p-4">
                        <ul class="nav nav-pills mb-3">
                            <li class="nav-item"><button class="nav-link active" data-bs-toggle="pill" data-bs-target="#http">HTTP Proxy</button></li>
                            <li class="nav-item"><button class="nav-link" data-bs-toggle="pill" data-bs-target="#socks">SOCKS5 Proxy</button></li>
                        </ul>
                        <div class="tab-content">
                            <div class="tab-pane fade show active" id="http">
                                <form action="/add/http" method="post" class="row g-2 mb-3">
                                    <div class="col"><input name="u" class="form-control" placeholder="User" required></div>
                                    <div class="col"><input name="p" class="form-control" placeholder="Pass" required></div>
                                    <div class="col-auto"><button class="btn btn-primary">Add</button></div>
                                </form>
                                {"".join([f'<div class="user-item d-flex justify-content-between"><span>{u}</span> <a href="/del/http/{u}" class="btn btn-sm btn-danger">Delete</a></div>' for u in h_list])}
                            </div>
                            <div class="tab-pane fade" id="socks">
                                <form action="/add/socks" method="post" class="row g-2 mb-3">
                                    <div class="col"><input name="u" class="form-control" placeholder="User" required></div>
                                    <div class="col"><input name="p" class="form-control" placeholder="Pass" required></div>
                                    <div class="col-auto"><button class="btn btn-primary">Add</button></div>
                                </form>
                                {"".join([f'<div class="user-item d-flex justify-content-between"><span>{u}</span> <a href="/del/socks/{u}" class="btn btn-sm btn-danger">Delete</a></div>' for u in s_list])}
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </body>
    </html>
    """

@app.post("/add/{{proto}}")
async def add(proto: str, u: str = Form(...), p: str = Form(...)):
    if proto == "http":
        subprocess.run(["htpasswd", "-bB", "$SQUID_USERS", u, p])
        subprocess.run(["systemctl", "reload", "squid"])
    else:
        subprocess.run(["useradd", "-m", "-s", "/usr/sbin/nologin", "-G", "$DANTE_GROUP", u])
        subprocess.run(["bash", "-c", f"echo '{{u}}:{{p}}' | chpasswd"])
        subprocess.run(["systemctl", "restart", "danted"])
    return RedirectResponse("/", status_code=303)

@app.get("/del/{{proto}}/{{u}}")
async def delete(proto: str, u: str):
    if proto == "http": subprocess.run(["htpasswd", "-D", "$SQUID_USERS", u]); subprocess.run(["systemctl", "reload", "squid"])
    else: subprocess.run(["userdel", "-r", u]); subprocess.run(["systemctl", "restart", "danted"])
    return RedirectResponse("/", status_code=303)
EOF

# --- Step 5: Firewall & Systemd ---
ufw allow "$p_web/tcp" && ufw allow "$p_http/tcp" && ufw allow "$p_socks/tcp" && ufw allow "$p_mt/tcp" && ufw allow "$p_wg/udp"
ufw --force enable

cat > /etc/systemd/system/enjaneb.service <<EOF
[Unit]
Description=Enjaneb Panel
After=network.target
[Service]
WorkingDirectory=$INSTALL_DIR/backend
ExecStart=$INSTALL_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port $p_web
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable --now enjaneb squid danted

echo -e "${C_GREEN}DONE! Panel URL: http://$(curl -s ifconfig.me):$p_web${C_NC}"
if [ "$CURRENT_ROLE" = "KHAREJ" ]; then echo -e "Public Key: ${C_YELLOW}$w_pub${C_NC}"; fi
