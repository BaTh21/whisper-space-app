from pydantic import BaseModel, ConfigDict, field_validator
from datetime import datetime
from typing import Optional, List
from enum import Enum

class ShareType(str, Enum):
    PRIVATE = "private"
    PUBLIC = "public"
    SHARED = "shared"

class NoteBase(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    title: str
    content: Optional[str] = None
    is_pinned: bool = False
    is_archived: bool = False
    color: str = "#ffffff"
    share_type: ShareType = ShareType.PRIVATE
    shared_with: List[int] = []
    can_edit: bool = False

    @field_validator('title')
    @classmethod
    def validate_title(cls, v):
        if not v or not v.strip():
            return "Untitled Note"
        return v.strip()

    @field_validator('content')
    @classmethod
    def validate_content(cls, v):
        if v is None:
            return None
        return v.strip() if v.strip() else None

class NoteCreate(NoteBase):
    pass

class NoteUpdate(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    title: Optional[str] = None
    content: Optional[str] = None
    is_pinned: Optional[bool] = None
    is_archived: Optional[bool] = None
    color: Optional[str] = None
    share_type: Optional[ShareType] = None
    shared_with: Optional[List[int]] = None
    can_edit: Optional[bool] = None

# Add the missing schemas
class ShareNoteRequest(BaseModel):
    share_type: ShareType
    friend_ids: Optional[List[int]] = None
    can_edit: bool = False
    expires_in_hours: Optional[int] = None

class PublicNoteOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    
    id: int
    title: str
    content: Optional[str] = None
    color: str = "#ffffff"
    created_at: datetime
    updated_at: Optional[datetime] = None
    
class UserResponse(BaseModel):
    id: int
    username: str
    avatar_url: Optional[str] = None
    
    model_config = ConfigDict(from_attributes=True)

class NoteOut(NoteBase):
    id: int
    user: UserResponse
    share_token: Optional[str] = None
    share_expires: Optional[datetime] = None
    created_at: datetime
    updated_at: Optional[datetime] = None