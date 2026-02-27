#!/bin/bash
# ENJANEB All-in-One Installer

# تنظیمات اولیه (بند 26 و 27)
clear
echo "1) Iran Server (Full)"
echo "2) Kharej Server (Tunnel Only)"
read -p "Select Role: " ROLE

# نصب پیشنیازها (بند 21 تا 23)
apt update && apt install -y python3-pip git nginx ufw fail2ban curl

# نصب GOST (هسته پروکسی)
curl -L https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz | gunzip > /usr/local/bin/gost
chmod +x /usr/local/bin/gost

# دانلود پروژه از گیت‌هاب تو
rm -rf /opt/ENJANEB
git clone https://github.com/enjaneb/ENJANEB.git /opt/ENJANEB

if [ "$ROLE" == "1" ]; then
    # تنظیمات سرور ایران (بند 24)
    cd /opt/ENJANEB/backend
    pip3 install fastapi uvicorn psutil
    
    # ساخت سرویس پایتون
    echo "[Unit]
Description=ENJANEB API
[Service]
ExecStart=/usr/bin/python3 /opt/ENJANEB/backend/main.py
Restart=always
[Install]
WantedBy=multi-user.target" > /etc/systemd/system/enjaneb.service
    
    systemctl daemon-reload
    systemctl enable --now enjaneb
    echo "Iran Server is Ready!"
else
    echo "Kharej Server is Ready!"
fi
