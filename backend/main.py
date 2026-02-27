import psutil
from fastapi import FastAPI
app = FastAPI()

@app.get("/api/metrics")
def get_metrics():
    return {
        "cpu": psutil.cpu_percent(interval=1),
        "ram": psutil.virtual_memory().percent,
        "status": "Online"
    }
