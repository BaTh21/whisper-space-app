from sqlalchemy import (
    Column, Integer, Enum, ForeignKey,
    Boolean, DateTime, JSON, Index, func, Text
)
from sqlalchemy.orm import relationship, backref
from app.models.base import Base
import enum

class ActivityType(enum.Enum):
    friend_request = "friend_request"
    post_like = "post_like"
    post_comment = "post_comment"
    group_invite = "group_invite"
    delete_post = "delete_post"

class Activity(Base):
    __tablename__ = "activities"

    id = Column(Integer, primary_key=True, autoincrement=True)
    actor_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    recipient_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    type = Column(Enum(ActivityType), nullable=False)
    post_id = Column(Integer, ForeignKey("diaries.id", ondelete="CASCADE"), nullable=True)
    comment_id = Column(Integer, ForeignKey("diary_comments.id", ondelete="CASCADE"), nullable=True)
    friend_request_id = Column(Integer, ForeignKey("friends.id", ondelete="CASCADE"), nullable=True)
    group_id = Column(Integer, ForeignKey("groups.id", ondelete="CASCADE"), nullable=True)
    extra_data  = Column(Text, nullable=True)
    is_read = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())

    # Relationships
    actor = relationship(
        "User",
        foreign_keys=[actor_id],
        backref=backref("activities_as_actor", overlaps="activities_sent")
    )

    recipient = relationship(
        "User",
        foreign_keys=[recipient_id],
        backref=backref("activities_as_recipient", overlaps="activities_received")
    )

    post = relationship("Diary", backref="activities", passive_deletes=True)
    comment = relationship("DiaryComment", backref="activities", passive_deletes=True)
    friend_request = relationship("Friend", backref="activities", passive_deletes=True)
    group = relationship("Group", backref="activities", passive_deletes=True)

    __table_args__ = (
        Index("idx_activity_recipient", "recipient_id", "is_read"),
        Index("idx_activity_type", "type"),
    )

