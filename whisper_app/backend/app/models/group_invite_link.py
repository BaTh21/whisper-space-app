# app/models/group_invite_link.py
from sqlalchemy import Column, Integer, String, ForeignKey
from app.models.base import Base

class GroupInviteLink(Base):
    __tablename__ = "group_invite_links"

    id = Column(Integer, primary_key=True, index=True)
    group_id = Column(Integer, ForeignKey("groups.id"), unique=True)
    token = Column(String(50), unique=True, index=True)