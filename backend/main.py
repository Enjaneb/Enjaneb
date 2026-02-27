from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import psutil
import sqlite3
import os
import subprocess

app = FastAPI()

# مسیر دیتابیس پروژه
DB_PATH = "/opt/ENJANEB/enjaneb.db"

class UserCreate(BaseModel):
    username: str
    password: str
    limit_gb: float
    expiry: str

# --- بخش مدیریت هسته پروکسی (Gost) ---
def start_proxy_engine():
    try:
        # 1. خواندن یوزرها از دیتابیس و نوشتن در فایل متنی برای Gost
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        users = cursor.execute("SELECT username, password FROM users").fetchall()
        conn.close()
        
        # ساخت فایل یوزرها
        with open("/opt/ENJANEB/users.txt", "w") as f:
            for u in users:
                f.write(f"{u[0]}:{u[1]}\n")
        
        # 2. بستن Gost قبلی (اگه باز باشه) و اجرای مجدد برای اعمال تغییرات
        subprocess.run(["pkill", "-f", "gost"], stderr=subprocess.DEVNULL)
        
        # اجرای Gost روی پورت 8080 (پشتیبانی از HTTP و SOCKS5)
        # یوزرها رو از فایل users.txt که بالا ساختیم میخونه
        cmd = "/usr/local/bin/gost -L=http://:8080?auth=/opt/ENJANEB/users.txt -L=socks5://:8080?auth=/opt/ENJANEB/users.txt &"
        subprocess.Popen(cmd, shell=True)
        print("Proxy Engine Started on Port 8080")
    except Exception as e:
        print(f"Error starting proxy: {e}")

# اجرای پروکسی به محض بالا آمدن برنامه
@app.on_event("startup")
async def startup_event():
    start_proxy_engine()

# --- بخش API ها ---

@app.get("/api/metrics")
def get_metrics():
    return {
        "cpu": psutil.cpu_percent(interval=1),
        "ram": psutil.virtual_memory().percent,
        "status": "Online"
    }

@app.get("/api/users")
def get_users():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    users = cursor.execute("SELECT * FROM users").fetchall()
    conn.close()
    return [dict(u) for u in users]

@app.post("/api/users/add")
def add_user(user: UserCreate):
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("INSERT INTO users (username, password, traffic_limit_gb, expiry_date) VALUES (?, ?, ?, ?)",
                       (user.username, user.password, user.limit_gb, user.expiry))
        conn.commit()
        conn.close()
        
        # بعد از ساخت یوزر، لیست پروکسی رو آپدیت کن
        start_proxy_engine()
        return {"message": "User added and Proxy updated"}
    except Exception as e:
        raise HTTPException(status_code=400, detail="User already exists or DB error")

# اتصال به داشبورد (فایل‌های HTML)
if os.path.exists("/opt/ENJANEB/dashboard"):
    app.mount("/", StaticFiles(directory="/opt/ENJANEB/dashboard", html=True), name="dashboard")
