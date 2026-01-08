from sqlalchemy import Column, Integer, ForeignKey, Boolean, DateTime
from sqlalchemy.orm import relationship
from app.models.base import Base

class DiaryGroup(Base):
    __tablename__ = "diary_groups"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    diary_id = Column(Integer, ForeignKey("diaries.id", ondelete="CASCADE"), nullable=False)
    group_id = Column(Integer, ForeignKey("groups.id", ondelete="CASCADE"), nullable=False)
    is_shared = Column(Boolean, default=True)
    shared_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    shared_at = Column(DateTime(), nullable=True)

    diary = relationship("Diary", back_populates="diary_groups")
    group = relationship("Group", back_populates="diary_groups")
    shared_user = relationship("User")