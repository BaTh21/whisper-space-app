from app.models.activity import Activity, ActivityType
from sqlalchemy.orm import Session

from app.models.activity import Activity, ActivityType
from sqlalchemy.orm import Session

def create_activity(
    db: Session,
    *,
    actor_id: int,
    recipient_id: int,
    activity_type: ActivityType,
    post_id: int | None = None,
    comment_id: int | None = None,
    friend_request_id: int | None = None,
    group_id: int | None = None,
    extra_data: dict | None = None,
):
    # Don't create activity if actor and recipient are the same
    if actor_id == recipient_id:
        return None

    # Only limit duplicate activities for friend requests and group invites
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
            # Already exists, return existing instead of creating new
            return existing_activity

    # Create new activity for all other cases
    activity = Activity(
        actor_id=actor_id,
        recipient_id=recipient_id,
        type=activity_type,
        post_id=post_id,
        comment_id=comment_id,
        friend_request_id=friend_request_id,
        group_id=group_id,
        extra_data=extra_data or {},
    )

    db.add(activity)
    db.commit()
    db.refresh(activity)

    return activity

