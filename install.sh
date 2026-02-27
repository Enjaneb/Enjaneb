#!/usr/bin/env bash

# --- Basic Config & Colors ---
C_BLUE='\033[0;34m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[0;31m'; C_NC='\033[0m'
E_HOME="/opt/enjaneb"
S_PWD="/etc/squid/enjaneb_htpasswd"
D_GRP="enjaneb-socks"

clear
echo -e "${C_BLUE}################################################################${C_NC}"
echo -e "${C_BLUE}#${C_NC} ${C_YELLOW}          ENJANEB ULTIMATE - FINAL STABLE V13               ${C_NC} ${C_BLUE}#${C_NC}"
echo -e "${C_BLUE}################################################################${C_NC}"

# --- Step 1: User Input (Fixed Logic) ---
echo -e "${C_BLUE}>>>> STEP 1: CONFIGURATION <<<<${C_NC}"
read -rp "Server Role [1: Kharej, 2: Iran]: " input_role

# تعریف بلافاصله برای جلوگیری از خطای unbound
if [[ "$input_role" == "2" ]]; then
    MY_ROLE="IRAN"
else
    MY_ROLE="KHAREJ"
fi

read -rp "Admin User [adminproxy]: " p_user
p_user=${p_user:-adminproxy}
read -rsp "Admin Pass: " p_pass; echo

read -rp "HTTP Port [3128]: " p_http; p_http=${p_http:-3128}
read -rp "SOCKS5 Port [1080]: " p_socks; p_socks=${p_socks:-1080}
read -rp "MTProto Port [8443]: " p_mt; p_mt=${p_mt:-8443}
read -rp "WireGuard Port [8080]: " p_wg; p_wg=${p_wg:-8080}
read -rp "Web Panel Port [8088]: " p_web; p_web=${p_web:-8088}

r_ip=""; r_pub=""
if [[ "$MY_ROLE" == "IRAN" ]]; then
    read -rp "Server Kharej IP: " r_ip
    read -rp "Server Kharej Public Key: " r_pub
fi

# --- Step 2: System Install ---
echo -e "${C_GREEN}[*] Installing dependencies...${C_NC}"
apt-get update
apt-get install -y ufw fail2ban curl squid dante-server wireguard python3 python3-venv apache2-utils iptables iproute2 openssl

# --- Step 3: WireGuard ---
mkdir -p /etc/wireguard
w_priv=$(wg genkey); w_pub=$(echo "$w_priv" | wg pubkey)

if [[ "$MY_ROLE" == "KHAREJ" ]]; then
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $w_priv
Address = 10.0.0.1/24
ListenPort = $p_wg
PostUp = iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
EOF
else
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $w_priv
Address = 10.0.0.2/24
PostUp = ip route add default dev wg0 table 200; ip rule add from 10.0.0.2 table 200; iptables -I FORWARD -i eth0 ! -o wg0 -j REJECT
[Peer]
PublicKey = $r_pub
Endpoint = $r_ip:$p_wg
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
fi
systemctl enable --now wg-quick@wg0

# --- Step 4: Panel Backend ---
mkdir -p "$E_HOME/backend"
python3 -m venv "$E_HOME/venv"
"$E_HOME/venv/bin/pip" install fastapi uvicorn[standard] python-multipart

cat > "$E_HOME/backend/app.py" <<EOF
import os, subprocess
from fastapi import FastAPI, Request, Form, Depends, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials

app = FastAPI()
security = HTTPBasic()

ADM_U, ADM_P = "$p_user", "$p_pass"

def check(c: HTTPBasicCredentials = Depends(security)):
    if c.username != ADM_U or c.password != ADM_P: raise HTTPException(401)
    return True

@app.get("/", response_class=HTMLResponse)
async def home(a=Depends(check)):
    h_list = []
    if os.path.exists("$S_PWD"):
        with open("$S_PWD", "r") as f: h_list = [l.split(":")[0] for l in f.readlines() if ":" in l]
    
    s_out = subprocess.run(["getent", "group", "$D_GRP"], capture_output=True, text=True).stdout
    s_list = s_out.strip().split(":")[-1].split(",") if ":" in s_out else []
    s_list = [x for x in s_list if x]

    return f"""
    <html>
    <head>
        <title>ENJANEB ULTIMATE</title>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
        <style>
            body {{ background: #0f172a; color: white; font-family: sans-serif; }}
            .card {{ background: #1e293b; border: none; border-radius: 15px; margin-bottom: 20px; }}
            .nav-link.active {{ background: #38bdf8 !important; }}
        </style>
    </head>
    <body class="p-4">
        <div class="container">
            <h2 class="text-info mb-4">ENJANEB ULTIMATE PANEL <small class="text-white fs-6">({MY_ROLE})</small></h2>
            <div class="row">
                <div class="col-md-4">
                    <div class="card p-3">
                        <h5>Status</h5><hr>
                        <p>HTTP: $p_http | SOCKS: $p_socks</p>
                        <p>MTProto: $p_mt</p>
                        <a href="/restart" class="btn btn-sm btn-danger w-100">Restart Services</a>
                    </div>
                </div>
                <div class="col-md-8">
                    <div class="card p-4">
                        <ul class="nav nav-pills mb-3">
                            <li class="nav-item"><button class="nav-link active" data-bs-toggle="pill" data-bs-target="#ht">HTTP</button></li>
                            <li class="nav-item"><button class="nav-link" data-bs-toggle="pill" data-bs-target="#sk">SOCKS5</button></li>
                        </ul>
                        <div class="tab-content">
                            <div class="tab-pane fade show active" id="ht">
                                <form action="/add/http" method="post" class="row g-2 mb-3">
                                    <input name="u" class="col form-control mx-1" placeholder="User">
                                    <input name="p" class="col form-control mx-1" placeholder="Pass">
                                    <button class="col-2 btn btn-info">Add</button>
                                </form>
                                {"".join([f'<div class="p-2 border-bottom d-flex justify-content-between">{u} <a href="/del/http/{u}" class="text-danger">Delete</a></div>' for u in h_list])}
                            </div>
                            <div class="tab-pane fade" id="sk">
                                <form action="/add/socks" method="post" class="row g-2 mb-3">
                                    <input name="u" class="col form-control mx-1" placeholder="User">
                                    <input name="p" class="col form-control mx-1" placeholder="Pass">
                                    <button class="col-2 btn btn-info">Add</button>
                                </form>
                                {"".join([f'<div class="p-2 border-bottom d-flex justify-content-between">{u} <a href="/del/socks/{u}" class="text-danger">Delete</a></div>' for u in s_list])}
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
        subprocess.run(["htpasswd", "-bB", "$S_PWD", u, p])
        subprocess.run(["systemctl", "reload", "squid"])
    else:
        subprocess.run(["useradd", "-m", "-s", "/usr/sbin/nologin", "-G", "$D_GRP", u])
        subprocess.run(["bash", "-c", f"echo '{{u}}:{{p}}' | chpasswd"])
        subprocess.run(["systemctl", "restart", "danted"])
    return RedirectResponse("/", status_code=303)

@app.get("/del/{{proto}}/{{u}}")
async def delete(proto: str, u: str):
    if proto == "http": subprocess.run(["htpasswd", "-D", "$S_PWD", u]); subprocess.run(["systemctl", "reload", "squid"])
    else: subprocess.run(["userdel", "-r", u]); subprocess.run(["systemctl", "restart", "danted"])
    return RedirectResponse("/", status_code=303)

@app.get("/restart")
async def res():
    subprocess.run(["systemctl", "restart", "squid", "danted", "wg-quick@wg0"])
    return RedirectResponse("/", status_code=303)
EOF

# --- Step 5: Firewall & Service ---
ufw allow "$p_web/tcp" && ufw allow "$p_http/tcp" && ufw allow "$p_socks/tcp" && ufw allow "$p_mt/tcp" && ufw allow "$p_wg/udp"
ufw --force enable

cat > /etc/systemd/system/enjaneb.service <<EOF
[Unit]
Description=Enjaneb Panel
After=network.target
[Service]
WorkingDirectory=$E_HOME/backend
ExecStart=$E_HOME/venv/bin/uvicorn app:app --host 0.0.0.0 --port $p_web
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable --now enjaneb squid danted

echo -e "${C_GREEN}SUCCESS! Panel: http://$(curl -s ifconfig.me):$p_web${C_NC}"
[[ "$MY_ROLE" == "KHAREJ" ]] && echo -e "Public Key: ${C_YELLOW}$w_pub${C_NC}"
