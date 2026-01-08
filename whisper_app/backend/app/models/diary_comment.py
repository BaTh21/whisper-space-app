from sqlalchemy import ARRAY, Column, String, Text, DateTime, ForeignKey, Integer
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
    
    parent_id = Column(Integer, ForeignKey("diary_comments.id", ondelete="CASCADE"), nullable=True)
    images = Column(ARRAY(String), nullable=True, default=list)

    diary = relationship("Diary", back_populates="comments")
    user = relationship("User", backref="diary_comments")
    parent = relationship("DiaryComment", remote_side=[id], backref="replies")