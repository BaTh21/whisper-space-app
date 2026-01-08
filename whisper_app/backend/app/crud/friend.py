from sqlalchemy.orm import Session
from typing import Optional, List
from app.models.friend import Friend, FriendshipStatus
from app.models.user import User
from app.services.websocket_manager import manager


def create(db: Session, user_id: int, friend_id: int, status: str = "pending") -> Friend:
    # Check if friendship already exists before creating
    existing = get_friend_request(db, user_id, friend_id)
    if existing:
        return existing
    
    # Manually generate ID if database doesn't auto-generate it
    # Get the next ID value
    max_id_result = db.execute("SELECT COALESCE(MAX(id), 0) + 1 as next_id FROM friends")
    next_id = max_id_result.scalar() or 1
    
    friendship = Friend(
        id=next_id,  # Manually set ID
        user_id=user_id, 
        friend_id=friend_id, 
        status=FriendshipStatus(status)
    )
    
    db.add(friendship)
    db.commit()
    db.refresh(friendship)
    return friendship


def get_pending(db: Session, requester_id: int, receiver_id: int) -> Optional[Friend]:
    return db.query(Friend).filter(
        Friend.user_id == requester_id,
        Friend.friend_id == receiver_id,
        Friend.status == FriendshipStatus.pending
    ).first()


def update_status(db: Session, user_id: int, friend_id: int, status: str):
    friendship = db.query(Friend).filter(
        ((Friend.user_id == user_id) & (Friend.friend_id == friend_id)) |
        ((Friend.user_id == friend_id) & (Friend.friend_id == user_id))
    ).first()
    if friendship:
        friendship.status = FriendshipStatus(status)
        db.commit()
        db.refresh(friendship)
    return friendship


def delete(db: Session, user_id: int, friend_id: int):
    """Delete friendship relationship between two users"""
    friendship = db.query(Friend).filter(
        ((Friend.user_id == user_id) & (Friend.friend_id == friend_id)) |
        ((Friend.user_id == friend_id) & (Friend.friend_id == user_id))
    ).first()
    
    if friendship:
        db.delete(friendship)
        db.commit()
        return True
    return False


def is_friend(db: Session, user_id: int, friend_id: int) -> bool:
    return db.query(Friend).filter(
        ((Friend.user_id == user_id) & (Friend.friend_id == friend_id)) |
        ((Friend.user_id == friend_id) & (Friend.friend_id == user_id)),
        Friend.status == FriendshipStatus.accepted
    ).first() is not None


def get_friends(db: Session, user_id: int) -> List[User]:
    return db.query(User).join(Friend,
        ((Friend.user_id == user_id) & (Friend.friend_id == User.id)) |
        ((Friend.friend_id == user_id) & (Friend.user_id == User.id))
    ).filter(Friend.status == FriendshipStatus.accepted).all()


def get_pending_requests(db: Session, user_id: int) -> List[User]:
    return db.query(User).join(Friend, Friend.user_id == User.id)\
        .filter(Friend.friend_id == user_id, Friend.status == FriendshipStatus.pending).all()


def get_friend_request(db: Session, user_id: int, friend_id: int) -> Optional[Friend]:
    return db.query(Friend).filter(
        ((Friend.user_id == user_id) & (Friend.friend_id == friend_id)) |
        ((Friend.user_id == friend_id) & (Friend.friend_id == user_id))
    ).first()


def get_blocked_users_list(db: Session, user_id: int) -> List[User]:
    """Get all users blocked by the current user"""
    try:
        # Get blocked relationships where current user is the blocker
        blocked_relationships = db.query(Friend).filter(
            Friend.user_id == user_id,
            Friend.status == FriendshipStatus.blocked
        ).all()
        
        # Extract the actual User objects
        blocked_users = []
        for relationship in blocked_relationships:
            # The blocked user is the friend_id
            user = db.query(User).filter(User.id == relationship.friend_id).first()
            if user:
                blocked_users.append(user)
        
        return blocked_users
        
    except Exception as e:
        print(f"Error in get_blocked_users_list: {str(e)}")
        raise


def is_blocked(db: Session, user_id: int, target_user_id: int) -> bool:
    """Check if user has blocked target user"""
    return db.query(Friend).filter(
        Friend.user_id == user_id,
        Friend.friend_id == target_user_id,
        Friend.status == FriendshipStatus.blocked
    ).first() is not None


def is_blocked_by(db: Session, user_id: int, target_user_id: int) -> bool:
    """Check if user is blocked by target user"""
    return db.query(Friend).filter(
        Friend.user_id == target_user_id,
        Friend.friend_id == user_id,
        Friend.status == FriendshipStatus.blocked
    ).first() is not None