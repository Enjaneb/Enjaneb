#!/usr/bin/env bash
set -euo pipefail

SUPPORTED_UBUNTU=("22.04" "24.04")

banner() {
  echo "===================================="
  echo "          ENJANEB Installer"
  echo "===================================="
  echo
}

die() { echo "[ERROR] $*" >&2; exit 1; }

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

need_root() {
  if [[ ${EUID:-0} -ne 0 ]]; then
    die "Run as root. Example: sudo ./install.sh"
  fi
}

detect_ssh_port() {
  local p=""

  if command -v ss >/dev/null 2>&1; then
    p="$(ss -ltnp 2>/dev/null | awk '/sshd/ && $4 ~ /:[0-9]+$/ {print $4}' | head -n1 | sed 's/.*://')"
  fi
  if [[ -n "${p:-}" ]]; then
    echo "$p"
    return 0
  fi

  if [[ -f /etc/ssh/sshd_config ]]; then
    p="$(grep -Ei '^\s*Port\s+' /etc/ssh/sshd_config 2>/dev/null | tail -n1 | awk '{print $2}' || true)"
  fi
  echo "${p:-22}"
}

choose_role_simple() {
  echo "Select server role:"
  echo "  1) Iran Server (Proxy + Panel)"
  echo "  2) Kharej Server (Gateway)"
  echo

  read -rp "Enter choice [1]: " choice || true
  choice="${choice:-1}"

  if [[ "$choice" == "1" ]]; then
    echo "iran"
  elif [[ "$choice" == "2" ]]; then
    echo "kharej"
  else
    die "Invalid choice: $choice"
  fi
}

base_security_setup() {
  local ssh_port="$1"

  echo
  echo "Preparing secure base system..."
  echo "Detected SSH Port: ${ssh_port}"
  echo

  export DEBIAN_FRONTEND=noninteractive

  echo "Updating packages..."
  apt-get update -y

  echo "Installing base packages (ufw, fail2ban, curl)..."
  apt-get install -y ufw fail2ban curl ca-certificates

  echo "Configuring UFW firewall..."
  ufw allow "${ssh_port}/tcp" || true
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  ufw --force enable

  echo "Enabling Fail2ban..."
  systemctl enable fail2ban
  systemctl restart fail2ban

  echo
  echo "Base security setup complete ✅"
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

  ROLE="$(choose_role_simple)"

  SSH_PORT="$(detect_ssh_port)"
  base_security_setup "$SSH_PORT"

  echo
  echo "You selected: $ROLE"
  echo
  echo "Phase 3 completed successfully ✅"
}

main "$@"
