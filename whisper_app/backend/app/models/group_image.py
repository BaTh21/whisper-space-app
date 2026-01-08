# app/models/group_image.py
from sqlalchemy import Column, Integer, String, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from app.models.base import Base
from datetime import datetime

class GroupImage(Base):
    __tablename__ = "group_images"

    id = Column(Integer, primary_key=True, autoincrement=True)
    group_id = Column(Integer, ForeignKey("groups.id", ondelete="CASCADE"), nullable=False)
    url = Column(String, nullable=False)
    public_id = Column(String, nullable=True)
    uploaded_by = Column(Integer, nullable=False)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)

    group = relationship("Group", back_populates="images")
