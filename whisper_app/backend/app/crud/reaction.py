from sqlalchemy.orm import Session, joinedload
from typing import List, Optional, Tuple
from fastapi import HTTPException, status
from datetime import datetime, timezone

from app.models.message_reaction import MessageReaction
from app.models.private_message import PrivateMessage
from app.schemas.reaction import ReactionCreate

def create_reaction(
    db: Session, 
    message_id: int, 
    user_id: int, 
    reaction_in: ReactionCreate
) -> MessageReaction:
    """
    Create a new reaction for a message
    """
    # Check if message exists and user has access
    message = db.query(PrivateMessage).filter(
        PrivateMessage.id == message_id,
        (PrivateMessage.sender_id == user_id) | (PrivateMessage.receiver_id == user_id)
    ).first()
    
    if not message:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Message not found or access denied"
        )
    
    # Check if user already reacted with this emoji
    existing_reaction = db.query(MessageReaction).filter(
        MessageReaction.message_id == message_id,
        MessageReaction.user_id == user_id,
        MessageReaction.emoji == reaction_in.emoji
    ).first()
    
    if existing_reaction:
        # If already exists, return the existing reaction (idempotent)
        return existing_reaction
    
    # Create new reaction
    reaction = MessageReaction(
        message_id=message_id,
        user_id=user_id,
        emoji=reaction_in.emoji,
        created_at=datetime.now(timezone.utc)
    )
    
    db.add(reaction)
    db.commit()
    db.refresh(reaction)
    
    # Load with user relationship
    reaction = db.query(MessageReaction).options(
        joinedload(MessageReaction.user)
    ).filter(MessageReaction.id == reaction.id).first()
    
    return reaction

def delete_reaction(
    db: Session, 
    message_id: int, 
    reaction_id: int, 
    user_id: int
) -> Tuple[bool, Optional[str]]:
    """
    Delete a reaction from a message
    Returns: (success, error_message)
    """
    # Find the reaction
    reaction = db.query(MessageReaction).filter(
        MessageReaction.id == reaction_id,
        MessageReaction.message_id == message_id,
        MessageReaction.user_id == user_id  # Only owner can delete
    ).first()
    
    if not reaction:
        return False, "Reaction not found or access denied"
    
    # Delete the reaction
    db.delete(reaction)
    db.commit()
    
    return True, None

def get_message_reactions(
    db: Session, 
    message_id: int, 
    user_id: int,
    skip: int = 0, 
    limit: int = 100
) -> List[MessageReaction]:
    """
    Get all reactions for a message with user access check
    """
    # Verify user has access to the message
    message = db.query(PrivateMessage).filter(
        PrivateMessage.id == message_id,
        (PrivateMessage.sender_id == user_id) | (PrivateMessage.receiver_id == user_id)
    ).first()
    
    if not message:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Message not found or access denied"
        )
    
    # Get reactions with user info
    reactions = db.query(MessageReaction).options(
        joinedload(MessageReaction.user)
    ).filter(
        MessageReaction.message_id == message_id
    ).order_by(
        MessageReaction.created_at.desc()
    ).offset(skip).limit(limit).all()
    
    return reactions

def get_reaction_summary(
    db: Session, 
    message_id: int, 
    user_id: int
) -> dict:
    """
    Get reaction summary (count by emoji) for a message
    """
    # Verify user has access to the message
    message = db.query(PrivateMessage).filter(
        PrivateMessage.id == message_id,
        (PrivateMessage.sender_id == user_id) | (PrivateMessage.receiver_id == user_id)
    ).first()
    
    if not message:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Message not found or access denied"
        )
    
    # Get reaction counts grouped by emoji
    from sqlalchemy import func
    
    reaction_counts = db.query(
        MessageReaction.emoji,
        func.count(MessageReaction.id).label('count'),
        func.max(MessageReaction.created_at).label('latest')
    ).filter(
        MessageReaction.message_id == message_id
    ).group_by(
        MessageReaction.emoji
    ).order_by(
        func.count(MessageReaction.id).desc(),
        func.max(MessageReaction.created_at).desc()
    ).all()
    
    # Check which emojis the current user has reacted with
    user_reactions = db.query(MessageReaction.emoji).filter(
        MessageReaction.message_id == message_id,
        MessageReaction.user_id == user_id
    ).all()
    
    user_reacted_emojis = {r.emoji for r in user_reactions}
    
    return {
        "message_id": message_id,
        "reactions": [
            {
                "emoji": rc.emoji,
                "count": rc.count,
                "latest": rc.latest,
                "user_reacted": rc.emoji in user_reacted_emojis
            }
            for rc in reaction_counts
        ],
        "total_reactions": sum(rc.count for rc in reaction_counts),
        "user_has_reacted": len(user_reacted_emojis) > 0
    }