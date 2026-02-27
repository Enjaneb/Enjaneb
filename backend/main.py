import os
import sqlite3
import subprocess
import psutil
import time
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

app = FastAPI()
DB_PATH = "/opt/ENJANEB/enjaneb.db"

class UserCreate(BaseModel):
    username: str
    password: str
    limit_gb: float
    expiry: str

def start_proxy_engine():
    try:
        # 1. خواندن یوزرها از دیتابیس
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        users = cursor.execute("SELECT username, password FROM users").fetchall()
        conn.close()
        
        # 2. نوشتن یوزرها در فایل با تمیزکاری کامل (برای جلوگیری از خطای base64)
        auth_file = "/opt/ENJANEB/users.txt"
        with open(auth_file, "w") as f:
            for u in users:
                uname = str(u[0]).strip()
                upass = str(u[1]).strip()
                if uname and upass:
                    f.write(f"{uname}:{upass}\n")
        
        # 3. توقف تمام پروسه‌های قبلی Gost
        os.system("pkill -9 gost")
        time.sleep(1) # زمان برای آزاد شدن پورت‌ها توسط لینوکس

        gost_path = "/usr/local/bin/gost"
        auth_param = f"?auth={auth_file}"

        # 4. اجرای پروتکل‌ها روی پورت‌های مجزا
        # HTTP روی پورت 8080
        subprocess.Popen(f"nohup {gost_path} -L=http://:8080{auth_param} > /dev/null 2>&1 &", shell=True)
        
        # SOCKS5 روی پورت 1080
        subprocess.Popen(f"nohup {gost_path} -L=socks5://:1080{auth_param} > /dev/null 2>&1 &", shell=True)
        
        # MTProto روی پورت 443
        secret = "ee00000000000000000000000000000000"
        subprocess.Popen(f"nohup {gost_path} -L=mtls://:443?secret={secret} > /dev/null 2>&1 &", shell=True)
        
        print("All Engines (8080, 1080, 443) Started successfully.")
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
    start_proxy_engine()
    return {"message": "User added and engine updated"}

if os.path.exists("/opt/ENJANEB/dashboard"):
    app.mount("/", StaticFiles(directory="/opt/ENJANEB/dashboard", html=True), name="dashboard")
