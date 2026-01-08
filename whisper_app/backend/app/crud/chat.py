from datetime import datetime, timezone
from sqlalchemy.orm import Session
from app.models.private_message import MessageType, PrivateMessage
from app.models.group_message import GroupMessage
from app.models.group_message_reply import GroupMessageReply
from app.models.group_member import GroupMember
from typing import List, Optional
from datetime import datetime, timezone
from fastapi import HTTPException,status
from app.models.user_message_status import UserMessageStatus
from sqlalchemy.orm import joinedload
from sqlalchemy.exc import SQLAlchemyError
from fastapi import HTTPException
from app.schemas.chat import MessageCreate

from app.models.user_message_status import UserMessageStatus
from app.models.message_seen_status import MessageSeenStatus
from app.utils.chat_helpers import validate_reply_message
from app.models.user import User


def create_private_message(
    db: Session,
    sender_id: int,
    receiver_id: int,
    content: str,
    message_type: str = "text",
    reply_to_id: Optional[int] = None,
    is_forwarded: bool = False,
    original_sender: Optional[str] = None,
    original_sender_avatar: Optional[str] = None,
    voice_duration: Optional[float] = None,
    file_size: Optional[int] = None,
    forwarded_from_id=None
) -> PrivateMessage:
    """
    Create a private message with proper type handling and reply validation
    """
    try:
        # Validate reply message if provided
        replied_message = None
        if reply_to_id:
            replied_message = validate_reply_message(db, reply_to_id, sender_id, receiver_id)
        
        # Validate message type
        try:
            msg_type_enum = MessageType(message_type)
        except ValueError:
            msg_type_enum = MessageType.text

        # FIXED: Handle voice message specific fields
        msg = PrivateMessage(
            sender_id=sender_id,
            receiver_id=receiver_id,
            content=content,
            message_type=msg_type_enum,
            reply_to_id=reply_to_id,
            is_forwarded=is_forwarded,
            original_sender=original_sender,
            original_sender_avatar=original_sender_avatar,
            voice_duration=voice_duration if msg_type_enum == MessageType.voice else None,
            file_size=file_size if msg_type_enum in [MessageType.voice, MessageType.file] else None,
            created_at=datetime.now(timezone.utc),
            delivered_at=datetime.now(timezone.utc),
            is_read=False,
            forwarded_from_id=forwarded_from_id
        )
        db.add(msg)
        db.commit()
        db.refresh(msg)
        
        # FIXED: Eager load relationships including reply_to sender
        msg = db.query(PrivateMessage).options(
            joinedload(PrivateMessage.sender),
            joinedload(PrivateMessage.receiver),
            joinedload(PrivateMessage.seen_statuses).joinedload(MessageSeenStatus.user),
            joinedload(PrivateMessage.reply_to).joinedload(PrivateMessage.sender)  # Load sender of replied message
        ).filter(PrivateMessage.id == msg.id).first()
        
        return msg
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create message: {str(e)}"
        )


def get_private_messages(db: Session, user_id: int, friend_id: int, limit: int = 50, offset: int = 0) -> List[PrivateMessage]:
    """Get private messages between two users"""
    return db.query(PrivateMessage).options(
        joinedload(PrivateMessage.sender),
        joinedload(PrivateMessage.receiver),
        joinedload(PrivateMessage.seen_statuses).joinedload(MessageSeenStatus.user)
    ).filter(
        ((PrivateMessage.sender_id == user_id) & (PrivateMessage.receiver_id == friend_id)) |
        ((PrivateMessage.sender_id == friend_id) & (PrivateMessage.receiver_id == user_id))
    ).order_by(PrivateMessage.created_at.desc()).offset(offset).limit(limit).all()

def mark_message_as_read(db: Session, message_id: int, user_id: int) -> bool:
    # Check if already exists
    existing = db.query(MessageSeenStatus).filter_by(message_id=message_id, user_id=user_id).first()
    if existing:
        return True  # Already marked as read

    seen_status = MessageSeenStatus(
        message_id=message_id,
        user_id=user_id,
        seen_at=datetime.utcnow()
    )
    db.add(seen_status)
    try:
        db.commit()
        return True
    except Exception as e:
        db.rollback()
        return False


# ADD NEW FUNCTION to get seen status
def get_message_seen_status(db: Session, message_id: int):
    """
    Get who has seen a message and when
    """
    seen_statuses = db.query(MessageSeenStatus).filter(
        MessageSeenStatus.message_id == message_id
    ).options(joinedload(MessageSeenStatus.user)).all()
    
    return seen_statuses


def create_group_message(
    db: Session, 
    sender_id: int, 
    group_id: int, 
    content: str, 
    message_type: MessageType = MessageType.text
) -> GroupMessage:
    
    msg = GroupMessage(
        sender_id=sender_id, 
        group_id=group_id, 
        content=content, 
        message_type= message_type,
        created_at=datetime.utcnow()
    )
    try:
        db.add(msg)
        db.commit()
        db.refresh(msg)
        
    except Exception as e:
        db.rollback()
    
    return msg

def get_group_messages(db: Session, group_id: int, limit=50, offset=0):
    return (
        db.query(GroupMessage)
        .filter(GroupMessage.group_id == group_id)
        .options(
            joinedload(GroupMessage.sender),
            joinedload(GroupMessage.replies).joinedload(GroupMessageReply.sender),
            joinedload(GroupMessage.parent_message).joinedload(GroupMessage.sender)
        )
        .order_by(GroupMessage.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
        
def edit_private_message(db: Session, message_id: int, user_id: int, new_content: str) -> PrivateMessage:
    """Edit a private message"""
    try:
        if not new_content or not new_content.strip():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Message content cannot be empty.")

        # Use options to load relationships for WebSocket broadcast
        msg = db.query(PrivateMessage).options(
            joinedload(PrivateMessage.sender),
            joinedload(PrivateMessage.receiver),
        ).filter(
            PrivateMessage.id == message_id,
            PrivateMessage.sender_id == user_id
        ).first()

        if not msg:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Message not found or you don't have permission to edit it."
            )

        # Store old content for potential rollback
        old_content = msg.content
        
        # Update message
        msg.content = new_content.strip()
        msg.edited_at = datetime.now(timezone.utc)
        
        db.commit()
        db.refresh(msg)
        
        return msg
        
    except HTTPException:
        # Re-raise HTTP exceptions
        raise
    except SQLAlchemyError as e:
        # Rollback on database errors
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Database error while editing message: {str(e)}"
        )
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Unexpected error while editing message: {str(e)}"
        )


def delete_message_for_user(db: Session, message_id: int, user_id: int):
    status = UserMessageStatus(user_id=user_id, message_id=message_id, is_deleted=True)
    db.merge(status)
    db.commit()
    
def delete_message_forever(db: Session, message_id: int, user_id: int) -> dict:
    """Permanently delete a message (sender only)"""
    msg = db.query(PrivateMessage).options(
        joinedload(PrivateMessage.seen_statuses)
    ).filter(
        PrivateMessage.id == message_id,
        PrivateMessage.sender_id == user_id,  # Only sender can delete permanently
    ).first()

    if not msg:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Message not found or you are not the sender",
        )

    receiver_id = msg.receiver_id

    # Delete seen statuses first
    if msg.seen_statuses:
        for seen_status in msg.seen_statuses:
            db.delete(seen_status)

    # Then delete the message
    db.delete(msg)
    db.commit()

    return {"message_id": message_id, "receiver_id": receiver_id}

def mark_message_as_read(db: Session, message_id: int, user_id: int) -> Optional[PrivateMessage]:
    try:
        message = db.query(PrivateMessage).filter(
            PrivateMessage.id == message_id,
            PrivateMessage.receiver_id == user_id
        ).first()

        if not message or message.sender_id == user_id:
            return None
        
        current_time = datetime.now(timezone.utc)

        existing_seen = db.query(MessageSeenStatus).filter(
            MessageSeenStatus.message_id == message_id,
            MessageSeenStatus.user_id == user_id
        ).first()

        if not existing_seen:
            seen_status = MessageSeenStatus(
                message_id=message_id,
                user_id=user_id,
                seen_at=current_time
            )
            db.add(seen_status)

        if not message.is_read:
            message.is_read = True
            message.read_at = current_time

        db.commit()
        db.refresh(message)
        return message

    except Exception as e:
        db.rollback()
        print(f"[DB] Error marking message as read: {e}")
        return None



def update_user_online_status(db: Session, user_id: int, is_online: bool) -> bool:
    """Update user's online status"""
    try:
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            return False
            
        user.is_online = is_online
        user.last_activity = datetime.now(timezone.utc)
        
        if not is_online:
            user.last_seen = datetime.now(timezone.utc)
            
        db.commit()
        return True
        
    except Exception as e:
        db.rollback()
        print(f"Error updating user online status: {e}")
        return False

def get_user_online_status(db: Session, user_id: int) -> dict:
    """Get user's online status and last activity"""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        return None
        
    return {
        "user_id": user.id,
        "username": user.username,
        "is_online": user.is_online,
        "last_seen": user.last_seen,
        "last_activity": user.last_activity,
        "avatar_url": user.avatar_url
    }

def get_friends_online_status(db: Session, user_id: int) -> List[dict]:
    """Get online status of all friends"""
    from app.crud.friend import get_user_friends
    
    friends = get_user_friends(db, user_id)
    
    status_list = []
    for friend in friends:
        status_list.append({
            "user_id": friend.id,
            "username": friend.username,
            "avatar_url": friend.avatar_url,
            "is_online": friend.is_online,
            "last_seen": friend.last_seen.isoformat() if friend.last_seen else None,
            "last_activity": friend.last_activity.isoformat() if friend.last_activity else None
        })
    
    return status_list

def get_multiple_users_online_status(db: Session, user_ids: List[int]) -> List[dict]:
    """Get online status for multiple users"""
    users = db.query(User).filter(User.id.in_(user_ids)).all()
    
    status_list = []
    for user in users:
        status_list.append({
            "user_id": user.id,
            "username": user.username,
            "avatar_url": user.avatar_url,
            "is_online": user.is_online,
            "last_seen": user.last_seen.isoformat() if user.last_seen else None,
            "last_activity": user.last_activity.isoformat() if user.last_activity else None
        })
    
    return status_list

