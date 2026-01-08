from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from app.core.database import get_db
from app.core.security import get_current_user
from app.crud.system_log import get_user_logs, get_user_devices
from app.schemas.system_log import SystemLogOut, DeviceInfo
from app.models.user import User

router = APIRouter(prefix="/devices", tags=["devices"])


@router.get("/logs", response_model=List[SystemLogOut])
def get_my_logs(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    action: str = None,
    limit: int = 50
):
    logs = get_user_logs(db, current_user.id, action, limit)
    return logs


@router.get("/my-devices", response_model=List[DeviceInfo])
def get_my_devices(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    devices = get_user_devices(db, current_user.id)
    
    result = []
    for device in devices:
        result.append(DeviceInfo(
            id=device.id,
            ip_address=device.ip_address or "Unknown",
            device_type=device.device_type or "Unknown",
            browser=device.browser or "Unknown",
            os=device.os or "Unknown",
            device_name=device.device_name or "Unknown",
            last_login=device.created_at
        ))
    
    return result