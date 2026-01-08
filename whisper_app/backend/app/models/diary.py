from sqlalchemy import ARRAY, Column, Enum, String, Text, Boolean, DateTime, ForeignKey, Integer
from app.models.base import Base
from datetime import datetime, timezone  
import enum
from sqlalchemy.orm import relationship
from app.models.diary_group import DiaryGroup

class ShareType(enum.Enum):
    public = "public"
    friends = "friends"
    personal = "personal"
    group = "group"

class Diary(Base):
    __tablename__ = "diaries"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    title = Column(String(255), nullable=True)
    content = Column(Text, nullable=True)
    share_type = Column(Enum(ShareType), nullable=False)
    group_id = Column(Integer, ForeignKey("groups.id", ondelete="SET NULL"))
    is_deleted = Column(Boolean, default=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), 
                        onupdate=lambda: datetime.now(timezone.utc))
    images = Column(ARRAY(String), nullable=True, default=list)
    videos = Column(ARRAY(String), nullable=True, default=list)
    video_thumbnails = Column(ARRAY(String), nullable=True, default=list)
    media_type = Column(String(20), default='image')
    
    author = relationship("User", back_populates="diaries")
    diary_groups = relationship("DiaryGroup", back_populates="diary", cascade="all, delete-orphan")
    groups = relationship("Group", secondary="diary_groups", viewonly=True)
    
    likes = relationship("DiaryLike", back_populates="diary", cascade="all, delete-orphan")
    comments = relationship("DiaryComment", back_populates="diary", cascade="all, delete-orphan")
    
    favorited_by = relationship(
        "DiaryFavorite",
        back_populates="diary",
        cascade="all, delete-orphan"
    )
    
    @property
    def favorited_user_ids(self) -> list[int]:
        return [fav.user_id for fav in self.favorited_by]