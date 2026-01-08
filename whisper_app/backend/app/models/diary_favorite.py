from sqlalchemy import ARRAY, Column, Enum, String, Text, Boolean, DateTime, ForeignKey, Integer, UniqueConstraint
from app.models.base import Base
from datetime import datetime, timezone  
from sqlalchemy.orm import relationship

class DiaryFavorite(Base):
    __tablename__ = "diary_favorites"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    diary_id = Column(Integer, ForeignKey("diaries.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        UniqueConstraint("user_id", "diary_id", name="unique_user_diary_favorite"),
    )

    user = relationship("User", back_populates="favorite_diaries")
    diary = relationship("Diary", back_populates="favorited_by")
