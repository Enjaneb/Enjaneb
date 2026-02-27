import os

def generate_gost_command(http_port=8080, socks_port=1080, remote_ip=None):
    # این تابع دستور اجرای پروکسی رو می‌سازه
    # اگر آی‌پی خارج ست شده باشه، ترافیک رو تانل می‌کنه
    auth = "admin:1234" # یوزر و پسورد پیش‌فرض
    
    command = f"/usr/local/bin/gost -L=http://{auth}@:{http_port} -L=socks5://{auth}@:{socks_port}"
    
    if remote_ip:
        # بند 4: هدایت تمام ترافیک به سرور خارج
        command += f" -F=socks5://{remote_ip}:1000" 
        
    return command

# این کد بعداً توسط main.py فراخوانی می‌شه
