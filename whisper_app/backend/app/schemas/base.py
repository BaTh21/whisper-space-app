from pydantic import BaseModel
from typing import Optional, TypeVar
from datetime import datetime

T = TypeVar("T")

class BaseResponse(BaseModel):
    msg: str
    success: bool = True

class TimestampMixin(BaseModel):
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True