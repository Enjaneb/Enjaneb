import sqlite3
from datetime import datetime

DB_PATH = "/opt/ENJANEB/enjaneb.db"

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE,
            password TEXT,
            traffic_limit_gb REAL,
            used_traffic_bytes INTEGER DEFAULT 0,
            expiry_date TEXT,
            is_active BOOLEAN DEFAULT 1
        )
    ''')
    conn.commit()
    conn.close()

# فراخوانی اولیه برای ساخت فایل دیتابیس
if __name__ == "__main__":
    init_db()
