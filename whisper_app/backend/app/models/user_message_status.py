# app/models/user_message_status.py
from sqlalchemy import Column, Boolean, Integer, ForeignKey
from app.models.base import Base

class UserMessageStatus(Base):
    __tablename__ = "user_message_status"

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    message_id = Column(Integer, ForeignKey("private_messages.id", ondelete="CASCADE"), primary_key=True)
    is_deleted = Column(Boolean, default=False)