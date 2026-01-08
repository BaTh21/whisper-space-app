from sqlalchemy import Column, Integer, ForeignKey, Text, DateTime, Enum, String
from sqlalchemy.orm import relationship
from datetime import datetime
from app.models.base import Base
from app.models.group_message import MessageType

class GroupMessageReply(Base):
    __tablename__ = "group_message_replies"

    id = Column(Integer, primary_key=True, autoincrement=True)
    message_id = Column(Integer, ForeignKey("group_messages.id", ondelete="CASCADE"), nullable=False)
    sender_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    content = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at = Column(DateTime())
    message_type = Column(Enum(MessageType), default=MessageType.text)
    file_url = Column(String(255), nullable=True)
    public_id = Column(String(255), nullable=True)

    message = relationship("GroupMessage", back_populates="replies")
    sender = relationship("User")