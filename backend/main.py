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
        # 1. خواندن یوزرها
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        users = cursor.execute("SELECT username, password FROM users").fetchall()
        conn.close()
        
        auth_file = "/opt/ENJANEB/users.txt"
        with open(auth_file, "w") as f:
            for u in users:
                f.write(f"{u[0]}:{u[1]}\n")
        
        # 2. ریست کردن پروسه‌ها
        os.system("pkill -9 gost")
        
        # 3. اجرای HTTP روی 8080
        os.system(f"nohup /usr/local/bin/gost -L=http://:8080?auth={auth_file} > /opt/ENJANEB/http.log 2>&1 &")
        
        # 4. اجرای SOCKS5 روی 1080 (جداگانه برای پایداری بیشتر)
        os.system(f"nohup /usr/local/bin/gost -L=socks5://:1080?auth={auth_file} > /opt/ENJANEB/socks.log 2>&1 &")
        
        # 5. اجرای MTProto روی 443
        secret = "ee00000000000000000000000000000000"
        os.system(f"nohup /usr/local/bin/gost -L=mtls://:443?secret={secret} > /opt/ENJANEB/mtp.log 2>&1 &")
        
    except Exception as e:
        print(f"Error: {e}")

@app.on_event("startup")
async def startup_event():
    start_proxy_engine()

# بقیه توابع (metrics, users, add_user) ثابت بماند...
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
    return {"message": "User added and all proxies updated"}

if os.path.exists("/opt/ENJANEB/dashboard"):
    app.mount("/", StaticFiles(directory="/opt/ENJANEB/dashboard", html=True), name="dashboard")
