from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class UserResponse(BaseModel):
    id: int
    username: str
    avatar_url: Optional[str] = None

class ActivityBase(BaseModel):
    id: int
    type: str
    actor: UserResponse
    recipient: UserResponse
    created_at: datetime
    is_read: bool
    post_id: Optional[int] = None
    comment_id: Optional[int] = None
    friend_request_id: Optional[int] = None
    group_id: Optional[int] = None
    extra_data: str

class ActivityDeleteRequest(BaseModel):
    ids: List[int]