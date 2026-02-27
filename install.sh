#!/usr/bin/env bash

echo "===================================="
echo "       ENJANEB Installer"
echo "===================================="
echo ""
echo "Checking Ubuntu version..."

if [ -f /etc/os-release ]; then
  . /etc/os-release
  VERSION=$VERSION_ID
else
  echo "Cannot detect OS."
  exit 1
fi

if [[ "$VERSION" != "22.04" && "$VERSION" != "24.04" ]]; then
  echo "Unsupported Ubuntu version: $VERSION"
  echo "Only Ubuntu 22.04 and 24.04 are supported."
  exit 1
fi

echo "Ubuntu $VERSION detected ✅"
echo ""

echo "This is phase 1 installer test."
echo "More features will be added step by step."

exit 0
