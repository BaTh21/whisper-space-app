from sqlalchemy import Column, DateTime, ForeignKey, Integer
from sqlalchemy.orm import relationship
from datetime import datetime
from app.models.base import Base

class DiaryLike(Base):
    __tablename__ = "diary_likes"

    id = Column(Integer, primary_key=True, nullable=False, autoincrement=True)
    diary_id = Column(Integer, ForeignKey("diaries.id", ondelete="CASCADE"), primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    diary = relationship("Diary", back_populates="likes")
    user = relationship("User", back_populates="diary_likes")
