from sqlalchemy import ARRAY, Column, String, Text, DateTime, ForeignKey, Integer, Boolean
from sqlalchemy.orm import relationship
from datetime import datetime
from app.models.base import Base

class DiaryComment(Base):
    __tablename__ = "diary_comments"

    id = Column(Integer, primary_key=True, autoincrement=True)
    diary_id = Column(Integer, ForeignKey("diaries.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    content = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    is_edited = Column(Boolean, default=False)
    
    parent_id = Column(Integer, ForeignKey("diary_comments.id", ondelete="CASCADE"), nullable=True)
    reply_to_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    images = Column(ARRAY(String), nullable=True, default=list)

    # Relationships - ALL WITH EXPLICIT FOREIGN KEYS
    diary = relationship("Diary", back_populates="comments")
    
    # User who created the comment
    user = relationship(
        "User", 
        foreign_keys=[user_id],
        back_populates="diary_comments"
    )
    
    # User being replied to
    reply_to_user = relationship(
        "User", 
        foreign_keys=[reply_to_user_id],
        back_populates="comments_replied_to"
    )
    
    parent = relationship(
        "DiaryComment", 
        remote_side=[id], 
        backref="replies"
    )