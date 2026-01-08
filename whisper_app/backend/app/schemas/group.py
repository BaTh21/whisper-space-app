from datetime import datetime
from time import timezone
from pydantic import BaseModel, ConfigDict
from typing import List, Optional, Literal
from app.schemas.base import TimestampMixin
from app.schemas.user import UserOut

MessageType = Literal["text", "image", "file"]

class GroupCreate(BaseModel):
    name: str
    description: Optional[str] = None
    invite_user_ids: List[int] = []
    
class ImageResponse(BaseModel):
    id: int
    url: str
    uploaded_by: int
    created_at: datetime

class GroupOut(TimestampMixin):
    id: int
    name: str
    creator_id: int
    description: Optional[str] = None
    images: Optional[List[ImageResponse]] = []
    
    class Config:
        from_attributes = True
        
class GroupDetailsOut(TimestampMixin):
    id: int
    name: str
    creator_id: int
    description: Optional[str] = None
    images: Optional[List[ImageResponse]] = []
    
    class Config:
        from_attributes = True
        
class GroupInviteOut(BaseModel):
    id: int
    group: GroupOut
    inviter: UserOut
    created_at: datetime

    class Config:
        from_attributes = True

class GroupMessageCreate(BaseModel):
    content: str
    message_type: MessageType = "text"
    
class GroupMessageUpdate(BaseModel):
    content: str

class GroupMessageOut(TimestampMixin):
    id: int
    sender_id: int
    group_id: int
    content: str
    message_type: MessageType

    model_config = ConfigDict(
        from_attributes=True,
        json_encoders={
            datetime: lambda dt: (
                dt.replace(tzinfo=datetime.timezone.utc) if dt.tzinfo is None
                else dt.astimezone(timezone.utc)
            ).isoformat().replace("+00:00", "Z")
        }
    )
    
class GroupMessageResponse(BaseModel):
    id: int
    sender_id: int
    group_id: int
    content: Optional[str] = None
    message_type: str
    created_at: datetime
    updated_at: Optional[datetime] = None
    file_url: Optional[str] = None
    voice_url: Optional[str] = None
    # public_id: Optional[str] = None
    
    class Config:
        form_attributes= True
    
class GroupUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    
class UserResponse(BaseModel):
    id: int
    username: str
    
class GroupResponse(BaseModel):
    id: int
    name: str
    
class GroupInviteResponse(BaseModel):
    id: int
    group_id: int
    inviter_id: int
    invitee_id: int
    status: str
    invite_token: str
    created_at: datetime
    expires_at: datetime
    
    # Include related objects
    group: Optional[GroupResponse] = None
    inviter: Optional[UserResponse] = None
    invitee: Optional[UserResponse] = None
    
    class Config:
        from_attributes = True
    
class GroupImageResponse(BaseModel):
    id: int
    group_id: int
    public_id: str
    url: str
    uploaded_by: int
    created_at: datetime
    
    class Config:
        orm_mode = True