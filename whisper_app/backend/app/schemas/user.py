from pydantic import BaseModel, EmailStr
from typing import Optional
from app.schemas.base import BaseResponse, TimestampMixin


class UserBase(BaseModel):
    username: str
    email: EmailStr
    avatar_url: Optional[str] = None

class UserOut(UserBase, TimestampMixin):
    id: int
    is_verified: bool
    avatar_url: Optional[str] = None
    bio: Optional[str] = None


class UserUpdate(BaseModel):
    username: Optional[str] = None
    bio: Optional[str] = None
    avatar_url: Optional[str] = None
    
class AvatarUploadResponse(BaseResponse):
    avatar_url: Optional[str] = None
    filename: Optional[str] = None

class AvatarDeleteResponse(BaseResponse):
    pass