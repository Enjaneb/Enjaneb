#!/bin/bash

# --- رنگ‌ها و بنر ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_banner() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${GREEN}           ENJANEB PROJECT - Personal Edition      ${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

# --- بررسی پیش‌نیازها (بند ۴۶، ۴۷، ۵۲) ---
check_os() {
    OS=$(lsb_release -is)
    VER=$(lsb_release -rs)
    if [[ "$OS" != "Ubuntu" ]]; then
        echo -e "${RED}Error: Only Ubuntu is supported.${NC}"
        exit 1
    fi
}

# --- بهینه‌سازی سیستم (بند ۹۸ تا ۱۰۲) ---
optimize_system() {
    echo -e "${YELLOW}[*] Hardening & Optimizing Kernel for 1GB RAM...${NC}"
    
    # افزایش محدودیت فایل‌ها
    echo "* soft nofile 1000000" >> /etc/security/limits.conf
    echo "* hard nofile 1000000" >> /etc/security/limits.conf
    
    # تنظیمات شبکه (BBR + Optimization)
    cat <<EOF > /etc/sysctl.d/99-enjaneb.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
vm.swappiness=10
fs.file-max=1000000
EOF
    sysctl --system
}

# --- نصب پیشنیازها (بند ۲۱ تا ۲۳) ---
install_base() {
    echo -e "${YELLOW}[*] Installing Base Packages...${NC}"
    apt update && apt install -y ufw fail2ban nginx python3-pip wireguard curl git
    systemctl enable ufw
}

# --- فرآیند اصلی ---
show_banner
check_os

echo -e "Which server are you installing?"
echo -e "1) ${GREEN}Iran Server${NC} (Panel + Proxies + System)"
echo -e "2) ${RED}Kharej Server${NC} (Tunnel Endpoint Only)"
read -p "Selection [1-2]: " SERVER_ROLE

if [ "$SERVER_ROLE" == "1" ]; then
    echo -e "\n${GREEN}>>> Configuring Iran Server <<<${NC}"
    
    # تنظیم پورت‌ها (بند ۲۹)
    read -p "Enter HTTP Proxy Port [Default 8080]: " HTTP_PORT
    HTTP_PORT=${HTTP_PORT:-8080}
    
    read -p "Enter SOCKS5 Port [Default 1080]: " SOCKS_PORT
    SOCKS_PORT=${SOCKS_PORT:-1080}

    # باز کردن پورت SSH فعلی در فایروال (بند ۲۰)
    CURRENT_SSH_PORT=$(ss -tlpn | grep sshd | awk '{print $4}' | cut -d: -f2 | head -n1)
    ufw allow $CURRENT_SSH_PORT/tcp
    ufw allow $HTTP_PORT/tcp
    ufw allow $SOCKS_PORT/tcp
    ufw --force enable

    optimize_system
    install_base
    
    # در اینجا باید کدهای پایتون پنل را از گیت‌هاب کلون کنی
    # git clone https://github.com/youruser/ENJANEB.git /opt/enjaneb
    
    echo -e "${GREEN}Iran Server Base Setup Completed!${NC}"

else
    echo -e "\n${RED}>>> Configuring Kharej Server <<<${NC}"
    optimize_system
    apt install -y wireguard
    echo -e "${GREEN}Kharej Server Ready for Tunneling.${NC}"
fi
