from sqlalchemy import ARRAY, Column, Enum, String, Text, Boolean, DateTime, ForeignKey, Integer, UniqueConstraint
from app.models.base import Base
from datetime import datetime, timezone  
from sqlalchemy.orm import relationship

class DiaryFavorite(Base):
    __tablename__ = "diary_favorites"

    id = Column(Integer, primary_key=True, autoincrement=True)
    diary_id = Column(Integer, ForeignKey("diaries.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    diary = relationship("Diary", back_populates="favorited_by")
    user = relationship("User", back_populates="favorite_diaries")

    __table_args__ = (
        UniqueConstraint('diary_id', 'user_id', name='unique_diary_user_favorite'),
    )
