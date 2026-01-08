from typing import List, Optional
from sqlalchemy.orm import Session, joinedload
from fastapi import HTTPException, status
from datetime import datetime, timezone

from app.models.private_message import PrivateMessage, MessageType
from app.models.message_seen_status import MessageSeenStatus
from app.models.group_message import GroupMessage
from app.models.group_member import GroupMember

def _chat_id(user_a: int, user_b: int) -> str:
    """Generate consistent chat room ID for private conversations"""
    a, b = sorted([user_a, user_b])
    return f"private_{a}_{b}"

def extract_public_id_from_url(url: str) -> Optional[str]:
    """Extract Cloudinary public_id from URL"""
    if not url:
        return None
    try:
        # Extract public_id from Cloudinary URL
        parts = url.split('/')
        if 'cloudinary.com' in url:
            # Find the part after the version number
            for i, part in enumerate(parts):
                if part.startswith('v'):
                    if i + 1 < len(parts):
                        public_id_with_extension = '/'.join(parts[i + 1:])
                        return public_id_with_extension.rsplit('.', 1)[0]  # Remove extension
        return None
    except Exception:
        return None

def is_group_member(db: Session, group_id: int, user_id: int) -> bool:
    return db.query(GroupMember).filter_by(group_id=group_id, user_id=user_id).first() is not None

def validate_reply_message(db: Session, reply_to_id: int, sender_id: int, receiver_id: int) -> PrivateMessage:
    """Validate that a reply message belongs to the same conversation"""
    if not reply_to_id:
        return None
        
    replied_message = db.query(PrivateMessage).options(
        joinedload(PrivateMessage.sender)
    ).filter(PrivateMessage.id == reply_to_id).first()
    
    if not replied_message:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Replied message not found"
        )
    
    # Check if replied message belongs to the same conversation
    valid_conversation = (
        (replied_message.sender_id == sender_id and replied_message.receiver_id == receiver_id) or
        (replied_message.sender_id == receiver_id and replied_message.receiver_id == sender_id)
    )
    
    if not valid_conversation:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot reply to a message from a different conversation"
        )
    
    return replied_message