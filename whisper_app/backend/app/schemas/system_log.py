from pydantic import BaseModel
from datetime import datetime
from typing import Optional


class SystemLogBase(BaseModel):
    action: str
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    device_type: Optional[str] = None
    browser: Optional[str] = None
    os: Optional[str] = None
    device_name: Optional[str] = None


class SystemLogCreate(SystemLogBase):
    user_id: int


class SystemLogOut(SystemLogBase):
    id: int
    user_id: int
    created_at: datetime

    class Config:
        from_attributes = True


class DeviceInfo(BaseModel):
    id: int
    ip_address: str
    device_type: str
    browser: str
    os: str
    device_name: str
    last_login: datetime