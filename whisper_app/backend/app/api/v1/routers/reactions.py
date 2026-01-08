from typing import List
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.crud.reaction import (
    create_reaction, 
    delete_reaction, 
    get_message_reactions,
    get_reaction_summary
)
from app.schemas.reaction import (
    ReactionCreate, 
    ReactionOut, 
    ReactionDeleteResponse,
    MessageReactionsResponse
)

router = APIRouter()

@router.post(
    "/messages/{message_id}/reactions", 
    response_model=ReactionOut,
    status_code=status.HTTP_201_CREATED,
    summary="Add reaction to message",
    description="Add an emoji reaction to a message. If user already reacted with same emoji, returns existing reaction."
)
async def add_reaction_to_message(
    message_id: int,
    reaction_in: ReactionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Add a reaction to a message.
    
    - **message_id**: ID of the message to react to
    - **emoji**: Emoji character (e.g., "👍", "❤️", "😂")
    
    Returns the created reaction with user information.
    """
    try:
        reaction = create_reaction(
            db=db,
            message_id=message_id,
            user_id=current_user.id,
            reaction_in=reaction_in
        )
        
        return reaction
        
    except HTTPException as he:
        raise he
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to add reaction: {str(e)}"
        )

@router.delete(
    "/messages/{message_id}/reactions/{reaction_id}",
    response_model=ReactionDeleteResponse,
    summary="Remove reaction from message",
    description="Remove a reaction from a message. Only the user who created the reaction can remove it."
)
async def remove_reaction_from_message(
    message_id: int,
    reaction_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Remove a reaction from a message.
    
    - **message_id**: ID of the message
    - **reaction_id**: ID of the reaction to remove
    
    Returns success status.
    """
    try:
        success, error_message = delete_reaction(
            db=db,
            message_id=message_id,
            reaction_id=reaction_id,
            user_id=current_user.id
        )
        
        if not success:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=error_message
            )
        
        return ReactionDeleteResponse(
            message_id=message_id,
            reaction_id=reaction_id
        )
        
    except HTTPException as he:
        raise he
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to remove reaction: {str(e)}"
        )

@router.get(
    "/messages/{message_id}/reactions",
    response_model=MessageReactionsResponse,
    summary="Get message reactions",
    description="Get all reactions for a specific message with user details."
)
async def get_message_reactions_list(
    message_id: str,  # Changed from int to str to accept temp IDs
    skip: int = Query(0, ge=0, description="Number of records to skip"),
    limit: int = Query(100, ge=1, le=500, description="Maximum number of records to return"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get all reactions for a message.
    
    - **message_id**: ID of the message (can be numeric ID or temp ID starting with 'temp-')
    - **skip**: Number of records to skip (for pagination)
    - **limit**: Maximum number of records to return
    
    Returns list of reactions with user information.
    For temp messages, returns empty list.
    """
    try:
        # Check if it's a temp message ID
        if isinstance(message_id, str) and message_id.startswith("temp-"):
            # Return empty response for temp messages
            return MessageReactionsResponse(
                message_id=message_id,
                reactions=[],
                total_count=0
            )
        
        # Try to convert to integer for real messages
        try:
            numeric_message_id = int(message_id)
        except ValueError:
            # If it's not a valid number, treat it as invalid request
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Invalid message ID format. Expected numeric ID or temp ID, got: {message_id}"
            )
        
        # Get reactions for real message
        reactions = get_message_reactions(
            db=db,
            message_id=numeric_message_id,
            user_id=current_user.id,
            skip=skip,
            limit=limit
        )
        
        return MessageReactionsResponse(
            message_id=numeric_message_id,
            reactions=reactions,
            total_count=len(reactions)
        )
        
    except HTTPException as he:
        raise he
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get reactions: {str(e)}"
        )
@router.get(
    "/messages/{message_id}/reactions/summary",
    summary="Get reaction summary",
    description="Get reaction counts grouped by emoji for a message."
)
async def get_reactions_summary(
    message_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get reaction summary (counts by emoji) for a message.
    
    - **message_id**: ID of the message
    
    Returns reaction counts grouped by emoji.
    """
    try:
        summary = get_reaction_summary(
            db=db,
            message_id=message_id,
            user_id=current_user.id
        )
        
        return summary
        
    except HTTPException as he:
        raise he
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get reaction summary: {str(e)}"
        )

# Additional endpoint for batch operations
@router.post(
    "/messages/reactions/batch",
    summary="Get reactions for multiple messages",
    description="Get reaction summaries for multiple messages at once."
)
async def get_batch_reactions_summary(
    message_ids: List[int],
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get reaction summaries for multiple messages.
    
    - **message_ids**: List of message IDs
    
    Returns reaction summaries for each message.
    """
    try:
        # Limit the number of messages to prevent abuse
        if len(message_ids) > 50:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Too many messages requested (max 50)"
            )
        
        summaries = {}
        for msg_id in message_ids:
            try:
                summary = get_reaction_summary(db, msg_id, current_user.id)
                summaries[msg_id] = summary
            except HTTPException:
                # Skip messages user doesn't have access to
                continue
            except Exception:
                continue
        
        return {
            "summaries": summaries,
            "total_messages": len(message_ids),
            "accessible_messages": len(summaries)
        }
        
    except HTTPException as he:
        raise he
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get batch reactions: {str(e)}"
        )