from sqlalchemy.orm import Session
from sqlalchemy import desc, func
from typing import List, Optional
from datetime import datetime, timedelta
from app.models.system_log import SystemLog
from app.schemas.system_log import SystemLogCreate


def create_log(db: Session, log_data: SystemLogCreate) -> SystemLog:
    db_log = SystemLog(**log_data.dict())
    db.add(db_log)
    db.commit()
    db.refresh(db_log)
    return db_log


def get_user_logs(
    db: Session,
    user_id: int,
    action: Optional[str] = None,
    limit: int = 50
) -> List[SystemLog]:
    query = db.query(SystemLog).filter(SystemLog.user_id == user_id)
    
    if action:
        query = query.filter(SystemLog.action == action)
    
    return query.order_by(desc(SystemLog.created_at)).limit(limit).all()


def get_user_devices(db: Session, user_id: int) -> List[SystemLog]:
    subquery = (
        db.query(
            SystemLog.ip_address,
            SystemLog.user_agent,
            func.max(SystemLog.created_at).label('latest_login')
        )
        .filter(SystemLog.user_id == user_id)
        .filter(SystemLog.action == "login")
        .group_by(SystemLog.ip_address, SystemLog.user_agent)
        .subquery()
    )
    
    devices = (
        db.query(SystemLog)
        .join(
            subquery,
            (SystemLog.ip_address == subquery.c.ip_address) &
            (SystemLog.user_agent == subquery.c.user_agent) &
            (SystemLog.created_at == subquery.c.latest_login)
        )
        .filter(SystemLog.user_id == user_id)
        .order_by(desc(SystemLog.created_at))
        .all()
    )
    
    return devices


def log_user_activity(
    db: Session,
    user_id: int,
    action: str,
    ip_address: str = None,
    user_agent: str = None
) -> SystemLog:
    from app.services.device_detector import DeviceDetector
    
    device_info = DeviceDetector.get_device_info(user_agent, ip_address)
    
    log_data = SystemLogCreate(
        user_id=user_id,
        action=action,
        ip_address=ip_address,
        user_agent=user_agent,
        device_type=device_info["device_type"],
        browser=device_info["browser"],
        os=device_info["os"],
        device_name=device_info["device_name"]
    )
    
    return create_log(db, log_data)