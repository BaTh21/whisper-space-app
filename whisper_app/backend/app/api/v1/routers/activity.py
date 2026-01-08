from sqlalchemy.orm import Session
from fastapi import HTTPException, Depends, APIRouter
from app.models.activity import Activity, ActivityType
from app.core.security import get_current_user
from app.core.database import get_db
from app.models.user import User
from app.schemas.activity import ActivityBase, ActivityDeleteRequest

router = APIRouter()

@router.get("/", response_model=list[ActivityBase])
def get_my_activities(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    limit: int = 20,
    offset: int = 0
):
    activities = (
        db.query(Activity)
        .filter(Activity.recipient_id == current_user.id)
        .order_by(Activity.created_at.desc())
        .limit(limit)
        .offset(offset)
        .all()
    )

    return activities

@router.patch("/{activity_id}/read")
def mark_activity_read(
    activity_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    activity = db.query(Activity).filter(
        Activity.id == activity_id,
        Activity.recipient_id == current_user.id
    ).first()

    if not activity:
        raise HTTPException(status_code=404, detail="Not found")

    activity.is_read = True
    db.commit()

    return {"message": "Marked as read"}

@router.delete("/delete")
def delete_activities(
    request: ActivityDeleteRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    activities = db.query(Activity).filter(
        Activity.id.in_(request.ids),
        Activity.recipient_id == current_user.id
    ).all()

    if not activities:
        raise HTTPException(status_code=404, detail="No matching activities found")

    for activity in activities:
        db.delete(activity)
    db.commit()

    return {"message": f"Deleted {len(activities)} activities"}

