from fastapi import FastAPI, HTTPException
import sqlite3
from pydantic import BaseModel
from typing import List

app = FastAPI()
DB_PATH = "/opt/ENJANEB/enjaneb.db"

class UserCreate(BaseModel):
    username: str
    password: str
    limit_gb: float
    expiry: str

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
        return {"message": "User added successfully"}
    except:
        raise HTTPException(status_code=400, detail="User already exists")
