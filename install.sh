#!/usr/bin/env bash
set -euo pipefail

SUPPORTED_UBUNTU=("22.04" "24.04")

# ---------- UI helpers ----------
GREEN="\033[0;32m"
RED="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m"

banner() {
  echo -e "${CYAN}"
  echo "===================================="
  echo "          ENJANEB Installer"
  echo "===================================="
  echo -e "${NC}"
}

die() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
ok()  { echo -e "${GREEN}✅${NC} $*"; }
info(){ echo -e "${CYAN}ℹ${NC} $*"; }

read_default() {
  local prompt="$1" def="$2" ans=""
  read -rp "$prompt [$def]: " ans || true
  echo "${ans:-$def}"
}

# ---------- checks ----------
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

# ---------- role selection ----------
choose_role() {
  echo
  echo "Select server role:"
  echo "  1) Iran (Proxy + Panel)"
  echo "  2) Server Kharej (Gateway)"
  echo
  local r
  r="$(read_default "Enter choice" "1")"
  case "$r" in
    1) echo "iran" ;;
    2) echo "kharej" ;;
    *) die "Invalid choice: $r" ;;
  esac
}

# ---------- phase stubs ----------
phase_iran_stub() {
  info "Selected: Iran (Proxy + Panel)"
  info "Phase 2 stub: next steps will install packages, enable firewall, and deploy panel components."
  ok "Nothing changed yet (safe test)."
}

phase_kharej_stub() {
  info "Selected: Server Kharej (Gateway)"
  info "Phase 2 stub: next steps will prepare gateway components."
  ok "Nothing changed yet (safe test)."
}

main() {
  banner
  need_root

  info "Checking Ubuntu version..."
  local v
  v="$(detect_ubuntu_version)"
  if ! check_ubuntu_supported "$v"; then
    die "Unsupported Ubuntu: $v (supported: 22.04, 24.04)"
  fi
  ok "Ubuntu $v detected"

  local role
  role="$(choose_role)"

  case "$role" in
    iran)   phase_iran_stub ;;
    kharej) phase_kharej_stub ;;
    *) die "Unexpected role: $role" ;;
  esac

  echo
  ok "Phase 2 installer test completed."
}

main "$@"
