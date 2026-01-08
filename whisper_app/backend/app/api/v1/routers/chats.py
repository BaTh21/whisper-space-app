import os
import uuid
from datetime import datetime, timezone
from typing import List, Optional

import cloudinary
import cloudinary.uploader
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session, joinedload

from app.core.database import get_db
from app.core.security import get_current_user
from app.crud.chat import create_private_message, delete_message_forever, edit_private_message, get_multiple_users_online_status, mark_message_as_read
from app.crud.friend import is_blocked, is_blocked_by, is_friend
from app.models.message_seen_status import MessageSeenStatus
from app.models.private_message import MessageType, PrivateMessage
from app.models.user import User
from app.schemas.chat import (MarkMessagesAsReadRequest, MarkMessagesAsReadResponse, ChatListItem,
                             MessageCreate, MessageOut, MessageSeenByUser, ReplyPreview)
from app.services.websocket_manager import manager
from app.utils.chat_helpers import _chat_id, extract_public_id_from_url
from app.core.cloudinary import check_cloudinary_health, upload_voice_message
from app.core.config import settings
from app.crud.friend import get_friends
from sqlalchemy import or_, and_
from app.crud.group import get_user_groups
from app.models.group_message import GroupMessage
from datetime import timezone

router = APIRouter()

def to_utc(dt):
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


@router.get("/", response_model=list[ChatListItem])
def list_chats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    chats = []

    friends = get_friends(db, current_user.id)

    for friend in friends:
        last_msg = (
            db.query(PrivateMessage)
            .filter(
                or_(
                    and_(
                        PrivateMessage.sender_id == current_user.id,
                        PrivateMessage.receiver_id == friend.id
                    ),
                    and_(
                        PrivateMessage.sender_id == friend.id,
                        PrivateMessage.receiver_id == current_user.id
                    )
                )
            )
            .order_by(PrivateMessage.created_at.desc())
            .first()
        )

        updated_at = to_utc(
            last_msg.created_at if last_msg else friend.created_at
        )

        chats.append({
            "id": friend.id,
            "type": "private",
            "name": friend.username,
            "avatar": friend.avatar_url,
            "last_message": last_msg.content if last_msg else None,
            "updated_at": updated_at
        })

    groups = get_user_groups(db, current_user.id)

    for group in groups:
        last_msg = (
            db.query(GroupMessage)
            .filter(GroupMessage.group_id == group.id)
            .order_by(GroupMessage.created_at.desc())
            .first()
        )

        updated_at = to_utc(
            last_msg.created_at if last_msg else group.created_at
        )

        chats.append({
            "id": group.id,
            "type": "group",
            "name": group.name,
            "avatar": group.images[0].url if group.images else None,
            "last_message": last_msg.content if last_msg else None,
            "updated_at": updated_at
        })

    chats.sort(
        key=lambda x: x["updated_at"] or datetime.min.replace(tzinfo=timezone.utc),
        reverse=True
    )

    return chats

# Mark messages as read endpoint
@router.post("/messages/read")
async def mark_messages_as_read_batch(
    request: MarkMessagesAsReadRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Mark multiple messages as read with proper seen_by tracking
    """
    try:
        # Get messages that belong to this user and are unread
        messages = db.query(PrivateMessage).filter(
            PrivateMessage.id.in_(request.message_ids),
            PrivateMessage.receiver_id == current_user.id,
            PrivateMessage.is_read == False
        ).all()
        
        if not messages:
            return MarkMessagesAsReadResponse(
                status="success",
                marked_count=0,
                message_ids=request.message_ids
            )
        
        marked_count = 0
        for message in messages:
            # Update message read status
            message.is_read = True
            message.read_at = datetime.now(timezone.utc)
            
            # Add seen status entry
            existing_seen = db.query(MessageSeenStatus).filter(
                MessageSeenStatus.message_id == message.id,
                MessageSeenStatus.user_id == current_user.id
            ).first()
            
            if not existing_seen:
                seen_status = MessageSeenStatus(
                    message_id=message.id,
                    user_id=current_user.id,
                    seen_at=datetime.now(timezone.utc)
                )
                db.add(seen_status)
                marked_count += 1
        
        db.commit()
        
        # Get updated messages with seen_by information
        updated_messages = db.query(PrivateMessage).options(
            joinedload(PrivateMessage.seen_statuses).joinedload(MessageSeenStatus.user)
        ).filter(PrivateMessage.id.in_([m.id for m in messages])).all()
        
        # Prepare WebSocket notification
        for message in updated_messages:
            chat_id = _chat_id(message.sender_id, message.receiver_id)
            
            # Prepare seen information
            seen_info = []
            for status in message.seen_statuses:
                seen_info.append({
                    "user_id": status.user.id,
                    "username": status.user.username,
                    "avatar_url": status.user.avatar_url,
                    "seen_at": status.seen_at.isoformat() if status.seen_at else None
                })
            
            await manager.broadcast(chat_id, {
                "type": "message_updated",
                "message_id": message.id,
                "is_read": True,
                "read_at": message.read_at.isoformat() if message.read_at else None,
                "seen_by": seen_info
            })
        
        return MarkMessagesAsReadResponse(
            status="success",
            marked_count=marked_count,
            message_ids=request.message_ids
        )
    except Exception as e:
        db.rollback()
        raise HTTPException(500, f"Failed to mark messages as read: {str(e)}")

@router.get("/private/{friend_id}", response_model=List[MessageOut])
async def get_private_chat(
    friend_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if is_blocked(db, current_user.id, friend_id) or is_blocked_by(db, current_user.id, friend_id):
        return []

    if not is_friend(db, current_user.id, friend_id):
        raise HTTPException(status_code=403, detail="Not friends")

    messages = (
        db.query(PrivateMessage)
        .options(
            joinedload(PrivateMessage.sender),
            joinedload(PrivateMessage.receiver),
            joinedload(PrivateMessage.reply_to).joinedload(PrivateMessage.sender),
            joinedload(PrivateMessage.seen_statuses).joinedload(MessageSeenStatus.user),
        )
        .filter(
            ((PrivateMessage.sender_id == current_user.id) & (PrivateMessage.receiver_id == friend_id)) |
            ((PrivateMessage.sender_id == friend_id) & (PrivateMessage.receiver_id == current_user.id))
        )
        .order_by(PrivateMessage.created_at.asc())
        .all()
    )

    result: list[MessageOut] = []

    for msg in messages:
        seen_by = [
            MessageSeenByUser(
                user_id=s.user.id,
                username=s.user.username,
                avatar_url=s.user.avatar_url,
                seen_at=s.seen_at.isoformat() if s.seen_at else None
            )
            for s in msg.seen_statuses
        ]

        reply_to_out = None
        reply_preview = None

        if msg.reply_to:
            reply = msg.reply_to

            reply_to_out = MessageOut(
                id=reply.id,
                sender_id=reply.sender_id,
                receiver_id=reply.receiver_id,
                content=reply.content,
                message_type=serialize_message_type(reply.message_type),  # ✅ FIXED
                is_read=reply.is_read,
                read_at=reply.read_at.isoformat() if reply.read_at else None,
                delivered_at=reply.delivered_at.isoformat() if reply.delivered_at else None,
                reply_to=None,
                reply_to_id=reply.reply_to_id,
                is_forwarded=reply.is_forwarded,
                forwarded_from_id=reply.forwarded_from_id,
                original_sender=reply.original_sender,
                original_sender_avatar=reply.original_sender_avatar,
                created_at=reply.created_at.isoformat(),
                sender_username=getattr(reply.sender, "username", None),
                receiver_username=getattr(reply.receiver, "username", None),
                voice_duration=reply.voice_duration,
                file_size=reply.file_size,
                seen_by=[]
            )

            reply_preview = build_reply_preview(reply)

        result.append(
            build_message_out(
                msg=msg,
                reply_to=reply_to_out,
                reply_preview=reply_preview,
                seen_by=seen_by
            )
        )

    return result

# Send text message
@router.post("/private/{friend_id}", response_model=MessageOut)
async def send_private_message(
    friend_id: int,
    msg_in: MessageCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Send a private message to a friend with Telegram-style reply handling
    """
    try:
        
        if is_blocked(db, current_user.id, friend_id):
            raise HTTPException(
                status_code=403, 
                detail="Cannot send message to blocked user"
            )
        
        # Check if friend has blocked current user
        if is_blocked_by(db, current_user.id, friend_id):
            raise HTTPException(
                status_code=403, 
                detail="This user has blocked you"
            )
            
        if not is_friend(db, current_user.id, friend_id):
            raise HTTPException(status_code=403, detail="Not friends")

        # Create message in database
        msg = create_private_message(
            db=db,
            sender_id=current_user.id,
            receiver_id=friend_id,
            content=msg_in.content,
            message_type=msg_in.message_type,
            reply_to_id=msg_in.reply_to_id,
            is_forwarded=msg_in.is_forwarded,
            original_sender=msg_in.original_sender,
            voice_duration=msg_in.voice_duration,
            file_size=msg_in.file_size
        )

        # Get the full message with all relationships
        full_msg = db.query(PrivateMessage).options(
            joinedload(PrivateMessage.sender),
            joinedload(PrivateMessage.receiver),
            joinedload(PrivateMessage.seen_statuses).joinedload(MessageSeenStatus.user),
            joinedload(PrivateMessage.reply_to).joinedload(PrivateMessage.sender),
            joinedload(PrivateMessage.reply_to).joinedload(PrivateMessage.seen_statuses).joinedload(MessageSeenStatus.user)
        ).filter(PrivateMessage.id == msg.id).first()

        if not full_msg:
            raise HTTPException(status_code=500, detail="Failed to retrieve created message")
        
        chat_id = _chat_id(current_user.id, friend_id)
        
        # Prepare seen information
        seen_by = []
        for status in full_msg.seen_statuses:
            seen_by.append({
                "user_id": status.user.id,
                "username": status.user.username,
                "avatar_url": status.user.avatar_url,
                "seen_at": status.seen_at.isoformat() if status.seen_at else None
            })
        
        # Prepare broadcast data
        broadcast_data = {
            "type": "message",
            "id": full_msg.id,
            "sender_id": full_msg.sender_id,
            "receiver_id": full_msg.receiver_id,
            "content": full_msg.content,
            "message_type": full_msg.message_type.value,
            "is_read": full_msg.is_read,
            "read_at": full_msg.read_at.isoformat() if full_msg.read_at else None,
            "delivered_at": full_msg.delivered_at.isoformat() if full_msg.delivered_at else None,
            "reply_to_id": full_msg.reply_to_id,
            "is_forwarded": full_msg.is_forwarded,
            "original_sender": full_msg.original_sender,
            "created_at": full_msg.created_at.isoformat(),
            "sender_username": full_msg.sender.username,
            "receiver_username": full_msg.receiver.username,
            "voice_duration": full_msg.voice_duration,
            "file_size": full_msg.file_size,
            "seen_by": seen_by
        }
        
        # Add Telegram-style reply data if exists
        if full_msg.reply_to:
            # Create compact reply preview (like Telegram)
            reply_content = full_msg.reply_to.content or ""
            if full_msg.reply_to.message_type == MessageType.voice:
                reply_content = "🎤 Voice message"
            elif full_msg.reply_to.message_type == MessageType.image:
                reply_content = "🖼️ Photo" 
            elif full_msg.reply_to.message_type == MessageType.file:
                reply_content = "📎 File"
            elif len(reply_content) > 100:
                reply_content = reply_content[:100] + "..."
            
            # Add compact reply preview to broadcast
            broadcast_data["reply_preview"] = {
                "id": full_msg.reply_to.id,
                "sender_username": full_msg.reply_to.sender.username,
                "content": reply_content,
                "message_type": full_msg.reply_to.message_type.value,
                "voice_duration": full_msg.reply_to.voice_duration,
                "file_size": full_msg.reply_to.file_size
            }
            
            # Also include full reply data for detailed view
            reply_seen_by = []
            if full_msg.reply_to.seen_statuses:
                for status in full_msg.reply_to.seen_statuses:
                    reply_seen_by.append({
                        "user_id": status.user.id,
                        "username": status.user.username,
                        "avatar_url": status.user.avatar_url,
                        "seen_at": status.seen_at.isoformat() if status.seen_at else None
                    })
            
            # Include complete replied message information
            broadcast_data["reply_to"] = {
                "id": full_msg.reply_to.id,
                "sender_id": full_msg.reply_to.sender_id,
                "receiver_id": full_msg.reply_to.receiver_id,
                "content": full_msg.reply_to.content,
                "message_type": full_msg.reply_to.message_type.value,
                "is_read": full_msg.reply_to.is_read,
                "read_at": full_msg.reply_to.read_at.isoformat() if full_msg.reply_to.read_at else None,
                "delivered_at": full_msg.reply_to.delivered_at.isoformat() if full_msg.reply_to.delivered_at else None,
                "reply_to_id": full_msg.reply_to.reply_to_id,
                "is_forwarded": full_msg.reply_to.is_forwarded,
                "original_sender": full_msg.reply_to.original_sender,
                "created_at": full_msg.reply_to.created_at.isoformat(),
                "sender_username": full_msg.reply_to.sender.username,
                "receiver_username": full_msg.reply_to.receiver.username if full_msg.reply_to.receiver else None,
                "voice_duration": full_msg.reply_to.voice_duration,
                "file_size": full_msg.reply_to.file_size,
                "seen_by": reply_seen_by
            }
        
        # Broadcast via WebSocket
        await manager.broadcast(chat_id, broadcast_data)
        
        # Build response with Telegram-style reply preview
        response = MessageOut(
            id=full_msg.id,
            sender_id=full_msg.sender_id,
            receiver_id=full_msg.receiver_id,
            content=full_msg.content,
            message_type=full_msg.message_type.value,
            is_read=full_msg.is_read,
            read_at=full_msg.read_at.isoformat() if full_msg.read_at else None,
            delivered_at=full_msg.delivered_at.isoformat() if full_msg.delivered_at else None,
            reply_to_id=full_msg.reply_to_id,
            is_forwarded=full_msg.is_forwarded,
            original_sender=full_msg.original_sender,
            sender_username=full_msg.sender.username,
            receiver_username=full_msg.receiver.username,
            voice_duration=full_msg.voice_duration,
            file_size=full_msg.file_size,
            seen_by=[MessageSeenByUser(**item) for item in seen_by],
            created_at=full_msg.created_at.isoformat()
        )
        
        # Add Telegram-style reply preview to response if exists
        if full_msg.reply_to:
            # Create compact preview for the response
            reply_content = full_msg.reply_to.content or ""
            if full_msg.reply_to.message_type == MessageType.voice:
                reply_content = "🎤 Voice message"
            elif full_msg.reply_to.message_type == MessageType.image:
                reply_content = "🖼️ Photo"
            elif full_msg.reply_to.message_type == MessageType.file:
                reply_content = "📎 File"
            elif len(reply_content) > 100:
                reply_content = reply_content[:100] + "..."
            
            # Add reply_preview to response
            response.reply_preview = ReplyPreview(
                id=full_msg.reply_to.id,
                sender_username=full_msg.reply_to.sender.username,
                content=reply_content,
                message_type=full_msg.reply_to.message_type.value,
                voice_duration=full_msg.reply_to.voice_duration,
                file_size=full_msg.reply_to.file_size
            )
            
            # Also include full reply object for detailed view
            reply_seen_by = []
            if full_msg.reply_to.seen_statuses:
                for status in full_msg.reply_to.seen_statuses:
                    reply_seen_by.append(MessageSeenByUser(
                        user_id=status.user.id,
                        username=status.user.username,
                        avatar_url=status.user.avatar_url,
                        seen_at=status.seen_at.isoformat() if status.seen_at else None
                    ))
            
            response.reply_to = MessageOut(
                id=full_msg.reply_to.id,
                sender_id=full_msg.reply_to.sender_id,
                receiver_id=full_msg.reply_to.receiver_id,
                content=full_msg.reply_to.content,
                message_type=full_msg.reply_to.message_type.value,
                is_read=full_msg.reply_to.is_read,
                read_at=full_msg.reply_to.read_at.isoformat() if full_msg.reply_to.read_at else None,
                delivered_at=full_msg.reply_to.delivered_at.isoformat() if full_msg.reply_to.delivered_at else None,
                reply_to_id=full_msg.reply_to.reply_to_id,
                is_forwarded=full_msg.reply_to.is_forwarded,
                original_sender=full_msg.reply_to.original_sender,
                created_at=full_msg.reply_to.created_at.isoformat(),
                sender_username=full_msg.reply_to.sender.username,
                receiver_username=full_msg.reply_to.receiver.username if full_msg.reply_to.receiver else None,
                voice_duration=full_msg.reply_to.voice_duration,
                file_size=full_msg.reply_to.file_size,
                seen_by=reply_seen_by
            )
        
        return response
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to send message: {str(e)}")
    
@router.get("/private/message/{message_id}/reply-context")
async def get_reply_context(
    message_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get full context of a replied message (for when user clicks on reply preview)
    """
    try:
        message = db.query(PrivateMessage).options(
            joinedload(PrivateMessage.sender),
            joinedload(PrivateMessage.receiver),
            joinedload(PrivateMessage.seen_statuses).joinedload(MessageSeenStatus.user)
        ).filter(PrivateMessage.id == message_id).first()
        
        if not message:
            raise HTTPException(status_code=404, detail="Message not found")
        
        # Check if user has access to this message
        if current_user.id not in [message.sender_id, message.receiver_id]:
            raise HTTPException(status_code=403, detail="No access to this message")
        
        # Build seen_by information
        seen_by = []
        for status in message.seen_statuses:
            seen_by.append(MessageSeenByUser(
                user_id=status.user.id,
                username=status.user.username,
                avatar_url=status.user.avatar_url,
                seen_at=status.seen_at.isoformat() if status.seen_at else None
            ))
        
        return MessageOut(
            id=message.id,
            sender_id=message.sender_id,
            receiver_id=message.receiver_id,
            content=message.content,
            message_type=message.message_type.value,
            is_read=message.is_read,
            read_at=message.read_at.isoformat() if message.read_at else None,
            delivered_at=message.delivered_at.isoformat() if message.delivered_at else None,
            reply_to_id=message.reply_to_id,
            is_forwarded=message.is_forwarded,
            original_sender=message.original_sender,
            created_at=message.created_at.isoformat(),
            sender_username=message.sender.username,
            receiver_username=message.receiver.username,
            voice_duration=message.voice_duration,
            file_size=message.file_size,
            seen_by=seen_by
        )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get reply context: {str(e)}")    

# Send voice message
@router.post("/private/{friend_id}/voice", response_model=MessageOut)
async def send_voice_message(
    friend_id: int,
    voice_file: UploadFile = File(...),
    duration: float = Form(...),
    reply_to_id: Optional[int] = Form(None),
    temp_id: Optional[str] = Form(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    FIXED VERSION: Better error handling and validation
    """
    try:
        print(f"🎤 Starting voice message from user {current_user.id} → friend {friend_id}")

        # Check friendship
        if not is_friend(db, current_user.id, friend_id):
            raise HTTPException(status_code=403, detail="Not friends")

        # Read and validate file
        contents = await voice_file.read()
        file_size = len(contents)

        if file_size == 0:
            raise HTTPException(status_code=400, detail="Empty audio file")
        if file_size > 15 * 1024 * 1024:  # 15MB max
            raise HTTPException(status_code=400, detail="Voice message too large (max 15MB)")

        # Validate duration
        if duration <= 0 or duration > 600:  # max 10 minutes
            raise HTTPException(status_code=400, detail="Invalid voice duration")

        print(f"📁 File received: {file_size} bytes, {duration:.1f}s")

        # FIX: Better error handling for upload
        try:
            upload_result = upload_voice_message(
                file_content=contents,
                public_id=f"voice_{current_user.id}_{uuid.uuid4().hex[:8]}",  # shorter ID
                folder="voice_messages"
            )
            voice_url = upload_result["secure_url"]
            
        except Exception as upload_error:
            print(f"❌ Cloudinary upload failed: {upload_error}")
            # FIX: More specific error message
            raise HTTPException(
                status_code=500, 
                detail=f"Failed to upload voice message: {str(upload_error)}"
            )

        # FIX: Wrap database operations in try-catch
        try:
            msg = create_private_message(
                db=db,
                sender_id=current_user.id,
                receiver_id=friend_id,
                content=voice_url,
                message_type="voice",
                reply_to_id=reply_to_id,
                voice_duration=round(duration, 2),
                file_size=file_size
            )
        except Exception as db_error:
            print(f"❌ Database error: {db_error}")
            raise HTTPException(status_code=500, detail="Failed to save message to database")

        # Load full message with all relations
        full_msg = db.query(PrivateMessage).options(
            joinedload(PrivateMessage.sender),
            joinedload(PrivateMessage.receiver),
            joinedload(PrivateMessage.seen_statuses).joinedload(MessageSeenStatus.user),
            joinedload(PrivateMessage.reply_to).joinedload(PrivateMessage.sender),
        ).filter(PrivateMessage.id == msg.id).first()

        if not full_msg:
            raise HTTPException(status_code=500, detail="Failed to load sent message")

        chat_id = _chat_id(current_user.id, friend_id)

        # Prepare WebSocket broadcast
        seen_by = [
            {
                "user_id": s.user.id,
                "username": s.user.username,
                "avatar_url": s.user.avatar_url,
                "seen_at": s.seen_at.isoformat() if s.seen_at else None
            }
            for s in full_msg.seen_statuses
        ]

        broadcast_data = {
            "type": "message",
            "id": full_msg.id,
            "temp_id": temp_id,
            "sender_id": full_msg.sender_id,
            "receiver_id": full_msg.receiver_id,
            "content": voice_url,
            "message_type": "voice",
            "voice_duration": round(duration, 2),
            "file_size": file_size,
            "is_read": False,
            "created_at": full_msg.created_at.isoformat(),
            "sender_username": full_msg.sender.username,
            "avatar_url": full_msg.sender.avatar_url or "",
            "seen_by": seen_by,
        }

        # Add reply preview (Telegram style)
        if full_msg.reply_to:
            reply = full_msg.reply_to
            reply_text = "Voice message"
            if reply.message_type == MessageType.text:
                reply_text = reply.content or "Message"
                if len(reply_text) > 80:
                    reply_text = reply_text[:80] + "..."
            elif reply.message_type == MessageType.image:
                reply_text = "Photo"
            elif reply.message_type == MessageType.file:
                reply_text = "File"

            broadcast_data["reply_preview"] = {
                "id": reply.id,
                "sender_username": reply.sender.username,
                "content": reply_text,
                "message_type": reply.message_type.value,
                "voice_duration": reply.voice_duration,
                "file_size": reply.file_size
            }

        # Send via WebSocket
        await manager.broadcast(chat_id, broadcast_data)

        # Build HTTP response
        response = MessageOut(
            id=full_msg.id,
            temp_id=temp_id,
            sender_id=full_msg.sender_id,
            receiver_id=full_msg.receiver_id,
            content=voice_url,
            message_type="voice",
            voice_duration=round(duration, 2),
            file_size=file_size,
            is_read=False,
            created_at=full_msg.created_at.isoformat(),
            sender_username=full_msg.sender.username,
            receiver_username=full_msg.receiver.username,
            seen_by=[MessageSeenByUser(**s) for s in seen_by],
        )

        # Add reply preview to response too
        if full_msg.reply_to:
            reply = full_msg.reply_to
            reply_text = "Voice message"
            if reply.message_type == MessageType.text:
                reply_text = (reply.content or "")[:100] + ("..." if len(reply.content or "") > 100 else "")
            elif reply.message_type == MessageType.image:
                reply_text = "Photo"
            elif reply.message_type == MessageType.file:
                reply_text = "File"

            response.reply_preview = ReplyPreview(
                id=reply.id,
                sender_username=reply.sender.username,
                content=reply_text,
                message_type=reply.message_type.value,
                voice_duration=reply.voice_duration,
                file_size=reply.file_size
            )

        print(f"VOICE MESSAGE SENT #{full_msg.id} | {duration}s | {file_size/1024:.1f}KB")
        return response

    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Voice message failed: {str(e)}")
    
@router.get("/cloudinary-health")
async def cloudinary_health_check():
    """Check Cloudinary connectivity and configuration"""
    try:
        is_healthy, message = check_cloudinary_health()
        
        # Test actual upload if configuration is OK
        if is_healthy:
            try:
                # Test with a small file
                test_content = b"test voice message content"
                test_result = upload_voice_message(
                    test_content,
                    public_id=f"health_check_{uuid.uuid4().hex}",
                    folder="health_checks"
                )
                return {
                    "status": "healthy",
                    "message": "Cloudinary is fully operational",
                    "upload_test": "success",
                    "cloud_name": settings.CLOUDINARY_CLOUD_NAME,
                    "base_folder": settings.CLOUDINARY_UPLOAD_FOLDER
                }
            except Exception as upload_error:
                return {
                    "status": "unhealthy", 
                    "message": f"Configuration OK but upload failed: {str(upload_error)}",
                    "upload_test": "failed",
                    "cloud_name": settings.CLOUDINARY_CLOUD_NAME,
                    "base_folder": settings.CLOUDINARY_UPLOAD_FOLDER
                }
        else:
            return {
                "status": "unhealthy",
                "message": message,
                "upload_test": "not_attempted",
                "cloud_name": settings.CLOUDINARY_CLOUD_NAME if hasattr(settings, 'CLOUDINARY_CLOUD_NAME') else "not_set",
                "base_folder": settings.CLOUDINARY_UPLOAD_FOLDER if hasattr(settings, 'CLOUDINARY_UPLOUD_FOLDER') else "not_set"
            }
            
    except Exception as e:
        return {
            "status": "error",
            "message": f"Health check failed: {str(e)}",
            "upload_test": "error"
        }
    
@router.post("/private/{friend_id}/image")
async def send_image_message(
    friend_id: int,
    image_url: str = Form(...),
    message_type: str = Form(default="image"),
    reply_to_id: int = Form(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Send an image message using pre-uploaded image URL
    """
    try:
        if not is_friend(db, current_user.id, friend_id):
            raise HTTPException(status_code=403, detail="Not friends")

        # Create message with image URL as content
        msg = create_private_message(
            db=db,
            sender_id=current_user.id,
            receiver_id=friend_id,
            content=image_url,
            message_type=message_type,
            reply_to_id=reply_to_id,
            is_forwarded=False,
            original_sender=None
        )
        
        # Get the full message with user relationships
        full_msg = db.query(PrivateMessage).options(
            joinedload(PrivateMessage.sender),
            joinedload(PrivateMessage.receiver),
            joinedload(PrivateMessage.seen_statuses).joinedload(MessageSeenStatus.user)
        ).filter(PrivateMessage.id == msg.id).first()
        
        if not full_msg:
            raise HTTPException(status_code=500, detail="Failed to retrieve created image message")
        
        chat_id = _chat_id(current_user.id, friend_id)
        
        # Prepare seen information
        seen_by = []
        for status in full_msg.seen_statuses:
            seen_by.append({
                "user_id": status.user.id,
                "username": status.user.username,
                "avatar_url": status.user.avatar_url,
                "seen_at": status.seen_at.isoformat() if status.seen_at else None
            })
        
        # Prepare broadcast data for image message
        broadcast_data = {
            "type": "message",
            "id": full_msg.id,
            "sender_id": full_msg.sender_id,
            "receiver_id": full_msg.receiver_id,
            "content": full_msg.content,
            "message_type": full_msg.message_type.value,
            "is_read": full_msg.is_read,
            "read_at": full_msg.read_at.isoformat() if full_msg.read_at else None,
            "delivered_at": full_msg.delivered_at.isoformat() if full_msg.delivered_at else None,
            "reply_to_id": full_msg.reply_to_id,
            "is_forwarded": full_msg.is_forwarded,
            "original_sender": full_msg.original_sender,
            "created_at": full_msg.created_at.isoformat(),
            "sender_username": full_msg.sender.username,
            "receiver_username": full_msg.receiver.username,
            "seen_by": seen_by
        }
        
        await manager.broadcast(chat_id, broadcast_data)
        
        return MessageOut(
            id=full_msg.id,
            sender_id=full_msg.sender_id,
            receiver_id=full_msg.receiver_id,
            content=full_msg.content,
            message_type=full_msg.message_type.value,
            is_read=full_msg.is_read,
            read_at=full_msg.read_at.isoformat() if full_msg.read_at else None,
            delivered_at=full_msg.delivered_at.isoformat() if full_msg.delivered_at else None,
            reply_to_id=full_msg.reply_to_id,
            is_forwarded=full_msg.is_forwarded,
            original_sender=full_msg.original_sender,
            sender_username=full_msg.sender.username,
            receiver_username=full_msg.receiver.username,
            created_at=full_msg.created_at.isoformat(),
            seen_by=[MessageSeenByUser(**item) for item in seen_by]
        )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to send image message: {str(e)}")

# Upload image to Cloudinary
@router.post("/private/{friend_id}/upload")
async def upload_image_to_cloudinary(
    friend_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Upload image to Cloudinary and return URL
    """
    try:
        if not is_friend(db, current_user.id, friend_id):
            raise HTTPException(status_code=403, detail="Not friends")

        if not file.content_type or not file.content_type.startswith("image/"):
            raise HTTPException(status_code=400, detail="Only image files allowed")

        try:
            # Generate unique filename
            file_extension = file.filename.split('.')[-1] if '.' in file.filename else 'jpg'
            unique_filename = f"chat_{current_user.id}_{friend_id}_{uuid.uuid4().hex}.{file_extension}"
            
            result = cloudinary.uploader.upload(
                file.file,
                folder="chat_images",
                public_id=unique_filename,
                resource_type="image",
                transformation=[
                    {"width": 800, "crop": "limit"},
                    {"quality": "auto"}
                ]
            )
            return {"url": result["secure_url"], "public_id": result["public_id"]}
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")
            
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to upload image: {str(e)}")

# Delete image message
@router.delete("/private/image/{message_id}")
async def delete_image_message(
    message_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Delete an image message and remove from Cloudinary
    """
    try:
        # Get the message with relationships
        message = db.query(PrivateMessage).options(
            joinedload(PrivateMessage.seen_statuses)
        ).filter(
            PrivateMessage.id == message_id,
            (PrivateMessage.sender_id == current_user.id) | (PrivateMessage.receiver_id == current_user.id)
        ).first()
        
        if not message:
            raise HTTPException(status_code=404, detail="Message not found")
        
        # Check if user has permission to delete (only sender can delete)
        if message.sender_id != current_user.id:
            raise HTTPException(status_code=403, detail="Can only delete your own messages")
        
        # Check if it's an image message
        if message.message_type.value != 'image':
            raise HTTPException(status_code=400, detail="Not an image message")
        
        # Extract public_id from Cloudinary URL
        image_url = message.content
        public_id = extract_public_id_from_url(image_url)
        
        # Delete from Cloudinary
        if public_id:
            try:
                cloudinary.uploader.destroy(public_id)
            except Exception as cloudinary_error:
                print(f"Cloudinary deletion failed: {str(cloudinary_error)}")
                # Continue with message deletion even if Cloudinary fails
        
        # Store info for WebSocket broadcast before deletion
        chat_id = _chat_id(message.sender_id, message.receiver_id)
        
        # Delete seen statuses first
        if message.seen_statuses:
            for seen_status in message.seen_statuses:
                db.delete(seen_status)
        
        # Delete the message from database
        db.delete(message)
        db.commit()
        
        # Notify via WebSocket
        await manager.broadcast(chat_id, {
            "type": "message_deleted",
            "message_id": message_id,
            "deleted_at": datetime.now(timezone.utc).isoformat()
        })
        
        return {"status": "success", "message": "Image message deleted", "message_id": message_id}
        
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to delete image message: {str(e)}")

# Enhanced delete endpoint for all message types
@router.delete("/private/{message_id}")
async def delete_message_forever_endpoint(
    message_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Enhanced delete to handle all message types with seen status
    """
    try:
        # Get the message first with all relationships
        message = db.query(PrivateMessage).options(
            joinedload(PrivateMessage.seen_statuses)
        ).filter(PrivateMessage.id == message_id).first()
        
        if not message:
            raise HTTPException(status_code=404, detail="Message not found")
        
        # Check permissions
        if message.sender_id != current_user.id:
            raise HTTPException(status_code=403, detail="Can only delete your own messages")
        
        # Store info for broadcast before deletion
        chat_id = _chat_id(message.sender_id, message.receiver_id)
        
        # If it's an image message, delete from Cloudinary first
        if message.message_type.value == 'image':
            image_url = message.content
            public_id = extract_public_id_from_url(image_url)
            
            if public_id:
                try:
                    cloudinary.uploader.destroy(public_id)
                except Exception as e:
                    print(f"Cloudinary deletion failed: {str(e)}")
                    # Continue with message deletion even if Cloudinary fails
        
        # Delete seen statuses first to avoid foreign key constraint
        if message.seen_statuses:
            for seen_status in message.seen_statuses:
                db.delete(seen_status)
            db.flush()  # Commit the deletion of seen statuses first
        
        # Now delete the message
        db.delete(message)
        db.commit()
        
        # Broadcast deletion
        await manager.broadcast(chat_id, {
            "type": "message_deleted", 
            "message_id": message_id,
            "deleted_at": datetime.now(timezone.utc).isoformat()
        })
        
        return {
            "status": "success", 
            "message": "Message deleted successfully",
            "message_id": message_id,
            "deleted_at": datetime.now(timezone.utc).isoformat()
        }
        
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        print(f"Delete error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to delete message: {str(e)}")

# Get message info for deletion confirmation
@router.get("/private/{friend_id}", response_model=List[MessageOut])
async def get_private_chat(
    friend_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if is_blocked(db, current_user.id, friend_id) or is_blocked_by(db, current_user.id, friend_id):
        return []

    if not is_friend(db, current_user.id, friend_id):
        raise HTTPException(status_code=403, detail="Not friends")

    messages = (
        db.query(PrivateMessage)
        .options(
            joinedload(PrivateMessage.sender),
            joinedload(PrivateMessage.receiver),
            joinedload(PrivateMessage.reply_to).joinedload(PrivateMessage.sender),
            joinedload(PrivateMessage.reply_to).joinedload(PrivateMessage.receiver),
            joinedload(PrivateMessage.seen_statuses).joinedload(MessageSeenStatus.user),
        )
        .filter(
            ((PrivateMessage.sender_id == current_user.id) & (PrivateMessage.receiver_id == friend_id)) |
            ((PrivateMessage.sender_id == friend_id) & (PrivateMessage.receiver_id == current_user.id))
        )
        .order_by(PrivateMessage.created_at.asc())
        .all()
    )

    result = []

    for msg in messages:
        seen_by = [
            MessageSeenByUser(
                user_id=s.user.id,
                username=s.user.username,
                avatar_url=s.user.avatar_url,
                seen_at=s.seen_at.isoformat() if s.seen_at else None
            )
            for s in msg.seen_statuses
        ]

        reply_to_out = None
        reply_preview = None

        if msg.reply_to:
            reply_to_out = MessageOut(
                id=msg.reply_to.id,
                sender_id=msg.reply_to.sender_id,
                receiver_id=msg.reply_to.receiver_id,
                content=msg.reply_to.content,
                message_type=serialize_message_type(msg.reply_to.message_type),
                is_read=msg.reply_to.is_read,
                read_at=msg.reply_to.read_at.isoformat() if msg.reply_to.read_at else None,
                delivered_at=msg.reply_to.delivered_at.isoformat() if msg.reply_to.delivered_at else None,
                reply_to=None,
                reply_to_id=msg.reply_to.reply_to_id,
                is_forwarded=msg.reply_to.is_forwarded,
                original_sender=msg.reply_to.original_sender,
                created_at=msg.reply_to.created_at.isoformat(),
                sender_username=msg.reply_to.sender.username,
                receiver_username=msg.reply_to.receiver.username,
                voice_duration=msg.reply_to.voice_duration,
                file_size=msg.reply_to.file_size,
                seen_by=[]
            )

            reply_preview = build_reply_preview(msg.reply_to)

        result.append(
            build_message_out(
                msg=msg,
                reply_to=reply_to_out,
                reply_preview=reply_preview,
                seen_by=seen_by
            )
        )

    return result

    """
    Get message information for deletion confirmation
    """
    try:
        message = db.query(PrivateMessage).filter(
            PrivateMessage.id == message_id,
            (PrivateMessage.sender_id == current_user.id) | (PrivateMessage.receiver_id == current_user.id)
        ).first()
        
        if not message:
            raise HTTPException(status_code=404, detail="Message not found")
        
        return {
            "id": message.id,
            "sender_id": message.sender_id,
            "content": message.content,
            "message_type": message.message_type.value,
            "created_at": message.created_at.isoformat(),
            "is_own_message": message.sender_id == current_user.id
        }
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get message info: {str(e)}")

# Edit message endpoint
@router.patch("/private/{message_id}")
async def edit_message(
    message_id: int,
    data: MessageCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Edit a message
    """
    try:
        # Edit the message
        msg = edit_private_message(db, message_id, current_user.id, data.content.strip())

        # Get complete message data with all relationships for WebSocket
        full_msg = db.query(PrivateMessage).options(
            joinedload(PrivateMessage.sender),
            joinedload(PrivateMessage.receiver),
            joinedload(PrivateMessage.seen_statuses).joinedload(MessageSeenStatus.user),
        ).filter(PrivateMessage.id == msg.id).first()

        if not full_msg:
            raise HTTPException(status_code=404, detail="Message not found after edit")

        chat_id = _chat_id(full_msg.sender_id, full_msg.receiver_id)
        
        # Prepare seen_by data
        seen_by = []
        for status in full_msg.seen_statuses:
            seen_by.append({
                "user_id": status.user.id,
                "username": status.user.username,
                "avatar_url": status.user.avatar_url,
                "seen_at": status.seen_at.isoformat() if status.seen_at else None
            })

        # Complete WebSocket payload
        payload = {
            "type": "message_updated", 
            "id": full_msg.id,
            "message_id": full_msg.id,  # Both id and message_id for compatibility
            "content": full_msg.content,
            "message_type": full_msg.message_type.value,
            "edited_at": full_msg.edited_at.isoformat(),
            "created_at": full_msg.created_at.isoformat(),
            "sender_id": full_msg.sender_id,
            "receiver_id": full_msg.receiver_id,
            "sender_username": full_msg.sender.username,
            "receiver_username": full_msg.receiver.username if full_msg.receiver else None,
            "avatar_url": full_msg.sender.avatar_url,
            "is_read": full_msg.is_read,
            "read_at": full_msg.read_at.isoformat() if full_msg.read_at else None,
            "seen_by": seen_by,
            "voice_duration": full_msg.voice_duration,
            "file_size": full_msg.file_size,
            "is_forwarded": full_msg.is_forwarded,
            "original_sender": full_msg.original_sender,
        }

        # Broadcast to all connected clients in the chat
        await manager.broadcast(chat_id, payload)
        print(f"✅ Broadcast message edit: {full_msg.id} to chat {chat_id}")
        
        # HTTP response
        return {
            "id": full_msg.id,
            "content": full_msg.content,
            "edited_at": full_msg.edited_at.isoformat(),
            "message_type": full_msg.message_type.value,
            "edited": True,
            "sender_username": full_msg.sender.username,
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Error editing message: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Failed to edit message: {str(e)}")

# Delete image from Cloudinary only
@router.post("/delete-image")
async def delete_cloudinary_image(
    data: dict,
    current_user: User = Depends(get_current_user)
):
    """
    Delete image from Cloudinary only
    """
    try:
        public_id = data.get("public_id")
        if not public_id:
            raise HTTPException(status_code=400, detail="public_id required")

        cloudinary.uploader.destroy(public_id)
        return {"status": "deleted"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Cloudinary delete failed: {str(e)}")
    
@router.get("/users/{user_id}/status")
async def get_user_online_status(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Get online status of a specific user"""
    try:
        # Verify friendship or same user
        if user_id != current_user.id and not is_friend(db, current_user.id, user_id):
            raise HTTPException(status_code=403, detail="Not friends")
            
        status_info = get_user_online_status(db, user_id)
        if not status_info:
            raise HTTPException(status_code=404, detail="User not found")
            
        return status_info
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get user status: {str(e)}")

@router.get("/friends/online-status")
async def get_friends_online_status(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Get online status of all friends"""
    try:
        friends_status = get_friends_online_status(db, current_user.id)
        return {"friends": friends_status}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get friends status: {str(e)}")

@router.post("/users/online-status/batch")
async def get_batch_online_status(
    user_ids: List[int],
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Get online status for multiple users"""
    try:
        # Limit the number of users to prevent abuse
        if len(user_ids) > 50:
            raise HTTPException(status_code=400, detail="Too many users requested")
            
        status_list = get_multiple_users_online_status(db, user_ids)
        return {"users": status_list}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get batch status: {str(e)}")
    
def serialize_message_type(message_type: MessageType | None) -> str:
    return message_type.value if message_type else MessageType.text.value


def build_reply_preview(reply: PrivateMessage) -> ReplyPreview:
    if reply.message_type == MessageType.voice:
        content = "🎤 Voice message"
    elif reply.message_type == MessageType.image:
        content = "🖼️ Photo"
    elif reply.message_type == MessageType.file:
        content = "📎 File"
    else:
        content = reply.content or ""
        if len(content) > 100:
            content = content[:100] + "..."

    return ReplyPreview(
        id=reply.id,
        sender_username=getattr(reply.sender, "username", "Unknown"),
        content=content,
        message_type=serialize_message_type(reply.message_type),
        voice_duration=reply.voice_duration,
        file_size=reply.file_size
    )


def build_message_out(
    msg: PrivateMessage,
    reply_to: MessageOut | None,
    reply_preview: ReplyPreview | None,
    seen_by: list
) -> MessageOut:
    return MessageOut(
        id=msg.id,
        sender_id=msg.sender_id,
        receiver_id=msg.receiver_id,
        content=msg.content or "",
        message_type=serialize_message_type(msg.message_type),

        is_read=msg.is_read,
        read_at=msg.read_at.isoformat() if msg.read_at else None,
        delivered_at=msg.delivered_at.isoformat() if msg.delivered_at else None,

        reply_to_id=msg.reply_to_id,
        reply_to=reply_to,
        reply_preview=reply_preview,

        is_forwarded=msg.is_forwarded,
        forwarded_from_id=msg.forwarded_from_id,
        original_sender=msg.original_sender,
        original_sender_avatar=msg.original_sender_avatar,

        created_at=msg.created_at.isoformat(),
        edited_at=msg.edited_at.isoformat() if msg.edited_at else None,

        sender_username=getattr(msg.sender, "username", None),
        receiver_username=getattr(msg.receiver, "username", None),

        voice_duration=msg.voice_duration,
        file_size=msg.file_size,
        seen_by=seen_by
    )

