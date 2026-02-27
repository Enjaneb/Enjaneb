from sqlalchemy import create_all, Column, Integer, String, Boolean, Float
from sqlalchemy.ext.declarative import declarative_base

Base = declarative_base()

class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True)
    username = Column(String, unique=True)
    password = Column(String)
    traffic_limit = Column(Float) # GB
    used_traffic = Column(Float, default=0.0) # Bytes
    expiry_date = Column(String)
    is_active = Column(Boolean, default=True)

# برای شروع سریع در SQLite
# Base.metadata.create_all(engine)
