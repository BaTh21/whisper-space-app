from sqlalchemy import Column, DateTime, ForeignKey, Integer, UniqueConstraint
from sqlalchemy.orm import relationship
from datetime import datetime
from app.models.base import Base

class DiaryLike(Base):
    __tablename__ = "diary_likes"

    id = Column(Integer, primary_key=True, autoincrement=True)
    diary_id = Column(Integer, ForeignKey("diaries.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    diary = relationship("Diary", back_populates="likes")
    user = relationship("User", back_populates="diary_likes")

    __table_args__ = (
        UniqueConstraint('diary_id', 'user_id', name='unique_diary_user_like'),
    )
