from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import psutil
import sqlite3
import os

app = FastAPI()

# مسیر دیتابیس
DB_PATH = "/opt/ENJANEB/enjaneb.db"

class UserCreate(BaseModel):
    username: str
    password: str
    limit_gb: float
    expiry: str

# API برای دریافت وضعیت سیستم (بند 53، 54)
@app.get("/api/metrics")
def get_metrics():
    return {
        "cpu": psutil.cpu_percent(interval=1),
        "ram": psutil.virtual_memory().percent,
        "net": psutil.net_io_counters().bytes_sent + psutil.net_io_counters().bytes_recv,
        "status": "Online"
    }

# API برای لیست کاربران (بند 56)
@app.get("/api/users")
def get_users():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    users = cursor.execute("SELECT * FROM users").fetchall()
    conn.close()
    return [dict(u) for u in users]

# API برای ساخت کاربر جدید (بند 57)
@app.post("/api/users/add")
def add_user(user: UserCreate):
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("INSERT INTO users (username, password, traffic_limit_gb, expiry_date) VALUES (?, ?, ?, ?)",
                       (user.username, user.password, user.limit_gb, user.expiry))
        conn.commit()
        conn.close()
        return {"message": "User added successfully"}
    except Exception as e:
        raise HTTPException(status_code=400, detail="Error: User might already exist")

# اتصال به فایل‌های گرافیکی داشبورد (این بخش مشکل Not Found را حل می‌کند)
# حتماً این بخش باید آخرین خطوط کد باشد
if os.path.exists("/opt/ENJANEB/dashboard"):
    app.mount("/", StaticFiles(directory="/opt/ENJANEB/dashboard", html=True), name="dashboard")
