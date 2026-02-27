#!/bin/bash
# ENJANEB Multi-Role Installer - v2.2

# پاک کردن صفحه و اجبار به پرسش
clear
echo "================================================"
echo "      WELCOME TO ENJANEB PROJECT SETUP          "
echo "================================================"
echo ""
echo "Please choose the server role:"
echo "1) Iran Server (Panel + Database + Proxy)"
echo "2) Kharej Server (Tunnel Core Only)"
echo ""

# استفاده از یک متغیر موقت برای اطمینان از دریافت ورودی
read -p "Enter number [1 or 2]: " CHOICE

# بررسی انتخاب کاربر
if [ "$CHOICE" == "1" ]; then
    ROLE="IRAN"
elif [ "$CHOICE" == "2" ]; then
    ROLE="KHAREJ"
else
    echo "Invalid choice. Exiting..."
    exit 1
fi

echo "You selected: $ROLE Server. Starting installation..."

# 1. نصب پیش‌نیازهای عمومی
apt update && apt install -y python3-pip git ufw curl psmisc

# 2. نصب هسته پروکسی Gost
wget https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
gunzip -f gost-linux-amd64-2.11.5.gz
mv gost-linux-amd64-2.11.5 /usr/local/bin/gost
chmod +x /usr/local/bin/gost

# 3. دانلود پروژه
rm -rf /opt/ENJANEB
git clone https://github.com/enjaneb/ENJANEB.git /opt/ENJANEB

if [ "$ROLE" == "IRAN" ]; then
    # بخش ایران
    apt install -y sqlite3
    cd /opt/ENJANEB/backend
    pip3 install fastapi uvicorn psutil aiofiles
    python3 database.py
    
    ufw allow 8000/tcp
    ufw allow 8080/tcp
    ufw --force enable
    
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
    echo "Iran Server setup complete on port 8000."

else
    # بخش خارج
    ufw allow 8080/tcp
    ufw --force enable
    
    cat <<EOF > /etc/systemd/system/enjaneb-kharej.service
[Unit]
Description=ENJANEB Kharej Service
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
    echo "Kharej Server setup complete on port 8080."
fi
