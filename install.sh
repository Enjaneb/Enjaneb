#!/bin/bash
# ENJANEB All-in-One Installer - v1.1

# 1. دریافت نقش سرور
clear
echo "Welcome to ENJANEB Setup"
echo "1) Iran Server"
echo "2) Kharej Server"
read -p "Choose: " ROLE

# 2. نصب ابزارهای مورد نیاز
apt update && apt install -y python3-pip git nginx ufw curl sqlite3

# 3. دانلود پروژه از گیت‌هاب تو
rm -rf /opt/ENJANEB
git clone https://github.com/enjaneb/ENJANEB.git /opt/ENJANEB

# 4. آماده‌سازی دیتابیس (این همون بخش حساسه)
cd /opt/ENJANEB/backend
pip3 install fastapi uvicorn psutil
python3 database.py  # اینجا دیتابیس ساخته میشه

# 5. ساخت سرویس سیستم برای اجرای خودکار (بند 25)
cat <<EOF > /etc/systemd/system/enjaneb.service
[Unit]
Description=ENJANEB Core Service
[Service]
WorkingDirectory=/opt/ENJANEB/backend
ExecStart=/usr/bin/python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now enjaneb

echo "Done! Panel is running on port 8000"
