from sqlalchemy import Column, String, Boolean, DateTime, Text, Integer
from app.models.base import Base
from datetime import datetime
from sqlalchemy.orm import relationship

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, autoincrement=True)
    username = Column(String(50), unique=True, nullable=False)
    email = Column(String(255), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    is_verified = Column(Boolean, default=False)
    avatar_url = Column(String(255))
    bio = Column(Text)
    online_status = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    diaries = relationship("Diary", back_populates="author")
    diary_likes = relationship("DiaryLike", back_populates="user", cascade="all, delete-orphan")
    favorite_diaries = relationship("DiaryFavorite", back_populates="user", cascade="all, delete-orphan")
    seen_messages = relationship("PrivateMessage", secondary="message_seen_status", back_populates="seen_by_users")
    
    is_online = Column(Boolean, default=False)
    last_seen = Column(DateTime(timezone=True), default=datetime.utcnow)
    last_activity = Column(DateTime(timezone=True), default=datetime.utcnow)

    message_reactions = relationship("MessageReaction", 
                                 back_populates="user", 
                                 cascade="all, delete-orphan")
# Relationship to seen message statuses
    seen_message_statuses = relationship(
        "MessageSeenStatus", 
        back_populates="user",
        cascade="all, delete-orphan"
    )
    
    # Many-to-many relationship to seen messages (read-only)
    seen_messages = relationship(
        "PrivateMessage",
        secondary="message_seen_status",
        back_populates="seen_by_users",
        viewonly=True  # This is read-only
    )
    
    activities_sent = relationship(
        "Activity",
        foreign_keys="[Activity.actor_id]",
        back_populates="actor"
    )
    activities_received = relationship(
        "Activity",
        foreign_keys="[Activity.recipient_id]",
        back_populates="recipient"
    )

    favorite_diaries = relationship(
        "DiaryFavorite",
        back_populates="user",
        cascade="all, delete-orphan"
    )


