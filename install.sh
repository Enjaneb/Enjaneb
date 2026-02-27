#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# ENJANEB - Clean One-File Installer (NO SSL, NO TUNNEL)
# Ubuntu: 22.04 / 24.04
#
# Installs:
# - UFW: opens current SSH port + 80/tcp
# - Fail2ban: enabled
# - Nginx: HTTP reverse-proxy -> local ENJANEB panel backend
# - ENJANEB Panel (FastAPI) via systemd service: enjaneb.service
#
# NOTE:
# This installer intentionally DOES NOT install/enable VPN/tunnels
# or proxy services intended to bypass network restrictions.
# ==========================================================

SUPPORTED_UBUNTU=("22.04" "24.04")

ENJ_USER_DEFAULT="enjaneb"
ENJ_HOME="/opt/enjaneb"
ENJ_VENV="${ENJ_HOME}/venv"
BACKEND_PORT_DEFAULT="8088"

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

is_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] || return 1
  (( p >= 1 && p <= 65535 )) || return 1
  return 0
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

choose_role() {
  echo "Select server role:"
  echo "  1) Iran Server"
  echo "  2) Kharej Server"
  echo
  local choice=""
  read -rp "Enter choice [1]: " choice || true
  choice="${choice:-1}"
  case "$choice" in
    1) echo "iran" ;;
    2) echo "kharej" ;;
    *) die "Invalid choice: $choice" ;;
  esac
}

install_packages() {
  echo "Updating packages..."
  apt-get update -y

  echo "Installing packages..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y \
    ufw fail2ban curl ca-certificates \
    nginx \
    python3 python3-venv python3-pip
}

setup_firewall() {
  local ssh_port="$1"
  echo "Configuring UFW firewall..."
  ufw allow "${ssh_port}/tcp" || true
  ufw allow 80/tcp || true
  ufw --force enable
}

setup_fail2ban() {
  echo "Enabling Fail2ban..."
  systemctl enable fail2ban
  systemctl restart fail2ban
}

create_system_user() {
  local user="$1"
  if ! id -u "$user" >/dev/null 2>&1; then
    echo "Creating system user: $user"
    useradd --system --home "${ENJ_HOME}" --shell /usr/sbin/nologin "$user"
  fi
  mkdir -p "${ENJ_HOME}/backend"
  chown -R "$user:$user" "${ENJ_HOME}"
}

write_backend() {
  local backend_port="$1" admin_user="$2" admin_pass="$3" sys_user="$4"

  cat > "${ENJ_HOME}/backend/requirements.txt" <<'EOF'
fastapi==0.115.0
uvicorn[standard]==0.30.6
python-dotenv==1.0.1
passlib[bcrypt]==1.7.4
EOF

  cat > "${ENJ_HOME}/backend/app.py" <<'EOF'
import os
from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from dotenv import load_dotenv
from passlib.hash import bcrypt
from fastapi.responses import HTMLResponse

load_dotenv()

APP = FastAPI(title="ENJANEB", version="1.0.0")
security = HTTPBasic()

ADMIN_USER = os.getenv("ENJANEB_ADMIN_USER", "admin")
ADMIN_PASS = os.getenv("ENJANEB_ADMIN_PASS", "")
ADMIN_HASH = bcrypt.hash(ADMIN_PASS) if ADMIN_PASS else ""

def require_admin(creds: HTTPBasicCredentials = Depends(security)):
    if creds.username != ADMIN_USER:
        raise HTTPException(status_code=401, detail="Unauthorized")
    if not ADMIN_HASH or not bcrypt.verify(creds.password, ADMIN_HASH):
        raise HTTPException(status_code=401, detail="Unauthorized")
    return True

@APP.get("/api/health")
def health():
    return {"ok": True, "service": "enjaneb"}

@APP.get("/", response_class=HTMLResponse)
def home(_: bool = Depends(require_admin)):
    return '''
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
  <h3>ENJANEB Panel</h3>
  <p class="text-muted">Basic Auth login required (admin username/password).</p>
  <div class="card shadow-sm">
    <div class="card-body">
      <h5 class="card-title">Status</h5>
      <a class="btn btn-outline-dark" href="/api/health">/api/health</a>
    </div>
  </div>
</div>
</body>
</html>
'''
EOF

  cat > "${ENJ_HOME}/backend/.env" <<EOF
ENJANEB_LISTEN_HOST=127.0.0.1
ENJANEB_LISTEN_PORT=${backend_port}
ENJANEB_ADMIN_USER=${admin_user}
ENJANEB_ADMIN_PASS=${admin_pass}
EOF
  chmod 600 "${ENJ_HOME}/backend/.env"

  echo "Setting up Python venv..."
  if [[ ! -d "${ENJ_VENV}" ]]; then
    python3 -m venv "${ENJ_VENV}"
  fi
  "${ENJ_VENV}/bin/pip" install --upgrade pip wheel >/dev/null
  "${ENJ_VENV}/bin/pip" install -r "${ENJ_HOME}/backend/requirements.txt"

  chown -R "$sys_user:$sys_user" "${ENJ_HOME}"
}

install_systemd_service() {
  local sys_user="$1"
  echo "Installing systemd service: enjaneb.service"
  cat > /etc/systemd/system/enjaneb.service <<EOF
[Unit]
Description=ENJANEB Control Panel
After=network.target

[Service]
Type=simple
User=${sys_user}
Group=${sys_user}
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

configure_nginx_http_proxy() {
  local host="$1" backend_port="$2"

  echo "Configuring Nginx (HTTP only) reverse proxy..."

  mkdir -p /etc/nginx/sites-enabled.bak
  if compgen -G "/etc/nginx/sites-enabled/*" > /dev/null; then
    cp -a /etc/nginx/sites-enabled/* /etc/nginx/sites-enabled.bak/ 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/*
  fi

  cat > /etc/nginx/sites-available/enjaneb.conf <<EOF
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

  ln -sf /etc/nginx/sites-available/enjaneb.conf /etc/nginx/sites-enabled/enjaneb.conf

  nginx -t
  systemctl enable nginx
  systemctl restart nginx
}

main() {
  banner
  need_root

  echo "Checking Ubuntu version..."
  local v
  v="$(detect_ubuntu_version)"
  if ! check_ubuntu_supported "$v"; then
    die "Unsupported Ubuntu version: $v (supported: 22.04, 24.04)"
  fi
  echo "Ubuntu $v detected ✅"
  echo

  ROLE="$(choose_role)"

  HOST="$(read_default "Panel host (domain or server IP for nginx server_name)" "localhost")"
  BACKEND_PORT="$(read_default "Panel backend local port" "${BACKEND_PORT_DEFAULT}")"
  is_port "$BACKEND_PORT" || die "Invalid port: $BACKEND_PORT"

  ADMIN_USER="$(read_default "Panel admin username" "admin")"
  ADMIN_PASS="$(read_secret "Panel admin password")"

  SYS_USER="$(read_default "System user for ENJANEB service" "${ENJ_USER_DEFAULT}")"

  SSH_PORT="$(detect_ssh_port)"
  echo "Detected SSH port: ${SSH_PORT}"
  echo

  install_packages
  setup_firewall "$SSH_PORT"
  setup_fail2ban

  create_system_user "$SYS_USER"
  write_backend "$BACKEND_PORT" "$ADMIN_USER" "$ADMIN_PASS" "$SYS_USER"
  install_systemd_service "$SYS_USER"
  configure_nginx_http_proxy "$HOST" "$BACKEND_PORT"

  echo
  echo "===================================="
  echo "DONE ✅"
  echo "Role:         ${ROLE}"
  echo "Panel (HTTP): http://${HOST}/"
  echo "Health:       http://${HOST}/api/health"
  echo "Service:      systemctl status enjaneb"
  echo "===================================="
}

main "$@"
