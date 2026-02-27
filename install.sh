#!/bin/bash
# ENJANEB Installer v1.0
clear
echo "Welcome to ENJANEB Project Setup"

# نصب پیشنیازها
apt update && apt install -y python3-pip git nginx ufw

# دانلود کل پروژه از گیت‌هاب تو
git clone https://github.com/enjaneb/ENJANEB.git /opt/ENJANEB

# اجرای بخش‌های دیگر (بعداً کامل می‌کنیم)
echo "Base system installed. Go to /opt/ENJANEB"
