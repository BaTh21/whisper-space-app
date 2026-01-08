# app/models/friend.py - CORRECTED VERSION
from sqlalchemy import Column, Integer, String, Enum, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.services.websocket_manager import manager
import enum

from app.models.base import Base

class FriendshipStatus(enum.Enum):
    pending = "pending"
    accepted = "accepted"
    blocked = "blocked"

class Friend(Base):
    __tablename__ = "friends"
    
    # Primary key with auto-increment
    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    friend_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    
    status = Column(Enum(FriendshipStatus), default=FriendshipStatus.pending)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    
    # Relationships
    user = relationship("User", foreign_keys=[user_id], backref="friends_sent")
    friend = relationship("User", foreign_keys=[friend_id], backref="friends_received")
    
    # Composite unique constraint to prevent duplicate friendships
    __table_args__ = (
        UniqueConstraint('user_id', 'friend_id', name='unique_friendship'),
        UniqueConstraint("friend_id", "user_id", name="unique_reverse_friendship"),
    )