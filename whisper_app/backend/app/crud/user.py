from sqlalchemy.orm import Session
from app.schemas.auth import UserCreate
from app.models.user import User
from app.models.friend import Friend, FriendshipStatus
from app.schemas.user import UserUpdate
from app.core.security import hash_password
from typing import List
from sqlalchemy import select, or_, and_, func, case, union, union_all

def get_by_id(db: Session, user_id: int) -> User:
    return db.query(User).filter(User.id == user_id).first()


def get_by_email(db: Session, email: str) -> User:
    return db.query(User).filter(User.email == email).first()


def create(db: Session, user_in: UserCreate) -> User:
    hashed = hash_password(user_in.password)
    user = User(
        username=user_in.username, 
        email=user_in.email, 
        password_hash=hashed,
        is_verified=False  # ✅ CRITICAL: Set this to False by default
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def update(db: Session, user: User, user_in: UserUpdate) -> User:
    update_data = user_in.dict(exclude_unset=True)
    for key, value in update_data.items():
        setattr(user, key, value)
    db.commit()
    db.refresh(user)
    return user


def search(db: Session, q: str) -> List[User]:
    q_clean = q.strip()
    if not q_clean:
        return []
    return db.query(User).filter(User.username.ilike(f"%{q_clean}%")).limit(10).all()


def verify(db: Session, user_id: int) -> User:
    user = get_by_id(db, user_id)
    if user:
        user.is_verified = True
        db.commit()
        db.refresh(user)  # ✅ Refresh to get updated data
    return user  # ✅ Return the user object

def get_friend_suggestions(db: Session, current_user_id: int, limit: int = 20):
    # Step 1: Get current user's friends
    my_friends = union_all(
        select(Friend.user_id).where(Friend.friend_id == current_user_id, Friend.status == FriendshipStatus.accepted),
        select(Friend.friend_id).where(Friend.user_id == current_user_id, Friend.status == FriendshipStatus.accepted)
    ).subquery()

    # Step 2: Get friends of friends (mutuals)
    mutual_candidates = union_all(
        select(Friend.user_id).where(Friend.friend_id.in_(select(my_friends.c.user_id)), Friend.status == FriendshipStatus.accepted),
        select(Friend.friend_id).where(Friend.user_id.in_(select(my_friends.c.user_id)), Friend.status == FriendshipStatus.accepted)
    ).subquery()

    # Count mutual connections
    mutual_counts = (
        select(mutual_candidates.c.user_id.label("user_id"), func.count().label("mutual_count"))
        .where(mutual_candidates.c.user_id != current_user_id)  # exclude self
        .group_by(mutual_candidates.c.user_id)
        .subquery()
    )

    # Step 3: Exclude already friends
    related_users = union_all(
        select(Friend.user_id).where(Friend.friend_id == current_user_id),
        select(Friend.friend_id).where(Friend.user_id == current_user_id)
    ).subquery()

    # Step 4: Final suggestions
    suggestions = (
        db.query(User)
        .join(mutual_counts, User.id == mutual_counts.c.user_id)
        .filter(~User.id.in_(select(related_users.c.user_id)))
        .order_by(mutual_counts.c.mutual_count.desc())
        .limit(limit)
        .all()
    )

    return suggestions

def get_by_email_or_username(db: Session, identifier: str) -> User:
    """Find user by email OR username"""
    return db.query(User).filter(
        (User.email == identifier) | (User.username == identifier)
    ).first()