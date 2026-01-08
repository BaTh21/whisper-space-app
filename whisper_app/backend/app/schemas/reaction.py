from pydantic import BaseModel, Field, validator
from datetime import datetime
from typing import Optional, List
import re

class ReactionCreate(BaseModel):
    emoji: str = Field(..., min_length=1, max_length=10, description="Emoji character")
    
    @validator('emoji')
    def validate_emoji(cls, v):
        # Basic emoji validation - check if it's likely an emoji
        # This is a simple check; emojis can be complex (multi-character)
        if not v.strip():
            raise ValueError("Emoji cannot be empty")
        
        # Check if it contains at least one emoji character
        # This regex matches most emojis (simplified version)
        emoji_pattern = re.compile(
            "["
            "\U0001F600-\U0001F64F"  # emoticons
            "\U0001F300-\U0001F5FF"  # symbols & pictographs
            "\U0001F680-\U0001F6FF"  # transport & map symbols
            "\U0001F1E0-\U0001F1FF"  # flags (iOS)
            "\U00002702-\U000027B0"  # dingbats
            "\U000024C2-\U0001F251" 
            "]+", 
            flags=re.UNICODE
        )
        
        if not emoji_pattern.search(v):
            # Allow common single-character emojis that might not match the regex
            if len(v) <= 2:  # Most emojis are 1-2 characters
                return v
            raise ValueError("Invalid emoji format")
        
        return v

class UserReaction(BaseModel):
    id: int
    username: str
    avatar_url: Optional[str] = None
    
    class Config:
        from_attributes = True

class ReactionOut(BaseModel):
    id: int
    message_id: int
    user_id: int
    emoji: str
    created_at: datetime
    user: UserReaction
    
    class Config:
        from_attributes = True

class ReactionDeleteResponse(BaseModel):
    status: str = "success"
    message: str = "Reaction removed"
    message_id: int
    reaction_id: int

class MessageReactionsResponse(BaseModel):
    message_id: int
    reactions: List[ReactionOut]
    total_count: int