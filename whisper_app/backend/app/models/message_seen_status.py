from sqlalchemy import Column, Integer, ForeignKey, DateTime, Boolean
from sqlalchemy.orm import relationship
from app.models.base import Base
from datetime import datetime

class MessageSeenStatus(Base):
    __tablename__ = "message_seen_status"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    message_id = Column(Integer, ForeignKey("private_messages.id", ondelete="CASCADE"), nullable=False)  # ADD CASCADE
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    seen_at = Column(DateTime(timezone=True), default=datetime.utcnow)
    
    # Relationships with back_populates
    message = relationship("PrivateMessage", back_populates="seen_statuses")
    user = relationship("User", back_populates="seen_message_statuses")