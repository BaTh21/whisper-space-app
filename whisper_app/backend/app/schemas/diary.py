import base64
from pydantic import BaseModel, ConfigDict, field_serializer, field_validator, model_validator, validator, Field
from typing import Literal, Optional, List, Union
from app.schemas.base import TimestampMixin
from datetime import datetime, timezone

ShareTypeInput = Literal["public", "friends", "group", "personal"]
ShareTypeOutput = str

class CreatorResponse(BaseModel):
    id: int
    username: str
    avatar_url: Optional[str] = None

class GroupResponse(BaseModel):
    id: int
    name: str

class DiaryLikeResponse(BaseModel):
    id: int
    user: CreatorResponse

class DiaryCreate(BaseModel):
    title: str = Field(..., max_length=255)
    content: str = Field(...)
    share_type: str = Field(..., pattern="^(public|friends|group|personal|private)$")
    group_ids: Optional[List[int]] = None
    images: Optional[List[str]] = Field(None, max_length=10)
    videos: Optional[List[str]] = Field(None, max_length=3)
    
    @field_validator('share_type', mode='before')
    @classmethod
    def normalize_share_type(cls, v):
        """Convert 'private' to 'personal' and validate"""
        if isinstance(v, str):
            v = v.strip().lower()
            # Accept "private" but don't convert it here
            # Let the CRUD function handle conversion
            allowed_values = ["public", "friends", "group", "personal", "private"]
            if v not in allowed_values:
                raise ValueError(f'share_type must be one of: {allowed_values}')
        return v
    
    @field_validator('images', 'videos', mode='before')
    @classmethod
    def validate_media_data(cls, v):
        if not v:
            return v
        
        if isinstance(v, str):
            # Check if it's already a URL
            if v.startswith(('http://', 'https://')):
                return v
            
            # Check if it's a data URL
            if v.startswith('data:'):
                if ',' not in v:
                    raise ValueError('Invalid data URL format')
                
                # Validate base64
                header, data = v.split(',', 1)
                try:
                    base64.b64decode(data, validate=True)
                    return v
                except:
                    raise ValueError('Invalid base64 encoding')
            
            # Try to decode as raw base64
            try:
                base64.b64decode(v, validate=True)
                # Determine MIME type
                if len(v) > 1000000:  # More than 1MB, likely video
                    return f"data:video/mp4;base64,{v}"
                else:
                    return f"data:image/jpeg;base64,{v}"
            except:
                raise ValueError('Invalid media data format')
        
        return v
    
    @field_validator('videos')
    @classmethod
    def validate_video_size(cls, v):
        if not v:
            return v
        
        for video in v:
            if video.startswith('data:'):
                header, data = video.split(',', 1)
                size = len(data) * 3 / 4  # Approximate size in bytes
                if size > 50 * 1024 * 1024:  # 50MB
                    raise ValueError('Each video must be less than 50MB')
        
        return v

class DiaryShare(BaseModel):
    group_ids: List[int] = None

class CreateDiaryForGroup(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None
    images: Optional[List[str]] = None
    
    @validator('images')
    def validate_images(cls, v):
        if v is None:
            return v
        for img in v:
            if not img.startswith('data:image/'):
                raise ValueError('Images must be base64 encoded with data URL')
        return v

class CommentReplyResponse(BaseModel):
    id: int
    user: CreatorResponse
    content: str
    images: Optional[List[str]] = None
    created_at: datetime
    parent_id: Optional[int] = None
    
    model_config = ConfigDict(from_attributes=True)
    
class CommentResponse(BaseModel):
    content: str
    created_at: datetime
    user: CreatorResponse
    images: Optional[List[str]] = None
    replies: Optional[List['CommentReplyResponse']] = None
    parent_id: Optional[int] = None
    
    class Config:
        form_attributes = True
    
class DiaryOut(BaseModel):
    id: int
    author: CreatorResponse
    title: Optional[str] = None
    content: Optional[str] = None
    share_type: str
    groups: Optional[List[GroupResponse]] = None
    likes: Optional[List[DiaryLikeResponse]] = None
    is_deleted: Optional[bool] = None
    images: List[str] = Field(default_factory=list)
    videos: List[str] = Field(default_factory=list)
    video_thumbnails: List[Optional[str]] = Field(default_factory=list)
    media_type: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    comments: List[CommentResponse] = Field(default_factory=list)
    favorited_user_ids: List[int] = Field(default_factory=list)
    
    class Config:
        from_attributes=True

class DiaryCommentCreate(BaseModel):
    content: str
    parent_id: Optional[int] = Field(None, ge=1)
    reply_to_user_id: Optional[int] = Field(None, ge=1)
    images: Optional[List[str]] = None
    
    @field_validator('parent_id')
    @classmethod
    def validate_parent_id(cls, v):
        """Convert 0 to None"""
        if v == 0:
            return None
        return v
    
    @field_validator('reply_to_user_id')
    @classmethod
    def validate_reply_to_user_id(cls, v):
        """Convert 0 to None"""
        if v == 0:
            return None
        return v
    
    @validator('images')
    def validate_images(cls, v):
        if v is None:
            return v
        for img in v:
            if not img.startswith('data:image/'):
                raise ValueError('Images must be base64 encoded with data URL')
        return v

class DiaryCommentOut(TimestampMixin):
    id: int
    diary_id: int
    user: CreatorResponse
    content: str
    images: Optional[List[str]] = None
    parent_id: Optional[int] = None
    reply_to_user_id: Optional[int] = None  
    reply_to_user: Optional[CreatorResponse] = None 
    replies: Optional[List['DiaryCommentOut']] = None
    created_at: datetime
    is_edited: bool = False
    updated_at: Optional[datetime] = None 
    model_config = ConfigDict(from_attributes=True)
    
    @field_serializer('created_at')
    def serialize_created_at(self, v: datetime, _info) -> str:
        if v.tzinfo is None:
            return v.isoformat() + 'Z'
        return v.isoformat()

class DiaryUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None
    share_type: Optional[str] = None
    group_ids: Optional[List[int]] = None
    images: Optional[List[str]] = None
    videos: Optional[List[str]] = None
    
    model_config = ConfigDict(from_attributes=True)
    
    @field_validator('share_type', mode='before')
    @classmethod
    def normalize_share_type(cls, v):
        """Normalize share_type to lowercase"""
        if v is None:
            return v
        
        if isinstance(v, str):
            v = v.strip().lower()
            allowed_values = ["public", "friends", "group", "personal"]
            if v not in allowed_values:
                raise ValueError(f"share_type must be one of: {allowed_values}")
        else:
            print(f"⚠️ share_type is not a string: {type(v)}")
        
        return v
    
    @field_validator('group_ids', mode='before')
    @classmethod
    def validate_group_ids(cls, v, info):
        """Validate group_ids when share_type is 'group'"""

        
        if v is None:
            print(f"  group_ids is None, returning None")
            return v
        
        # Get the data being validated
        data = getattr(info, 'data', {})

        
        # Get share_type from data
        share_type = data.get('share_type')

        
        # If share_type is being set to 'group' in this update, require group_ids
        if share_type == 'group':
            print(f"  Share type is 'group', validating group_ids...")
            if not v or len(v) == 0:
                print(f"❌ ERROR: group_ids are required when share_type is 'group'")
                raise ValueError('group_ids are required when share_type is "group"')
            
            if not all(isinstance(gid, int) for gid in v):
                raise ValueError('All group_ids must be integers')
        
        print(f"✅ Validated group_ids: {v}")
        return v
    
    @model_validator(mode='after')
    def check_group_ids_with_share_type(self):
        """Check that group_ids makes sense with share_type"""

        # If group_ids is provided but share_type is not 'group', warn
        if self.group_ids and len(self.group_ids) > 0:
            if self.share_type and self.share_type != 'group':
                print(f"⚠️ WARNING: group_ids provided but share_type is '{self.share_type}' not 'group'")
                print(f"⚠️ These groups may be ignored by the backend")
        
        return self
    
    @field_validator('images', mode='before')
    @classmethod
    def validate_and_process_images(cls, v):
        """Validate images field"""
        if v is None:
            return v
        
        
        # If it's an empty list, return empty list
        if isinstance(v, list) and len(v) == 0:
            return []
        
        if not isinstance(v, list):
            raise ValueError('images must be a list')
        
        if len(v) > 10:
            raise ValueError('Maximum 10 images allowed')
        
        processed_images = []
        for img in v:
            if img is None:
                continue
                
            if isinstance(img, str):
                if (img.startswith('data:image/') or 
                    img.startswith(('http://', 'https://'))):
                    processed_images.append(img)
                else:
                    # Try to validate as base64
                    try:
                        base64.b64decode(img, validate=True)
                        processed_images.append(f"data:image/jpeg;base64,{img}")
                    except:
                        raise ValueError(f'Invalid image format: {img[:50]}...')
            else:
                raise ValueError('Image must be a string')
        
        print(f"✅ Processed {len(processed_images)} images")
        return processed_images
    
    @field_validator('videos', mode='before')
    @classmethod
    def validate_and_process_videos(cls, v):
        """Validate videos field"""
        if v is None:
            return v
        
        
        if isinstance(v, list) and len(v) == 0:
            return []
        
        if not isinstance(v, list):
            raise ValueError('videos must be a list')
        
        if len(v) > 3:
            raise ValueError('Maximum 3 videos allowed')
        
        processed_videos = []
        for vid in v:
            if vid is None:
                continue
                
            if isinstance(vid, str):
                if (vid.startswith('data:video/') or 
                    vid.startswith(('http://', 'https://'))):
                    processed_videos.append(vid)
                else:
                    try:
                        base64.b64decode(vid, validate=True)
                        processed_videos.append(f"data:video/mp4;base64,{vid}")
                    except:
                        raise ValueError(f'Invalid video format: {vid[:50]}...')
            else:
                raise ValueError('Video must be a string')
        
        return processed_videos

class CommentUpdate(BaseModel):
    content: str
    images: Optional[List[str]] = None
    
class DiaryFavoriteResponse(BaseModel):
    id: int
    user_id: int
    diary_id: int
    created_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True 