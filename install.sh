#!/usr/bin/env bash
set -e

echo "===================================="
echo "          ENJANEB Installer"
echo "===================================="
echo ""

# ---- Check Ubuntu Version ----
if [ -f /etc/os-release ]; then
  . /etc/os-release
  VERSION=$VERSION_ID
else
  echo "Cannot detect OS."
  exit 1
fi

if [[ "$VERSION" != "22.04" && "$VERSION" != "24.04" ]]; then
  echo "Unsupported Ubuntu version: $VERSION"
  exit 1
fi

echo "Ubuntu $VERSION detected ✅"
echo ""

# ---- Role Selection ----
echo "Select server role:"
echo "1) Iran (Proxy + Panel)"
echo "2) Server Kharej (Gateway)"
echo ""

read -p "Enter choice [1]: " choice

if [ -z "$choice" ]; then
  choice=1
fi

if [ "$choice" = "1" ]; then
  ROLE="iran"
elif [ "$choice" = "2" ]; then
  ROLE="kharej"
else
  echo "Invalid choice"
  exit 1
fi

echo ""
echo "You selected: $ROLE"
echo ""
echo "Phase 2 test successful ✅"
