from sqlalchemy import Column, Integer, String, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
from sqlalchemy.sql import func

from app.models.base import Base

class MessageReaction(Base):
    __tablename__ = "message_reactions"
    
    id = Column(Integer, primary_key=True, index=True)
    message_id = Column(Integer, ForeignKey("private_messages.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    emoji = Column(String(10), nullable=False)  # Emoji character (supports up to 10 chars for complex emojis)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    message = relationship("PrivateMessage", back_populates="reactions")
    user = relationship("User", back_populates="message_reactions")
    
    def __repr__(self):
        return f"<MessageReaction {self.id}: {self.emoji} on message {self.message_id} by user {self.user_id}>"