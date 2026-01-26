from app.models.activity import Activity, ActivityType
from sqlalchemy.orm import Session
from datetime import datetime
from typing import Optional
import json

def create_activity(
    db: Session,
    *,
    actor_id: int,
    recipient_id: int,
    activity_type: ActivityType,
    post_id: Optional[int] = None,
    comment_id: Optional[int] = None,
    friend_request_id: Optional[int] = None,
    group_id: Optional[int] = None,
    extra_data: Optional[str] = None, 
):
    """
    Create an activity notification
    extra_data: Should be a string (or None)
    """
    if actor_id == recipient_id:
        return None

    if activity_type in [ActivityType.friend_request, ActivityType.group_invite]:
        query = db.query(Activity).filter(
            Activity.actor_id == actor_id,
            Activity.recipient_id == recipient_id,
            Activity.type == activity_type,
        )

        if friend_request_id is not None:
            query = query.filter(Activity.friend_request_id == friend_request_id)
        if group_id is not None:
            query = query.filter(Activity.group_id == group_id)

        existing_activity = query.first()
        if existing_activity:
            return existing_activity


    activity = Activity(
        actor_id=actor_id,
        recipient_id=recipient_id,
        type=activity_type,
        post_id=post_id,
        comment_id=comment_id,
        friend_request_id=friend_request_id,
        group_id=group_id,
        extra_data=extra_data,  
        is_read=False,
    )

    db.add(activity)
    db.commit()
    db.refresh(activity)

    return activity