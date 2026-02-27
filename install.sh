#!/usr/bin/env bash
set -euo pipefail

# =========================
# ENJANEB - One-file Installer (NO SSL)
# Ubuntu: 22.04 / 24.04
# Installs:
# - UFW (opens current SSH port, 80, and proxy ports)
# - Fail2ban (enabled)
# - Nginx (HTTP only, port 80) reverse proxy to ENJANEB backend
# - ENJANEB Panel (FastAPI) as systemd: enjaneb.service
# - Squid HTTP Proxy (Basic auth via htpasswd) + managed via panel
# - Dante SOCKS5 (auth via system users) + managed via panel
#
# NOTE: This installer DOES NOT configure SSL/Certbot.
# =========================

SUPPORTED_UBUNTU=("22.04" "24.04")

ENJ_USER="enjaneb"
ENJ_HOME="/opt/enjaneb"
ENJ_VENV="${ENJ_HOME}/venv"
ENJ_BACKEND_PORT_DEFAULT="8088"

SQUID_HTPASSWD="/etc/squid/enjaneb_htpasswd"
SQUID_CONF="/etc/squid/squid.conf"

DANTE_CONF="/etc/danted.conf"
DANTE_USER_GROUP="enjaneb-socks"

banner() {
  echo "===================================="
  echo "          ENJANEB Installer"
  echo "===================================="
  echo
}

die(){ echo "[ERROR] $*" >&2; exit 1; }

need_root() {
  if [[ ${EUID:-0} -ne 0 ]]; then
    die "Run as root. Example: sudo ./install.sh"
  fi
}

detect_ubuntu_version() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "${VERSION_ID:-unknown}"
  else
    echo "unknown"
  fi
}

check_ubuntu_supported() {
  local v="$1"
  for okv in "${SUPPORTED_UBUNTU[@]}"; do
    [[ "$v" == "$okv" ]] && return 0
  done
  return 1
}

read_default() {
  local prompt="$1" def="$2" ans=""
  read -rp "$prompt [$def]: " ans || true
  echo "${ans:-$def}"
}

read_secret() {
  local prompt="$1" ans=""
  read -rsp "$prompt: " ans; echo
  [[ -z "$ans" ]] && die "Empty value not allowed"
  echo "$ans"
}

detect_ssh_port() {
  local p=""
  if command -v ss >/dev/null 2>&1; then
    p="$(ss -ltnp 2>/dev/null | awk '/sshd/ && $4 ~ /:[0-9]+$/ {print $4}' | head -n1 | sed 's/.*://')"
  fi
  if [[ -n "${p:-}" ]]; then echo "$p"; return 0; fi
  if [[ -f /etc/ssh/sshd_config ]]; then
    p="$(grep -Ei '^\s*Port\s+' /etc/ssh/sshd_config 2>/dev/null | tail -n1 | awk '{print $2}' || true)"
  fi
  echo "${p:-22}"
}

install_packages() {
  echo "Updating packages..."
  apt-get update -y

  echo "Installing packages..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y     ufw fail2ban curl ca-certificates     nginx     python3 python3-venv python3-pip     apache2-utils     squid dante-server
}

setup_firewall() {
  local ssh_port="$1"
  echo "Configuring UFW firewall..."
  ufw allow "${ssh_port}/tcp" || true
  ufw allow 80/tcp || true
  ufw allow "${HTTP_PORT}/tcp" || true
  ufw allow "${SOCKS_PORT}/tcp" || true
  ufw --force enable
}

setup_fail2ban() {
  echo "Enabling Fail2ban..."
  systemctl enable fail2ban
  systemctl restart fail2ban
}

setup_nginx_http_reverse_proxy() {
  local host="$1"
  local backend_port="$2"

  echo "Configuring Nginx (HTTP only) reverse proxy..."
  cat > "/etc/nginx/sites-available/enjaneb.conf" <<EOF
server {
  listen 80;
  server_name ${host};

  location / {
    proxy_pass http://127.0.0.1:${backend_port};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF

  ln -sf "/etc/nginx/sites-available/enjaneb.conf" "/etc/nginx/sites-enabled/enjaneb.conf"
  rm -f /etc/nginx/sites-enabled/default || true

  nginx -t
  systemctl enable nginx
  systemctl restart nginx
}

create_enjaneb_user() {
  if ! id -u "${ENJ_USER}" >/dev/null 2>&1; then
    echo "Creating system user: ${ENJ_USER}"
    useradd --system --home "${ENJ_HOME}" --shell /usr/sbin/nologin "${ENJ_USER}"
  fi
  mkdir -p "${ENJ_HOME}"
  chown -R "${ENJ_USER}:${ENJ_USER}" "${ENJ_HOME}"
}

setup_squid() {
  echo "Configuring Squid HTTP proxy..."
  touch "${SQUID_HTPASSWD}"
  chmod 640 "${SQUID_HTPASSWD}"
  chown proxy:proxy "${SQUID_HTPASSWD}" 2>/dev/null || true

  if [[ -f "${SQUID_CONF}" ]]; then
    cp -a "${SQUID_CONF}" "${SQUID_CONF}.bak.$(date +%s)" || true
  fi

  cat > "${SQUID_CONF}" <<EOF
# ENJANEB Squid config (HTTP proxy)
http_port ${HTTP_PORT}

auth_param basic program /usr/lib/squid/basic_ncsa_auth ${SQUID_HTPASSWD}
auth_param basic realm ENJANEB-HTTP
acl authenticated proxy_auth REQUIRED

http_access allow authenticated
http_access deny all

via off
forwarded_for delete

access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
EOF

  systemctl enable squid
  systemctl restart squid
}

setup_dante() {
  echo "Configuring Dante SOCKS5 proxy..."

  if ! getent group "${DANTE_USER_GROUP}" >/dev/null; then
    groupadd "${DANTE_USER_GROUP}"
  fi

  if [[ -f "${DANTE_CONF}" ]]; then
    cp -a "${DANTE_CONF}" "${DANTE_CONF}.bak.$(date +%s)" || true
  fi

  local iface
  iface="$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1 || true)"
  [[ -z "${iface:-}" ]] && iface="eth0"

  cat > "${DANTE_CONF}" <<EOF
# ENJANEB Dante config (SOCKS5)
logoutput: syslog

internal: ${iface} port = ${SOCKS_PORT}
external: ${iface}

method: username
user.notprivileged: nobody

client pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: error
}

socks pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  command: connect
  log: error
  method: username
}

socks pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  command: bind
  log: error
  method: username
}

socks pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  command: udpassociate
  log: error
  method: username
}
EOF

  systemctl enable danted
  systemctl restart danted
}

write_backend() {
  local backend_port="$1" admin_user="$2" admin_pass="$3"

  echo "Deploying ENJANEB backend (FastAPI)..."
  mkdir -p "${ENJ_HOME}/backend"
  chown -R "${ENJ_USER}:${ENJ_USER}" "${ENJ_HOME}"

  cat > "${ENJ_HOME}/backend/requirements.txt" <<'EOF'
fastapi==0.115.0
uvicorn[standard]==0.30.6
python-dotenv==1.0.1
passlib[bcrypt]==1.7.4
EOF

  cat > "${ENJ_HOME}/backend/app.py" <<'EOF'
import os
import subprocess
from fastapi import FastAPI, HTTPException, Depends, Form
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from dotenv import load_dotenv
from passlib.hash import bcrypt
from fastapi.responses import HTMLResponse, RedirectResponse

load_dotenv()

APP = FastAPI(title="ENJANEB", version="1.0.0")
security = HTTPBasic()

ADMIN_USER = os.getenv("ENJANEB_ADMIN_USER", "admin")
ADMIN_PASS = os.getenv("ENJANEB_ADMIN_PASS", "")
ADMIN_HASH = bcrypt.hash(ADMIN_PASS) if ADMIN_PASS else ""

HTTP_PORT = os.getenv("ENJANEB_HTTP_PORT", "3128")
SOCKS_PORT = os.getenv("ENJANEB_SOCKS_PORT", "1080")
SQUID_HTPASSWD = os.getenv("ENJANEB_SQUID_HTPASSWD", "/etc/squid/enjaneb_htpasswd")
SOCKS_GROUP = os.getenv("ENJANEB_SOCKS_GROUP", "enjaneb-socks")

def require_admin(creds: HTTPBasicCredentials = Depends(security)):
    if creds.username != ADMIN_USER:
        raise HTTPException(status_code=401, detail="Unauthorized")
    if not ADMIN_HASH or not bcrypt.verify(creds.password, ADMIN_HASH):
        raise HTTPException(status_code=401, detail="Unauthorized")
    return True

def run(cmd):
    try:
        p = subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return p.stdout.strip()
    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=400, detail=(e.stderr.strip() or "Command failed"))

@APP.get("/api/health")
def health():
    return {"ok": True, "service": "enjaneb"}

@APP.get("/", response_class=HTMLResponse)
def home(_: bool = Depends(require_admin)):
    html = f'''
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <title>ENJANEB</title>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
<div class="container py-4">
  <div class="d-flex justify-content-between align-items-center">
    <h3 class="m-0">ENJANEB Control Panel</h3>
    <span class="badge text-bg-dark">HTTP:{HTTP_PORT} | SOCKS5:{SOCKS_PORT}</span>
  </div>
  <hr/>
  <div class="row g-3">
    <div class="col-md-6">
      <div class="card shadow-sm">
        <div class="card-body">
          <h5 class="card-title">HTTP Proxy (Squid)</h5>
          <p class="text-muted mb-2">Users stored in htpasswd. Service: squid</p>

          <form class="row g-2" method="post" action="/ui/http/create">
            <div class="col-6"><input class="form-control" name="username" placeholder="username" required></div>
            <div class="col-6"><input class="form-control" name="password" placeholder="password" type="password" required></div>
            <div class="col-12"><button class="btn btn-primary w-100" type="submit">Create HTTP User</button></div>
          </form>

          <form class="row g-2 mt-2" method="post" action="/ui/http/delete">
            <div class="col-12"><input class="form-control" name="username" placeholder="username to delete" required></div>
            <div class="col-12"><button class="btn btn-outline-danger w-100" type="submit">Delete HTTP User</button></div>
          </form>

          <div class="d-flex gap-2 mt-3">
            <a class="btn btn-outline-secondary w-50" href="/api/http/users/list">List Users</a>
            <a class="btn btn-outline-secondary w-50" href="/api/service/squid/restart">Restart</a>
          </div>
        </div>
      </div>
    </div>

    <div class="col-md-6">
      <div class="card shadow-sm">
        <div class="card-body">
          <h5 class="card-title">SOCKS5 (Dante)</h5>
          <p class="text-muted mb-2">Users are system users in group: {SOCKS_GROUP}. Service: danted</p>

          <form class="row g-2" method="post" action="/ui/socks/create">
            <div class="col-6"><input class="form-control" name="username" placeholder="username" required></div>
            <div class="col-6"><input class="form-control" name="password" placeholder="password" type="password" required></div>
            <div class="col-12"><button class="btn btn-primary w-100" type="submit">Create SOCKS User</button></div>
          </form>

          <form class="row g-2 mt-2" method="post" action="/ui/socks/delete">
            <div class="col-12"><input class="form-control" name="username" placeholder="username to delete" required></div>
            <div class="col-12"><button class="btn btn-outline-danger w-100" type="submit">Delete SOCKS User</button></div>
          </form>

          <div class="d-flex gap-2 mt-3">
            <a class="btn btn-outline-secondary w-50" href="/api/socks/users/list">List Users</a>
            <a class="btn btn-outline-secondary w-50" href="/api/service/danted/restart">Restart</a>
          </div>
        </div>
      </div>
    </div>
  </div>

  <div class="card shadow-sm mt-3">
    <div class="card-body">
      <h5 class="card-title">System</h5>
      <div class="d-flex gap-2 flex-wrap">
        <a class="btn btn-outline-dark" href="/api/health">Health</a>
        <a class="btn btn-outline-dark" href="/api/service/status">Service Status</a>
      </div>
      <p class="text-muted mt-2 mb-0">Browser will ask for Basic Auth. Use your panel admin username/password.</p>
    </div>
  </div>
</div>
</body>
</html>
'''
    return html

@APP.get("/api/service/status")
def service_status(_: bool = Depends(require_admin)):
    squid = run(["systemctl", "is-active", "squid"])
    danted = run(["systemctl", "is-active", "danted"])
    return {"squid": squid, "danted": danted}

@APP.get("/api/service/{name}/restart")
def service_restart(name: str, _: bool = Depends(require_admin)):
    if name not in ("squid", "danted"):
        raise HTTPException(status_code=400, detail="Unsupported service")
    run(["systemctl", "restart", name])
    return {"ok": True, "service": name}

@APP.get("/api/http/users/list")
def http_list(_: bool = Depends(require_admin)):
    if not os.path.exists(SQUID_HTPASSWD):
        return {"users": []}
    with open(SQUID_HTPASSWD, "r", encoding="utf-8", errors="ignore") as f:
        users = [line.split(":", 1)[0].strip() for line in f if ":" in line]
    users = sorted([u for u in users if u])
    return {"users": users}

@APP.post("/ui/http/create")
def ui_http_create(username: str = Form(...), password: str = Form(...), _: bool = Depends(require_admin)):
    run(["htpasswd", "-bB", SQUID_HTPASSWD, username, password])
    run(["chown", "proxy:proxy", SQUID_HTPASSWD])
    run(["chmod", "640", SQUID_HTPASSWD])
    run(["systemctl", "restart", "squid"])
    return RedirectResponse(url="/", status_code=303)

@APP.post("/ui/http/delete")
def ui_http_delete(username: str = Form(...), _: bool = Depends(require_admin)):
    if not os.path.exists(SQUID_HTPASSWD):
        raise HTTPException(status_code=400, detail="htpasswd file missing")
    run(["htpasswd", "-D", SQUID_HTPASSWD, username])
    run(["systemctl", "restart", "squid"])
    return RedirectResponse(url="/", status_code=303)

@APP.get("/api/socks/users/list")
def socks_list(_: bool = Depends(require_admin)):
    out = run(["getent", "group", SOCKS_GROUP])
    if ":" not in out:
        return {"users": []}
    members = out.split(":")[-1].strip()
    if not members:
        return {"users": []}
    users = sorted([u for u in members.split(",") if u])
    return {"users": users}

@APP.post("/ui/socks/create")
def ui_socks_create(username: str = Form(...), password: str = Form(...), _: bool = Depends(require_admin)):
    try:
        run(["id", "-u", username])
        user_exists = True
    except HTTPException:
        user_exists = False

    if not user_exists:
        run(["useradd", "-m", "-s", "/usr/sbin/nologin", username])

    run(["bash", "-lc", f"echo '{username}:{password}' | chpasswd"])
    run(["usermod", "-aG", SOCKS_GROUP, username])
    run(["systemctl", "restart", "danted"])
    return RedirectResponse(url="/", status_code=303)

@APP.post("/ui/socks/delete")
def ui_socks_delete(username: str = Form(...), _: bool = Depends(require_admin)):
    run(["userdel", "-r", username])
    run(["systemctl", "restart", "danted"])
    return RedirectResponse(url="/", status_code=303)
EOF

  cat > "${ENJ_HOME}/backend/.env" <<EOF
ENJANEB_LISTEN_HOST=127.0.0.1
ENJANEB_LISTEN_PORT=${backend_port}
ENJANEB_ADMIN_USER=${admin_user}
ENJANEB_ADMIN_PASS=${admin_pass}
ENJANEB_HTTP_PORT=${HTTP_PORT}
ENJANEB_SOCKS_PORT=${SOCKS_PORT}
ENJANEB_SQUID_HTPASSWD=${SQUID_HTPASSWD}
ENJANEB_SOCKS_GROUP=${DANTE_USER_GROUP}
EOF
  chmod 600 "${ENJ_HOME}/backend/.env"
  chown -R "${ENJ_USER}:${ENJ_USER}" "${ENJ_HOME}"

  echo "Setting up Python venv..."
  if [[ ! -d "${ENJ_VENV}" ]]; then
    python3 -m venv "${ENJ_VENV}"
  fi
  "${ENJ_VENV}/bin/pip" install --upgrade pip wheel >/dev/null
  "${ENJ_VENV}/bin/pip" install -r "${ENJ_HOME}/backend/requirements.txt"
}

install_systemd_service() {
  echo "Installing systemd service: enjaneb.service"
  cat > /etc/systemd/system/enjaneb.service <<EOF
[Unit]
Description=ENJANEB Control Panel
After=network.target

[Service]
Type=simple
User=${ENJ_USER}
Group=${ENJ_USER}
WorkingDirectory=${ENJ_HOME}/backend
EnvironmentFile=${ENJ_HOME}/backend/.env
ExecStart=${ENJ_VENV}/bin/uvicorn app:APP --host \${ENJANEB_LISTEN_HOST} --port \${ENJANEB_LISTEN_PORT}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable enjaneb
  systemctl restart enjaneb
}

main() {
  banner
  need_root

  echo "Checking Ubuntu version..."
  v="$(detect_ubuntu_version)"
  if ! check_ubuntu_supported "$v"; then
    die "Unsupported Ubuntu version: $v (supported: 22.04, 24.04)"
  fi
  echo "Ubuntu $v detected ✅"
  echo

  echo "This installer sets up: Panel + HTTP proxy + SOCKS5 (NO SSL)."
  echo

  HOST="$(read_default "Panel host (domain or server IP; used in nginx server_name)" "localhost")"

  HTTP_PORT="$(read_default "HTTP proxy port (Squid)" "3128")"
  SOCKS_PORT="$(read_default "SOCKS5 port (Dante)" "1080")"
  BACKEND_PORT="$(read_default "ENJANEB backend local port (nginx -> 127.0.0.1)" "${ENJ_BACKEND_PORT_DEFAULT}")"

  ADMIN_USER="$(read_default "Panel admin username (panel-only)" "admin")"
  ADMIN_PASS="$(read_secret "Panel admin password")"

  SSH_PORT="$(detect_ssh_port)"
  echo "Detected SSH port: ${SSH_PORT}"
  echo

  install_packages
  setup_firewall "$SSH_PORT"
  setup_fail2ban

  create_enjaneb_user

  setup_squid
  setup_dante

  write_backend "$BACKEND_PORT" "$ADMIN_USER" "$ADMIN_PASS"
  install_systemd_service

  setup_nginx_http_reverse_proxy "$HOST" "$BACKEND_PORT"

  echo
  echo "===================================="
  echo "DONE ✅"
  echo "Panel (HTTP):  http://${HOST}/"
  echo "HTTP Proxy:    ${HTTP_PORT} (Squid, create users in panel)"
  echo "SOCKS5:        ${SOCKS_PORT} (Dante, create users in panel)"
  echo "Service:       systemctl status enjaneb"
  echo "===================================="
}

main "$@"
