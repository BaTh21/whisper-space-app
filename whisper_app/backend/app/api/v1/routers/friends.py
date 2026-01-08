import traceback
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import get_current_user
from app.crud.friend import create, is_blocked, is_blocked_by, update_status, get_friends, get_pending_requests, is_friend, get_friend_request, delete
from app.models.user import User
from app.models.friend import Friend, FriendshipStatus
from datetime import datetime
import asyncio
from app.services.websocket_manager import manager
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import text
from sqlalchemy import or_, and_
from app.crud.activity import create_activity
from app.models.activity import Activity, ActivityType
from app.schemas.friend import FriendResponse

router = APIRouter()

# ==================== HEALTH CHECK ====================
@router.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "ok",
        "message": "Friends API is working",
        "timestamp": datetime.utcnow().isoformat()
    }
    
def get_any_friendship(db: Session, user1: int, user2: int):
    return db.query(Friend).filter(
        or_(
            and_(Friend.user_id == user1, Friend.friend_id == user2),
            and_(Friend.user_id == user2, Friend.friend_id == user1)
        )
    ).first()

# ==================== SEND FRIEND REQUEST ====================
@router.post("/request/{user_id}")
async def send_friend_request(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot add yourself")

    target_user = db.query(User).filter(User.id == user_id).first()
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")

    existing = get_any_friendship(db, current_user.id, user_id)

    if existing:
        if existing.status == FriendshipStatus.pending:
            raise HTTPException(
                status_code=409,
                detail="Friend request already exists"
            )
        if existing.status == FriendshipStatus.accepted:
            raise HTTPException(
                status_code=409,
                detail="Already friends"
            )
        if existing.status == FriendshipStatus.blocked:
            raise HTTPException(
                status_code=403,
                detail="Friendship is blocked"
            )

    friendship = Friend(
        user_id=current_user.id,
        friend_id=user_id,
        status=FriendshipStatus.pending
    )
    
    try:
        db.add(friendship)
        db.commit()
        db.refresh(friendship)
        
        activity = create_activity(
        db,
        actor_id=current_user.id,
        recipient_id=user_id,
        activity_type=ActivityType.friend_request,
        friend_request_id=friendship.id,
        extra_data = f"{current_user.username} sent you a friend request"
        )
        
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Friend request already sent"
        )
        
    return {
        "msg": "Friend request sent",
        "request_id": friendship.id,
        "requester_id": current_user.id,
        "recipient_id": user_id,
        "created_at": friendship.created_at.isoformat()
    }

    
# ==================== GET PENDING REQUESTS ====================
@router.get("/pending", response_model=list[FriendResponse])
async def get_pending_friend_requests(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        result = db.query(Friend).options(
            joinedload(Friend.user)
        ).filter(
            Friend.user_id == current_user.id,
            Friend.status == FriendshipStatus.pending
        ).all()
        
        return result
        
    except Exception as e:
        print(f"Error getting pending requests: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Internal server error")
    
@router.get("/all-status", response_model=list[FriendResponse])
async def get_all_status_friends(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    friends = (
        db.query(Friend)
        .filter(
            or_(
                Friend.user_id == current_user.id,
                Friend.friend_id == current_user.id
            )
        )
        .all()
    )
    return friends
    
# ==================== DECLINE FRIEND REQUEST ====================
@router.delete("/pending/{pending_id}")
async def decline_friend_request(
    pending_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        friend_request = db.query(Friend).filter(
            Friend.id == pending_id,
            Friend.user_id == current_user.id,
            Friend.status == FriendshipStatus.pending
        ).first()
        
        if not friend_request:
            raise HTTPException(status_code=404, detail="Friend request not found")
        
        # Delete the request
        db.delete(friend_request)
        db.commit()
        
        return {'detail':'Pending has been deleted'}
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Server error: {str(e)}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")
    
# ==================== ACCEPT FRIEND REQUEST ====================
@router.post("/accept/{requester_id}")
async def accept_friend_request(
    requester_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        friend_request = db.query(Friend).filter(
            Friend.user_id == requester_id,
            Friend.friend_id == current_user.id,
            Friend.status == FriendshipStatus.pending
        ).first()

        if not friend_request:
            print(f"No pending request found for requester {requester_id} -> user {current_user.id}")
            raise HTTPException(status_code=404, detail="Friend request not found")

        now = datetime.utcnow()
        friend_request.status = FriendshipStatus.accepted
        friend_request.updated_at = now
        db.commit()

        requester = db.query(User).filter(User.id == requester_id).first()
        if not requester:
            raise HTTPException(status_code=404, detail="Requester not found")

        acceptance_data = {
            "type": "friend_request_accepted",
            "data": {
                "friend_request_id": friend_request.id,
                "friend_id": current_user.id,
                "friend_username": current_user.username,
                "friend_avatar_url": current_user.avatar_url or "",
                "accepted_at": now.isoformat(),
                "message": f"{current_user.username} accepted your friend request!"
            }
        }

        requester_room = f"user_{requester_id}"
        if manager and hasattr(manager, 'broadcast_to_user'):
            try:
                asyncio.create_task(
                    manager.broadcast_to_user(requester_room, acceptance_data)
                )
            except Exception as ws_error:
                print(f"WebSocket error: {ws_error}")

        return {
            "msg": "Friend request accepted successfully",
            "friend_request_id": friend_request.id,
            "friend_id": requester_id,
            "friend_username": requester.username,
            "accepted_at": now.isoformat()
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"Server error: {str(e)}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@router.post("/unfriend/{friend_id}")
async def unfriend(
    friend_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        # Check if friendship exists
        friendship = get_friend_request(db, current_user.id, friend_id)
        if not friendship:
            raise HTTPException(status_code=404, detail="Friendship not found")
        
        if friendship.status != FriendshipStatus.accepted:
            raise HTTPException(status_code=400, detail="You are not friends with this user")
        
        # Delete the friendship
        delete(db, current_user.id, friend_id)
        
        # Notify the other user about unfriending
        unfriend_data = {
            "type": "unfriended",
            "data": {
                "unfriended_by_id": current_user.id,
                "unfriended_by_username": current_user.username,
                "unfriended_at": datetime.utcnow().isoformat(),
                "message": f"{current_user.username} unfriended you"
            }
        }
        
        # Send real-time notification
        friend_room = f"user_{friend_id}"
        
        try:
            if hasattr(manager, 'broadcast_to_user'):
                asyncio.create_task(
                    manager.broadcast_to_user(friend_room, unfriend_data)
                )
                print(f"Unfriend notification sent to user {friend_id}")
        except Exception as ws_error:
            print(f"WebSocket unfriend notification error: {ws_error}")
        
        return {"msg": "Unfriended successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Server error in unfriend: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")


@router.post("/block/{user_id}")
async def block_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Block a user and optionally clear chat history"""
    try:
        if user_id == current_user.id:
            raise HTTPException(status_code=400, detail="Cannot block yourself")
        
        # Check if relationship already exists
        existing = get_friend_request(db, current_user.id, user_id)
        
        if existing:
            # Update existing relationship to blocked
            existing.status = FriendshipStatus.blocked
            existing.updated_at = datetime.utcnow()
            db.commit()
        else:
            # Create new blocked relationship
            create(db, current_user.id, user_id, FriendshipStatus.blocked)
        
        return {
            "msg": "User blocked successfully",
            "blocked_user_id": user_id,
            "blocker_id": current_user.id,
            "timestamp": datetime.utcnow().isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Server error in block_user: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@router.post("/unblock/{user_id}")
def unblock_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        # Check if blocked relationship exists
        blocked_relationship = get_friend_request(db, current_user.id, user_id)
        if not blocked_relationship:
            raise HTTPException(status_code=404, detail="User is not blocked")
        
        if blocked_relationship.status != FriendshipStatus.blocked:
            raise HTTPException(status_code=400, detail="User is not blocked")
        
        # Delete the blocked relationship
        delete(db, current_user.id, user_id)
        return {"msg": "User unblocked successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Server error in unblock_user: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")


@router.get("/", response_model=list[dict])
def list_friends(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        friends = get_friends(db, current_user.id)
        return [{
            "id": f.id, 
            "username": f.username, 
            "email": f.email,
            "avatar_url": f.avatar_url,  # ADD THIS LINE
            "is_verified": f.is_verified  # Optional: add if you have this field
        } for f in friends]
    except Exception as e:
        print(f"Server error in list_friends: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")


@router.get("/requests")
def pending_requests(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        requests = get_pending_requests(db, current_user.id)
        
        # Transform User objects to friend request format
        formatted_requests = []
        for user in requests:
            # Find the actual friend request record to get request-specific data
            friend_request = db.query(Friend).filter(
                # Friend.user_id == user.id,
                Friend.friend_id == current_user.id,  # Current user is the receiver
                Friend.status == FriendshipStatus.pending
            ).first()
            
            formatted_requests.append({
                "friend_request_id": friend_request.id if friend_request else None,
                "requester_id": user.id,
                "requester_username": user.username,
                "requester_email": user.email,
                "requester_avatar_url": user.avatar_url,
                "created_at": friend_request.created_at.isoformat() if friend_request and friend_request.created_at else None,
                "status": "pending"
            })
        
        return formatted_requests
        
    except Exception as e:
        print(f"Server error in pending_requests: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.get("/blocked")
def get_blocked_users_route(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        # Direct query without using CRUD function
        blocked_users = db.query(User).join(
            Friend, User.id == Friend.friend_id
        ).filter(
            Friend.user_id == current_user.id,
            Friend.status == FriendshipStatus.blocked
        ).all()
        
        return [{
            "id": user.id,
            "username": user.username,
            "email": user.email,
            "avatar_url": user.avatar_url  # ADD THIS LINE
        } for user in blocked_users]
        
    except Exception as e:
        print(f"Server error in get_blocked_users_route: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.post("/friends/")
def add_friend(
    friend_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Add a friend"""
    try:
        
        if friend_id == current_user.id:
            raise HTTPException(status_code=400, detail="Cannot add yourself as friend")
            
        # Your friend adding logic here
        return {"message": f"Friend with ID {friend_id} added successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to add friend")
    
@router.get("/check-blocked/{user_id}")
async def check_blocked_status(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Check if a user is blocked by or has blocked current user"""
    try:
        # Check if current user has blocked the target user
        current_blocked_target = is_blocked(db, current_user.id, user_id)
        
        # Check if target user has blocked current user
        target_blocked_current = is_blocked_by(db, current_user.id, user_id)
        
        return {
            "current_user_has_blocked": current_blocked_target,
            "target_user_has_blocked": target_blocked_current,
            "is_blocked": current_blocked_target or target_blocked_current,
            "current_user_id": current_user.id,
            "target_user_id": user_id
        }
        
    except Exception as e:
        print(f"Error checking blocked status: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")