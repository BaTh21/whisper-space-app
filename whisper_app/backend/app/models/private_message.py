from sqlalchemy import Column, Enum, Boolean, DateTime, Float, ForeignKey, Text, Integer, String
from sqlalchemy.orm import relationship
from app.models.base import Base
from datetime import datetime
import enum

class MessageType(enum.Enum):
    text = "text"
    image = "image"
    file = "file"
    voice = "voice"
    system = "system"

class PrivateMessage(Base):
    __tablename__ = "private_messages"

    id = Column(Integer, primary_key=True, autoincrement=True)
    sender_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    receiver_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    content = Column(Text, nullable=False)
    message_type = Column(Enum(MessageType), default=MessageType.text)
    is_read = Column(Boolean, default=False)
    read_at = Column(DateTime(timezone=True), nullable=True)
    delivered_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, index=True)
    # updated_at = Column(DateTime(timezone=True), nullable=True, onupdate=datetime.utcnow)
    edited_at = Column(DateTime(timezone=True), nullable=True)
    reply_to_id = Column(Integer, ForeignKey("private_messages.id", ondelete="SET NULL"), nullable=True)
    is_forwarded = Column(Boolean, default=False)
    original_sender = Column(String(255), nullable=True)
    original_sender_avatar = Column(String(255), nullable=True)
    voice_duration = Column(Float, nullable=True)
    file_size = Column(Integer, nullable=True)  
    forwarded_from_id = Column(Integer, ForeignKey("users.id"), nullable=True)

    # FIXED: Self-referencing relationship for replies
    reply_to = relationship(
        "PrivateMessage",
        remote_side=[id],
        backref="replies",
        foreign_keys=[reply_to_id],
        post_update=True
    )

    # Sender and receiver relationships
    sender = relationship("User", foreign_keys=[sender_id], backref="sent_messages")
    receiver = relationship("User", foreign_keys=[receiver_id], backref="received_messages")
    reactions = relationship("MessageReaction", 
                         back_populates="message", 
                         cascade="all, delete-orphan",
                         lazy="selectin") 

    # Many-to-many relationship for seen users (read-only)
    seen_by_users = relationship(
        "User",
        secondary="message_seen_status",
        back_populates="seen_messages",
        viewonly=True
    )

    # Relationship to seen statuses (for creating/updating)
    seen_statuses = relationship(
        "MessageSeenStatus",
        back_populates="message",
        cascade="all, delete-orphan"
    )
