#!/bin/bash
# ENJANEB All-in-One Installer v2.1 (Multi-Role)

clear
echo "================================================"
echo "      WELCOME TO ENJANEB PROJECT SETUP          "
echo "================================================"
echo "1) Iran Server (Panel + Database + Proxy)"
echo "2) Kharej Server (Tunnel Core Only)"
read -p "Please select the server role [1 or 2]: " ROLE

# 1. نصب پیش‌نیازهای عمومی
apt update && apt install -y python3-pip git ufw curl psmisc

# 2. نصب هسته پروکسی Gost (برای هر دو سرور الزامی است)
echo "Installing GOST Proxy Engine..."
wget https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
gunzip -f gost-linux-amd64-2.11.5.gz
mv gost-linux-amd64-2.11.5 /usr/local/bin/gost
chmod +x /usr/local/bin/gost

# 3. دانلود سورس پروژه
rm -rf /opt/ENJANEB
git clone https://github.com/enjaneb/ENJANEB.git /opt/ENJANEB

if [ "$ROLE" == "1" ]; then
    echo "Configuring as IRAN Server..."
    
    # نصب ابزارهای مخصوص ایران
    apt install -y nginx sqlite3
    cd /opt/ENJANEB/backend
    pip3 install fastapi uvicorn psutil aiofiles
    python3 database.py # ساخت دیتابیس
    
    # تنظیم فایروال ایران
    ufw allow 8000/tcp # پورت پنل
    ufw allow 8080/tcp # پورت پروکسی
    ufw --force enable
    
    # ساخت سرویس پنل و پروکسی
    cat <<EOF > /etc/systemd/system/enjaneb.service
[Unit]
Description=ENJANEB Iran Service
After=network.target

[Service]
User=root
WorkingDirectory=/opt/ENJANEB/backend
ExecStart=/usr/bin/python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now enjaneb
    echo "Iran Server is Ready! Access panel at port 8000"

else
    echo "Configuring as KHAREJ Server..."
    
    # تنظیم فایروال خارج (فقط پورت تانل)
    ufw allow 8080/tcp
    ufw --force enable
    
    # ساخت سرویس ساده برای خارج (فقط اجرای Gost برای تانل)
    # در فازهای بعدی این بخش با Wireguard یا تانل اختصاصی جایگزین می‌شود
    cat <<EOF > /etc/systemd/system/enjaneb-kharej.service
[Unit]
Description=ENJANEB Kharej Tunnel Service
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/gost -L=:8080
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now enjaneb-kharej
    echo "Kharej Server is Ready! Tunnel core is running on port 8080"
fi

echo "================================================"
