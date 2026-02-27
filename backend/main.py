from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import psutil
import sqlite3
import os
import subprocess

app = FastAPI()
DB_PATH = "/opt/ENJANEB/enjaneb.db"

class UserCreate(BaseModel):
    username: str
    password: str
    limit_gb: float
    expiry: str

def start_proxy_engine():
    try:
        # 1. آماده‌سازی فایل یوزرها
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        users = cursor.execute("SELECT username, password FROM users").fetchall()
        conn.close()
        
        auth_file = "/opt/ENJANEB/users.txt"
        with open(auth_file, "w") as f:
            for u in users:
                f.write(f"{u[0]}:{u[1]}\n")
        
        # 2. بستن تمام پروسه‌های قبلی Gost
        os.system("pkill -9 gost")
        
        # 3. اجرای HTTP و SOCKS5 روی پورت 8080
        cmd_proxy = f"nohup /usr/local/bin/gost -L=http://:8080?auth={auth_file} -L=socks5://:8080?auth={auth_file} > /opt/ENJANEB/proxy.log 2>&1 &"
        os.system(cmd_proxy)
        
        # 4. اجرای MTProto روی پورت 443 (مخصوص تلگرام)
        # یوزرنیم و پسورد MTProto را فعلاً ثابت می‌گذاریم یا می‌توانید طبق الگوی بالا تغییر دهید
        secret = "ee00000000000000000000000000000000" # سکرت استاندارد
        cmd_mtp = f"nohup /usr/local/bin/gost -L=mtls://:443?secret={secret} > /opt/ENJANEB/mtp.log 2>&1 &"
        os.system(cmd_mtp)
        
        print("All Engines (HTTP, SOCKS5, MTProto) Started.")
    except Exception as e:
        print(f"Error starting engines: {e}")

@app.on_event("startup")
async def startup_event():
    start_proxy_engine()

@app.get("/api/metrics")
def get_metrics():
    return {"cpu": psutil.cpu_percent(interval=1), "ram": psutil.virtual_memory().percent, "status": "Online"}

@app.get("/api/users")
def get_users():
    conn = sqlite3.connect(DB_PATH); conn.row_factory = sqlite3.Row
    users = conn.cursor().execute("SELECT * FROM users").fetchall()
    conn.close()
    return [dict(u) for u in users]

@app.post("/api/users/add")
def add_user(user: UserCreate):
    conn = sqlite3.connect(DB_PATH)
    conn.cursor().execute("INSERT INTO users (username, password, traffic_limit_gb, expiry_date) VALUES (?, ?, ?, ?)",
                   (user.username, user.password, user.limit_gb, user.expiry))
    conn.commit(); conn.close()
    start_proxy_engine()
    return {"message": "User added and proxies updated"}

if os.path.exists("/opt/ENJANEB/dashboard"):
    app.mount("/", StaticFiles(directory="/opt/ENJANEB/dashboard", html=True), name="dashboard")
