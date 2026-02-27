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
        # 1. استخراج یوزرها از دیتابیس
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        users = cursor.execute("SELECT username, password FROM users").fetchall()
        conn.close()
        
        # 2. ساخت فایل احراز هویت برای Gost
        auth_file = "/opt/ENJANEB/users.txt"
        with open(auth_file, "w") as f:
            for u in users:
                f.write(f"{u[0]}:{u[1]}\n")
        
        # 3. بستن Gost قبلی و اجرای نسخه ایمن (با فایل auth)
        subprocess.run(["pkill", "-9", "gost"], stderr=subprocess.DEVNULL)
        
        # اجرای Gost که یوزر/پسورد رو چک می‌کنه
        cmd = f"nohup /usr/local/bin/gost -L=http://:8080?auth={auth_file} -L=socks5://:8080?auth={auth_file} > /opt/ENJANEB/gost.log 2>&1 &"
        subprocess.Popen(cmd, shell=True)
        print("Secure Proxy Started.")
    except Exception as e:
        print(f"Error: {e}")

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
    start_proxy_engine() # آپدیت آنی پروکسی
    return {"message": "User added"}

if os.path.exists("/opt/ENJANEB/dashboard"):
    app.mount("/", StaticFiles(directory="/opt/ENJANEB/dashboard", html=True), name="dashboard")
