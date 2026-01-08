from sqlalchemy import Boolean, Column, Integer, ForeignKey, DateTime
from datetime import datetime
from app.models.base import Base
from sqlalchemy.orm import relationship

class GroupMessageSeen(Base):
    __tablename__ = "group_message_seen"

    id = Column(Integer, primary_key=True, autoincrement=True)
    message_id = Column(Integer, ForeignKey("group_messages.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    seen = Column(Boolean, default=False)
    seen_at = Column(DateTime, default= datetime.utcnow())

    message = relationship("GroupMessage", back_populates="seen_by")
    user = relationship("User")
