import asyncio
import json
import traceback
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session, joinedload

from app.core.database import get_db
from app.core.security import get_current_user_ws, verify_token
from app.crud.friend import is_friend
from app.crud.chat import create_private_message, mark_message_as_read
from app.models.user import User
from app.models.message_seen_status import MessageSeenStatus
from app.models.private_message import PrivateMessage, MessageType
from app.models.group_message import GroupMessage
from app.models.group_message_seen import GroupMessageSeen
from app.schemas.chat import GroupMessageOut, ParentMessageResponse, AuthorResponse
from app.utils.chat_helpers import _chat_id, is_group_member, validate_reply_message
from app.crud.message import handle_forward_message, update_message, delete_message
from app.helpers.to_utc_iso import to_local_iso
from app.crud.reaction import create_reaction, delete_reaction
from app.schemas.reaction import ReactionCreate


router = APIRouter()

@router.websocket("/private/{friend_id}")
async def handle_websocket_private(
    websocket: WebSocket,
    friend_id: int,
    db: Session = Depends(get_db)
):
    
    from app.services.websocket_manager import manager

    current_user = None
    heartbeat_task = None
    
    try:
        token = None
        
        query_params = dict(websocket.query_params)
        if "token" in query_params:
            token = query_params["token"]
            
        if not token:
            token_header = websocket.headers.get("Authorization")
            if token_header and token_header.startswith("Bearer "):
                token = token_header.split(" ")[1]

        if not token:
            try:
                data = await asyncio.wait_for(websocket.receive_json(), timeout=10.0)
                if data.get("type") == "auth" and data.get("token"):
                    token = data["token"]
                else:
                    await websocket.close(code=4001, reason="Authentication required")
                    return
            except (asyncio.TimeoutError, json.JSONDecodeError):
                await websocket.close(code=4001, reason="Authentication timeout")
                return
        
        payload = verify_token(token)
        if not payload:
            await websocket.close(code=4001, reason="Invalid or expired token")
            return
        
        raw_user_id = payload.get("sub")
        if not raw_user_id:
            await websocket.close(code=4001, reason="Token missing sub")
            return
        
        try:
            user_id = int(raw_user_id)
        except (ValueError, TypeError):
            await websocket.close(code=4001, reason="Invalid user ID in token")
            return
        
        current_user = db.query(User).filter(User.id == user_id).first()
        if not current_user:
            await websocket.close(code=4001, reason="User not found")
            return
        
        if not is_friend(db, current_user.id, friend_id):
            await websocket.close(code=4003, reason="Not friends")
            return
        
        await websocket.accept()

        await websocket.send_json({
            "type": "auth_success",
            "message": "Authenticated successfully",
            "user_id": current_user.id,
            "username": current_user.username,
        })
        
        unread_msgs = db.query(PrivateMessage).filter(
            PrivateMessage.receiver_id == current_user.id,
            PrivateMessage.sender_id == friend_id,
            PrivateMessage.is_read == False
        ).all()

        seen_ids = []
        for msg in unread_msgs:
            msg.is_read = True
            msg.read_at = datetime.utcnow()
            
            existing_seen = db.query(MessageSeenStatus).filter(
                MessageSeenStatus.message_id == msg.id,
                MessageSeenStatus.user_id == current_user.id
            ).first()
            
            if not existing_seen:
                seen_status = MessageSeenStatus(
                    message_id=msg.id,
                    user_id=current_user.id,
                    seen_at=datetime.utcnow()
                )
                db.add(seen_status)
            
            seen_ids.append(msg.id)

        db.commit()
        
        chat_id = _chat_id(current_user.id, friend_id)
        await manager.connect(chat_id, websocket, user_id=current_user.id)
        
        async def send_heartbeat():
            try:
                while True:
                    await asyncio.sleep(25)
                    try:
                        await websocket.send_json({
                            "type": "ping",
                            "timestamp": datetime.utcnow().isoformat()
                        })
                        await manager.update_user_activity(current_user.id)
                    except Exception:
                        break
            except asyncio.CancelledError:
                raise
            except Exception as e:
                print(f"Heartbeat error: {e}")

        heartbeat_task = asyncio.create_task(send_heartbeat())

        while True:
            try:
                raw_data = await asyncio.wait_for(
                    websocket.receive_text(), 
                    timeout=35.0
                )
                
                await manager.update_user_activity(current_user.id)
                
                if raw_data.strip():
                    try:
                        data = json.loads(raw_data)
                        if data.get("type") == "pong":
                            continue
                    except json.JSONDecodeError:
                        if raw_data.strip() == "pong":
                            continue

                try:
                    data = json.loads(raw_data) if raw_data.strip() else {}
                except json.JSONDecodeError:
                    await websocket.send_json({
                        "type": "error",
                        "error": "Invalid JSON format"
                    })
                    continue

                msg_type = data.get("type")
                content = data.get("content")
                reply_to_id = data.get("reply_to_id")
                message_type = data.get("message_type", "text")
                voice_duration = data.get("voice_duration")
                file_size = data.get("file_size")
                temp_id = data.get("temp_id")
                
                if not msg_type:
                    await websocket.send_json({
                        "type": "error", 
                        "error": "Message type is required"
                    })
                    continue
                
                if msg_type == "message":
                    if message_type == "voice":
                        if not content or not content.startswith(('http://', 'https://')):
                            await websocket.send_json({
                                "type": "error",
                                "error": "Voice messages require a valid URL",
                                "temp_id": temp_id
                            })
                            continue
                    elif message_type == "file":
                        if not content or not content.startswith(('http://', 'https://')):
                            await websocket.send_json({
                                "type": "error",
                                "error": "File messages require a valid URL",
                                "temp_id": temp_id
                            })
                            continue
                    elif message_type == "image":
                        if not content or not content.startswith(('http://', 'https://')):
                            await websocket.send_json({
                                "type": "error",
                                "error": "Image messages require a valid URL",
                                "temp_id": temp_id
                            })
                            continue
                    else:
                        if not content or not content.strip():
                            await websocket.send_json({
                                "type": "error",
                                "error": "Message content cannot be empty",
                                "temp_id": temp_id
                            })
                            continue
                    
                    if reply_to_id:
                        try:
                            replied_message = validate_reply_message(db, reply_to_id, current_user.id, friend_id)
                            if not replied_message:
                                await websocket.send_json({
                                    "type": "error",
                                    "error": "Replied message not found",
                                    "temp_id": temp_id
                                })
                                continue
                        except HTTPException as e:
                            await websocket.send_json({
                                "type": "error", 
                                "error": e.detail,
                                "temp_id": temp_id
                            })
                            continue

                    try:
                        msg = create_private_message(
                            db=db,
                            sender_id=current_user.id,
                            receiver_id=friend_id,
                            content=content.strip() if message_type == "text" else content,
                            reply_to_id=reply_to_id,
                            message_type=message_type,
                            voice_duration=voice_duration,
                            file_size=file_size
                        )

                        full_msg = db.query(PrivateMessage).options(
                            joinedload(PrivateMessage.sender),
                            joinedload(PrivateMessage.receiver),
                            joinedload(PrivateMessage.seen_statuses).joinedload(MessageSeenStatus.user),
                            joinedload(PrivateMessage.reply_to).joinedload(PrivateMessage.sender),
                            joinedload(PrivateMessage.reply_to).joinedload(PrivateMessage.seen_statuses).joinedload(MessageSeenStatus.user)
                        ).filter(PrivateMessage.id == msg.id).first()

                        if not full_msg:
                            await websocket.send_json({
                                "type": "error", 
                                "error": "Failed to create message",
                                "temp_id": temp_id
                            })
                            continue

                        seen_by = []
                        if full_msg.seen_statuses:
                            for status in full_msg.seen_statuses:
                                seen_by.append({
                                    "user_id": status.user.id,
                                    "username": status.user.username,
                                    "avatar_url": status.user.avatar_url,
                                    "seen_at": status.seen_at.isoformat() if status.seen_at else None
                                })

                        message_data = {
                            "type": "message",
                            "id": full_msg.id,
                            "temp_id": data.get("temp_id"),
                            "sender_id": full_msg.sender_id,
                            "sender_username": current_user.username,
                            "receiver_id": full_msg.receiver_id,
                            "content": full_msg.content,
                            "message_type": full_msg.message_type.value,
                            "created_at": full_msg.created_at.isoformat(),
                            "reply_to_id": full_msg.reply_to_id,
                            "avatar_url": full_msg.sender.avatar_url,
                            "voice_duration": full_msg.voice_duration,
                            "file_size": full_msg.file_size,
                        }

                        if full_msg.reply_to:
                            reply_content = full_msg.reply_to.content or ""
                            if full_msg.reply_to.message_type == MessageType.voice:
                                reply_content = "🎤 Voice message"
                            elif full_msg.reply_to.message_type == MessageType.image:
                                reply_content = "🖼️ Photo"
                            elif full_msg.reply_to.message_type == MessageType.file:
                                reply_content = "📎 File"
                            elif len(reply_content) > 100:
                                reply_content = reply_content[:100] + "..."
                            
                            message_data["reply_preview"] = {
                                "id": full_msg.reply_to.id,
                                "sender_username": full_msg.reply_to.sender.username,
                                "content": reply_content,
                                "message_type": full_msg.reply_to.message_type.value,
                                "voice_duration": full_msg.reply_to.voice_duration,
                                "file_size": full_msg.reply_to.file_size
                            }
                            reply_seen_by = []
                            if hasattr(full_msg.reply_to, 'seen_statuses') and full_msg.reply_to.seen_statuses:
                                for status in full_msg.reply_to.seen_statuses:
                                    reply_seen_by.append({
                                        "user_id": status.user.id,
                                        "username": status.user.username,
                                        "avatar_url": status.user.avatar_url,
                                        "seen_at": status.seen_at.isoformat() if status.seen_at else None
                                    })
                            
                            message_data["reply_to"] = {
                                "id": full_msg.reply_to.id,
                                "sender_id": full_msg.reply_to.sender_id,
                                "content": full_msg.reply_to.content,
                                "message_type": full_msg.reply_to.message_type.value,
                                "sender_username": full_msg.reply_to.sender.username,
                                "voice_duration": full_msg.reply_to.voice_duration,
                                "created_at": full_msg.reply_to.created_at.isoformat(),
                                "file_size": full_msg.reply_to.file_size,
                            }

                        await manager.broadcast(chat_id, message_data)

                    except Exception as e:
                        print(f"Error sending message: {e}")
                        await websocket.send_json({
                            "type": "error",
                            "error": "Failed to send message",
                            "temp_id": temp_id
                        })

                elif msg_type == "read_message":
                    message_id = data.get("message_id")

                    if not message_id:
                        await websocket.send_json({
                            "type": "error",
                            "error": "message_id is required"
                        })
                        continue

                    try:
                        message = mark_message_as_read(
                            db=db,
                            message_id=message_id,
                            user_id=current_user.id
                        )

                        if not message:
                            await websocket.send_json({
                                "type": "error",
                                "error": "Message not found or not allowed"
                            })
                            continue

                        read_event = {
                            "type": "message_read",
                            "message_id": message.id,
                            "reader_id": current_user.id,
                            "reader_username": current_user.username,
                            "reader_avatar": current_user.avatar_url,
                            "read_at": message.read_at.isoformat()
                        }

                        await manager.broadcast(
                            chat_id=chat_id,
                            message=read_event,
                        )

                    except Exception as e:
                        print("Read error:", e)
                        await websocket.send_json({
                            "type": "error",
                            "error": "Failed to mark message as read"
                        })

                elif msg_type == "typing":
                    is_typing = data.get("is_typing", False)
                    await manager.broadcast(chat_id, {
                        "type": "typing",
                        "is_typing": is_typing,
                        "user_id": current_user.id,
                        "username": current_user.username
                    })

                elif msg_type == "delete":
                    message_id = data.get("message_id")
                    if not message_id:
                        await websocket.send_json({
                            "type": "error",
                            "error": "Message ID is required for deletion"
                        })
                        continue

                    try:
                        message = db.query(PrivateMessage).filter(
                            PrivateMessage.id == message_id,
                            PrivateMessage.sender_id == current_user.id
                        ).first()
                        
                        if message:
                            db.query(MessageSeenStatus).filter(
                                MessageSeenStatus.message_id == message_id
                            ).delete()
                            
                            db.delete(message)
                            db.commit()
                            
                            await manager.broadcast(chat_id, {
                                "type": "message_deleted",
                                "message_id": message_id,
                                "deleted_by": current_user.id,
                                "deleted_at": datetime.utcnow().isoformat()
                            })
                        else:
                            await websocket.send_json({
                                "type": "error",
                                "error": "Message not found or not authorized to delete"
                            })
                    except Exception as e:
                        db.rollback()
                        await websocket.send_json({
                            "type": "error",
                            "error": "Failed to delete message"
                        })

                elif msg_type == "edit":
                    message_id = data.get("message_id")
                    new_content = data.get("new_content")
                    
                    if not message_id or not new_content:
                        await websocket.send_json({
                            "type": "error",
                            "error": "Message ID and new content are required"
                        })
                        continue
                    
                    try:
                        message = db.query(PrivateMessage).filter(
                            PrivateMessage.id == message_id,
                            PrivateMessage.sender_id == current_user.id
                        ).first()
                        
                        if message:
                            message.content = new_content
                            message.edited_at = datetime.utcnow()
                            db.commit()
                            
                            await manager.broadcast(chat_id, {
                                "type": "message_edited",
                                "message_id": message_id,
                                "new_content": new_content,
                                "edited_by": current_user.id,
                                "edited_at": datetime.utcnow().isoformat()
                            })
                        else:
                            await websocket.send_json({
                                "type": "error",
                                "error": "Message not found or not authorized to edit"
                            })
                    except Exception as e:
                        db.rollback()
                        await websocket.send_json({
                            "type": "error",
                            "error": "Failed to edit message"
                        })

                elif msg_type == "get_online_users":
                    online_users = manager.get_online_users(chat_id)
                    await websocket.send_json({
                        "type": "online_users",
                        "user_ids": list(online_users),
                        "timestamp": datetime.utcnow().isoformat()
                    })
                    
                elif msg_type == "reaction_add":
                    message_id = data.get("message_id")
                    emoji = data.get("emoji")
                    
                    if not message_id or not emoji:
                        await websocket.send_json({
                            "type": "error",
                            "error": "Message ID and emoji are required"
                        })
                        continue
                    
                    try:
                        reaction_in = ReactionCreate(emoji=emoji)
                        reaction = create_reaction(db, message_id, current_user.id, reaction_in)
                        
                        await manager.broadcast(chat_id, {
                            "type": "reaction_added",
                            "message_id": message_id,
                            "reaction": {
                                "id": reaction.id,
                                "emoji": reaction.emoji,
                                "user_id": reaction.user_id,
                                "user": {
                                    "id": reaction.user.id,
                                    "username": reaction.user.username,
                                    "avatar_url": reaction.user.avatar_url
                                },
                                "created_at": reaction.created_at.isoformat()
                            }
                        })
                    except Exception as e:
                        await websocket.send_json({
                            "type": "error",
                            "error": "Failed to add reaction"
                        })
                        
                elif msg_type == "reaction_remove":
                    message_id = data.get("message_id")
                    reaction_id = data.get("reaction_id")
                    
                    if not message_id or not reaction_id:
                        await websocket.send_json({
                            "type": "error",
                            "error": "Message ID and reaction ID are required"
                        })
                        continue
                    
                    try:
                        success, error_message = delete_reaction(db, message_id, reaction_id, current_user.id)
                        
                        if success:
                            await manager.broadcast(chat_id, {
                                "type": "reaction_removed",
                                "message_id": message_id,
                                "reaction_id": reaction_id,
                                "user_id": current_user.id,
                                "timestamp": datetime.utcnow().isoformat()
                            })
                            
                            await websocket.send_json({
                                "type": "reaction_removed",
                                "message_id": message_id,
                                "reaction_id": reaction_id,
                                "success": True
                            })
                        else:
                            await websocket.send_json({
                                "type": "error",
                                "error": f"Failed to remove reaction: {error_message}",
                                "success": False
                            })
                            
                    except Exception as e:
                        await websocket.send_json({
                            "type": "error",
                            "error": f"Failed to remove reaction: {str(e)}",
                            "success": False
                        })
                        
                elif msg_type == "check_user_status":
                    user_id_to_check = data.get("user_id")
                    if user_id_to_check:
                        is_online = manager.is_user_online(user_id_to_check)
                        last_activity = manager.get_user_last_activity(user_id_to_check)
                        
                        await websocket.send_json({
                            "type": "user_status",
                            "user_id": user_id_to_check,
                            "is_online": is_online,
                            "last_activity": last_activity.isoformat() if last_activity else None,
                            "timestamp": datetime.utcnow().isoformat()
                        })

                elif msg_type == "heartbeat":
                    await websocket.send_json({
                        "type": "pong",
                        "timestamp": datetime.utcnow().isoformat()
                    })
                    pass

                elif msg_type == "forward":
                    message_id = data.get("message_id")
                    target_user_ids = data.get("target_user_ids", [])

                    if not message_id or not target_user_ids:
                        await websocket.send_json({
                            "type": "error",
                            "error": "Message ID and target users are required"
                        })
                        continue

                    try:
                        original_msg = db.query(PrivateMessage).filter(
                            PrivateMessage.id == message_id
                        ).first()
                        if not original_msg:
                            raise Exception("Original message not found")

                        forwarded_to = []

                        for target_user_id in target_user_ids:
                            if target_user_id == current_user.id:
                                continue  # Skip self
                            if not is_friend(db, current_user.id, target_user_id):
                                continue  # Skip non-friends

                            # Create forwarded message
                            forwarded_msg = create_private_message(
                                db=db,
                                sender_id=current_user.id,
                                receiver_id=target_user_id,
                                content=original_msg.content,
                                message_type=original_msg.message_type.value,
                                voice_duration=original_msg.voice_duration,
                                file_size=original_msg.file_size,
                                is_forwarded=True,
                                forwarded_from_id=original_msg.sender_id,
                                original_sender=original_msg.sender.username if original_msg.sender else None,
                                original_sender_avatar=original_msg.sender.avatar_url if original_msg.sender else None,
                            )

                            # Send to the specific user using your manager
                            payload = {
                                "type": "message",
                                "id": forwarded_msg.id,
                                "content": forwarded_msg.content,
                                "message_type": forwarded_msg.message_type.value,
                                "sender_id": current_user.id,
                                "sender_username": current_user.username,
                                "is_forwarded": True,
                                "forwarded_from_id": original_msg.sender_id,
                                "voice_duration": forwarded_msg.voice_duration,
                                "file_size": forwarded_msg.file_size,
                                "created_at": forwarded_msg.created_at.isoformat(),
                                "is_read": False,
                                "original_sender": forwarded_msg.original_sender,
                                "original_sender_avatar": forwarded_msg.original_sender_avatar
                            }

                            # Use your WebSocketManager method to send directly to the user
                            user_chats = manager.get_user_chats(target_user_id)
                            for chat_id in user_chats:
                                await manager.send_to_user(chat_id, target_user_id, payload)

                            forwarded_to.append(target_user_id)

                        if not forwarded_to:
                            raise Exception("No valid recipients to forward message")

                        await websocket.send_json({
                            "type": "forward_success",
                            "forwarded_to": forwarded_to
                        })

                    except Exception as e:
                        import traceback
                        traceback.print_exc()
                        await websocket.send_json({
                            "type": "error",
                            "error": str(e)
                        })

                
                elif msg_type == "call_start":
                    call_type = data.get("call_type")
                    friend_id = data.get("to_user")
                    
                    if not friend_id:
                        await websocket.send_json({
                            "type": "call_error",
                            "error": "Missing call recipient"
                        })
                        continue
                    
                    if current_user.id == friend_id:
                        await websocket.send_json({
                            "type": "call_error",
                            "error": "You cannot call yourself"
                        })
                        continue

                    if chat_id in manager.active_calls:
                        await websocket.send_json({
                            "type": "call_error",
                            "error": "Call already in progress"
                        })
                        continue

                    # Create call session
                    timeout_task = asyncio.create_task(manager._auto_cancel_call(chat_id))

                    system_msg = PrivateMessage(
                        receiver_id=friend_id,
                        sender_id=current_user.id,
                        content=f"{current_user.username} started a {call_type} call",
                        message_type="system",
                        created_at=datetime.now(timezone.utc)
                    )
                    db.add(system_msg)
                    db.commit()
                    db.refresh(system_msg)
                    
                    manager.active_calls[chat_id] = {
                        "caller": current_user.id,
                        "receiver": friend_id,
                        "call_type": call_type,
                        "status": "ringing",
                        "timeout_task": timeout_task
                    }
                    
                    await manager.broadcast(chat_id, {
                        "type": "new_call_message",
                        "message_id": system_msg.id,
                        "sender_id": current_user.id,
                        "sender": {
                            "id": current_user.id,
                            "username": current_user.username,
                            "avatar": current_user.avatar_url
                        },
                        "content": system_msg.content,
                        "created_at": system_msg.created_at.isoformat(),
                        "message_type": "system"
                    })

                    await manager.broadcast(chat_id, {
                        "type": "call_request",
                        "call_type": call_type,
                        "from_user": current_user.id,
                        "sender_username": current_user.username,
                        "avatar_url": current_user.avatar_url,
                        "timestamp": system_msg.created_at.isoformat()
                    })
                    
                elif msg_type == "call_offer":
                    to_user = data.get("to_user")
                    offer = data.get("offer")

                    if not to_user or not offer:
                        continue

                    await manager.send_to_user(chat_id, to_user, {
                        "type": "call_offer",
                        "from_user": current_user.id,
                        "username": current_user.username,
                        "avatar": current_user.avatar_url,
                        "offer": offer,
                        "call_type": manager.active_calls[chat_id]["call_type"]
                    })
                
                elif msg_type == "call_answer":
                    to_user = data.get("to_user")
                    answer = data.get("answer")

                    if not to_user or not answer:
                        continue

                    await manager.send_to_user(chat_id, to_user, {
                        "type": "call_answer",
                        "from_user": current_user.id,
                        "username": current_user.username,
                        "avatar": current_user.avatar_url,
                        "answer": answer
                    })
                elif msg_type == "call_ice":
                    to_user = data.get("to_user")
                    candidate = data.get("candidate")

                    if not to_user or not candidate:
                        continue

                    await manager.send_to_user(chat_id, to_user, {
                        "type": "call_ice",
                        "from_user": current_user.id,
                        "candidate": candidate
                    })

                elif msg_type == "call_accept":
                    call = manager.active_calls.get(chat_id)

                    await manager.broadcast(chat_id, {
                        "type": "call_accepted",
                        "from_user": current_user.id,
                        "timestamp": datetime.utcnow().isoformat()
                    })

                elif msg_type == "call_reject":
                    call = manager.active_calls.get(chat_id)

                    if not call:
                        continue

                    await manager._end_call(chat_id, "rejected", ended_by=current_user.id)

                elif msg_type == "call_end":
                    call = manager.active_calls.get(chat_id)

                    if not call:
                        continue

                    await manager._end_call(chat_id, "ended", ended_by=current_user.id)

                else:
                    await websocket.send_json({
                        "type": "error",
                        "error": f"Unknown message type: {msg_type}"
                    })

            except asyncio.TimeoutError:
                print(f"Timeout waiting for message from user {current_user.id}")
                continue
                
            except WebSocketDisconnect:
                print(f"User {current_user.id} disconnected from WebSocket")
                break
                
            except Exception as e:
                print(f"WebSocket error for user {current_user.id}: {e}")
                try:
                    await websocket.send_json({
                        "type": "error",
                        "error": "Internal server error"
                    })
                except Exception:
                    break  # Client disconnected

    except WebSocketDisconnect:
        print(f"User {current_user.id if current_user else 'unknown'} disconnected normally")
    except Exception as e:
        print(f"WebSocket connection error: {e}")
    finally:
        try:
            if heartbeat_task:
                heartbeat_task.cancel()
                try:
                    await heartbeat_task
                except asyncio.CancelledError:
                    print("Heartbeat task cancelled successfully")
        except Exception as e:
            print(f"Error cancelling heartbeat: {e}")

        if current_user:
            chat_id = _chat_id(current_user.id, friend_id)
            manager.disconnect(chat_id, websocket, user_id=current_user.id)
            print(f"User {current_user.id} fully disconnected from chat {chat_id}")        
            
@router.websocket("/notifications")
async def websocket_notifications(websocket: WebSocket, db: Session = Depends(get_db)):
    """
    Unified WebSocket endpoint for all notifications
    """
    from app.services.websocket_manager import manager
    
    current_user: User | None = None

    try:
        # Accept connection first
        await websocket.accept()
        
        print("🔌 Notifications WebSocket connection accepted")
        
        # 1. First try to get token from query params
        token = None
        query_params = dict(websocket.query_params)
        if "token" in query_params:
            token = query_params["token"]
            print(f"🔑 Token from query params: {token[:20]}...")
        
        # 2. If no token in query params, check headers
        if not token:
            token_header = websocket.headers.get("Authorization")
            if token_header and token_header.startswith("Bearer "):
                token = token_header.split(" ")[1]
                print(f"🔑 Token from headers: {token[:20]}...")
        
        # 3. If still no token, wait for auth message
        if not token:
            try:
                print("⏳ Waiting for auth message...")
                data = await asyncio.wait_for(websocket.receive_json(), timeout=10.0)
                if data.get("type") == "auth" and data.get("token"):
                    token = data["token"]
                    print(f"🔑 Token from auth message: {token[:20]}...")
                else:
                    await websocket.close(code=4001, reason="Authentication required")
                    return
            except (asyncio.TimeoutError, json.JSONDecodeError):
                await websocket.close(code=4001, reason="Authentication timeout")
                return
        
        # Verify token
        print("🔍 Verifying token...")
        payload = verify_token(token)
        if not payload:
            print("❌ Token verification failed")
            await websocket.send_json({
                "type": "auth_error",
                "error": "Invalid or expired token"
            })
            await websocket.close(code=4001, reason="Invalid or expired token")
            return
        
        # Get user ID from token
        raw_user_id = payload.get("sub")
        if not raw_user_id:
            print("❌ Token missing sub claim")
            await websocket.send_json({
                "type": "auth_error",
                "error": "Token missing user ID"
            })
            await websocket.close(code=4001, reason="Token missing sub")
            return
        
        try:
            user_id = int(raw_user_id)
        except (ValueError, TypeError):
            print(f"❌ Invalid user ID in token: {raw_user_id}")
            await websocket.send_json({
                "type": "auth_error",
                "error": "Invalid user ID in token"
            })
            await websocket.close(code=4001, reason="Invalid user ID in token")
            return
        
        # Load user from DB
        print(f"👤 Loading user with ID: {user_id}")
        current_user = db.query(User).filter(User.id == user_id).first()
        if not current_user:
            print(f"❌ User not found with ID: {user_id}")
            await websocket.send_json({
                "type": "auth_error",
                "error": "User not found"
            })
            await websocket.close(code=4001, reason="User not found")
            return
        
        print(f"✅ User authenticated: {current_user.username} (ID: {current_user.id})")

        # 4. Success – send auth_success
        await websocket.send_json({
            "type": "auth_success",
            "message": "Authenticated successfully",
            "user_id": current_user.id,
            "username": current_user.username,
        })

        # 5. Join user's notification room
        user_room = f"user_{current_user.id}"
        await manager.connect(user_room, websocket, user_id=current_user.id)

        print(f"📢 User {current_user.id} ({current_user.username}) connected to notifications")

        # 6. Keep-alive loop
        while True:
            try:
                msg = await websocket.receive_json()
                if msg.get("type") == "ping":
                    await websocket.send_json({"type": "pong"})
                elif msg.get("type") == "heartbeat":
                    # Update user activity
                    await manager.update_user_activity(current_user.id)
                    await websocket.send_json({"type": "pong"})
            except WebSocketDisconnect:
                print(f"📢 User {current_user.id} disconnected from notifications")
                break
            except Exception as e:
                print(f"📢 Message handling error: {e}")
                continue

    except WebSocketDisconnect:
        print(f"📢 Notifications WebSocket disconnected normally")
    except Exception as e:
        print(f"❌ Notification WS authentication error: {e}")
        traceback.print_exc()
        try:
            await websocket.close(code=1011, reason=f"Authentication failed: {str(e)}")
        except:
            pass
    finally:
        if current_user:
            await manager.disconnect(f"user_{current_user.id}", websocket)
            print(f"📢 User {current_user.id} disconnected from notifications")
            
@router.websocket("/group/{group_id}")
async def websocket_group_chat(
    websocket: WebSocket,
    group_id: int,
):
    
    from app.services.ws_manager_group import manager
    
    db = next(get_db())
    try:
        current_user = await get_current_user_ws(websocket, db)
        if not current_user:
            await websocket.close(code=4001, reason="Please login to use chat")
            return

        if not is_group_member(db, group_id, current_user.id):
            await websocket.close(code=4003, reason="Not a member of this group")
            return
        
        await websocket.accept()

        chat_id = f"group_{group_id}"
        await manager.connect(chat_id, websocket, user_id=current_user.id)

        try:
            while True:
                data = await websocket.receive_json()
                message_type = data.get("message_type", "text")
                content = data.get("content")
                parent_message_id = data.get("reply_to")  # Optional
                action = data.get("action")
                incoming_temp_id = data.get("temp_id")
                to_user = data.get("to_user")
                sdp = data.get("sdp")
                
                if action == "online_users":
                    online_user_ids = list(manager.get_online_users(chat_id))
                    await websocket.send_json({
                        "action": "online_users",
                        "user_ids": online_user_ids
                    })

                if action == "seen":
                    message_id = int(data.get("message_id"))

                    msg = db.query(GroupMessage).filter(
                        GroupMessage.id == message_id,
                        GroupMessage.group_id == group_id
                    ).first()
                    if not msg:
                        continue

                    seen_record = db.query(GroupMessageSeen).filter_by(
                        message_id=message_id,
                        user_id=current_user.id
                    ).first()

                    now = datetime.utcnow()

                    if not seen_record:
                        seen_record = GroupMessageSeen(
                            message_id=message_id,
                            user_id=current_user.id,
                            seen=True,
                            seen_at=to_local_iso(now, tz_offset_hours=7),
                        )
                        db.add(seen_record)
                        db.commit()
                    else:
                        if seen_record.seen:
                            continue

                        seen_record.seen = True
                        seen_record.seen_at = to_local_iso(now, tz_offset_hours=7)
                        db.commit()

                    await manager.broadcast(chat_id, {
                        "action": "seen",
                        "message_id": message_id,
                        "user_id": current_user.id,                                   
                        "seen_at": to_local_iso(now, tz_offset_hours=7)
                    })
                    continue

                if action == "forward_to_groups": 
                    message_id = data.get("message_id")
                    target_group_ids = [int(g) for g in data.get("group_ids", [])]
                    target_group_ids = [gid for gid in target_group_ids if gid != group_id]
                    
                    if not target_group_ids:
                        continue
                    
                    forwarded_msgs = await handle_forward_message(
                        db,
                        current_user_id=current_user.id,
                        message_id=message_id,
                        target_group_ids=target_group_ids
                    )

                    for gid, fwd_msg in zip(target_group_ids, forwarded_msgs):
                        target_chat_id = f"group_{gid}"
                        await manager.broadcast(target_chat_id, {
                            "action": "new_message",
                            **fwd_msg
                        })
                    continue

                if action == "edit":
                    message_id = int(data.get("message_id"))
                    new_content = data.get("new_content")
                    now = datetime.utcnow()

                    updated = update_message(
                        db=db,
                        message_id=message_id,
                        content=new_content,
                        current_user_id=current_user.id,
                    )

                    await manager.broadcast(chat_id, {
                        "action": "edit",
                        "message_id": message_id,
                        "new_content": new_content,
                        "updated_at": to_local_iso(updated.updated_at, tz_offset_hours=7)
                    })
                    continue
                
                if action == "delete":
                    message_id = int(data.get("message_id"))
                    await delete_message(db, message_id, current_user.id)
                    
                    await manager.broadcast(chat_id, {
                        "action": "delete",
                        "message_id": message_id
                    })
                    continue
                
                if action == "file_upload":
                    file_url = data.get("file_url")
                    message_id = data.get("message_id")
                    
                    msg = db.query(GroupMessage).filter(GroupMessage.id == message_id).first()
                    if not msg:
                        continue
                    
                    await manager.broadcast(chat_id, {
                        "action": "file_upload",
                        "id": msg.id,
                        "sender": {
                            "id": msg.sender.id,
                            "username": msg.sender.username,
                            "avatar_url": msg.sender.avatar_url
                        },
                        "file_url": msg.file_url,
                        "created_at": to_local_iso(msg.created_at, tz_offset_hours=7),
                        "temp_id": incoming_temp_id
                    })
                    continue

                if action == "file_update":
                    message_id = data.get("message_id")
                    file_url = data.get("file_url")
                    
                    msg = db.query(GroupMessage).filter(GroupMessage.id == message_id).first()
                    if not msg:
                        continue

                    await manager.broadcast(chat_id, {
                        "action": "file_update",
                        "message_id": msg.id,
                        "file_url": file_url,
                        "updated_at": to_local_iso(msg.updated_at, tz_offset_hours=7),
                        "temp_id": incoming_temp_id
                    })
                    continue
                
                if action == "voice_upload":
                    voice_url = data.get("voice_url")
                    message_id = data.get("message_id")
                    message_type = data.get("message_type", "voice")
                    
                    msg = db.query(GroupMessage).filter(GroupMessage.id == message_id).first()
                    if not msg:
                        continue
                    
                    await manager.broadcast(chat_id, {
                        "action": "voice_upload",
                        "id": msg.id,
                        "sender": {
                            "id": msg.sender.id,
                            "username": msg.sender.username,
                            "avatar_url": msg.sender.avatar_url
                        },
                        "voice_url": voice_url,
                        "message_type": message_type,
                        "created_at": to_local_iso(msg.created_at, tz_offset_hours=7),
                        "temp_id": incoming_temp_id
                    })
                    continue
                
                if action == "call_start":
                    
                    system_msg = GroupMessage(
                        group_id=group_id,
                        sender_id=current_user.id,
                        call_content=f"{current_user.username} started a video call",
                        message_type="system"
                    )
                    db.add(system_msg)
                    db.commit()
                    db.refresh(system_msg)
                    
                    manager.group_call_sessions[chat_id] =   {
                        "start_message_id": system_msg.id,
                        "start_time": datetime.utcnow(),
                        "end_time": None,
                        "can_join": True,
                        "starter_id": current_user.id,
                        "starter_name": current_user.username,
                        "call_type": "video"
                    }
                    
                    await manager.broadcast(chat_id, {
                        "action": "new_call_message",
                        "id": system_msg.id,
                        "sender": {
                            "id": current_user.id,
                            "username": current_user.username,
                            "avatar_url": current_user.avatar_url,
                        },
                        "call_content": system_msg.call_content,
                        "can_join": True,
                        "message_type": "system",
                        "created_at": to_local_iso(system_msg.created_at, tz_offset_hours=7),
                    })
                    
                    await manager.broadcast(chat_id, {
                        "action": "call_request",
                        "from_user": current_user.id,
                        "username": current_user.username,
                        "avatar_url": current_user.avatar_url,
                        "call_type": "video"
                    })
                    
                    ## auto close if no one accepted
                    async def auto_close_no_accept(chat_id: str, db):
                        await asyncio.sleep(30)
                        if manager.get_total_accepted(chat_id) == 0:
                            await manager.end_group_call(chat_id, db)

                    asyncio.create_task(auto_close_no_accept(chat_id, db))
                    continue
                
                if action == "call_start_voice":
                    
                    system_msg = GroupMessage(
                        group_id=group_id,
                        sender_id=current_user.id,
                        call_content=f"{current_user.username} started a voice call",
                        message_type="system"
                    )
                    db.add(system_msg)
                    db.commit()
                    db.refresh(system_msg)
                    
                    manager.group_call_sessions[chat_id] = {
                        "start_message_id": system_msg.id,
                        "start_time": datetime.utcnow(),
                        "end_time": None,
                        "can_join": True,
                        "starter_id": current_user.id,
                        "starter_name": current_user.username,
                        "call_type": "voice"
                    }
                    
                    await manager.broadcast(chat_id, {
                        "action": "new_call_message",
                        "id": system_msg.id,
                        "sender": {
                            "id": current_user.id,
                            "username": current_user.username,
                            "avatar_url": current_user.avatar_url,
                        },
                        "call_content": system_msg.call_content,
                        "can_join": True,
                        "message_type": "system",
                        "created_at": to_local_iso(system_msg.created_at, tz_offset_hours=7),
                    })
                    
                    await manager.broadcast(chat_id, {
                        "action": "call_request",
                        "from_user": current_user.id,
                        "username": current_user.username,
                        "avatar_url": current_user.avatar_url,
                        "call_type": "voice"
                    })
                    
                    ## auto close if no one accepted
                    async def auto_close_no_accept(chat_id: str, db):
                        await asyncio.sleep(30)
                        if manager.get_total_accepted(chat_id) == 0:
                            await manager.end_group_call(chat_id, db)

                    asyncio.create_task(auto_close_no_accept(chat_id, db))
                    continue
                
                if action == "call_accept":
                    manager.mark_user_accepted(chat_id, current_user.id)
                    
                    await manager.send_to_user(chat_id, to_user, {
                        "action": "call_accepted",
                        "from_user": current_user.id,
                        "username": current_user.username,
                        "avatar_url": current_user.avatar_url,
                    })
                    
                    total_accepted = manager.get_total_accepted(chat_id)
                    await manager.broadcast(chat_id, {
                        "action": "total_accepted",
                        "total": total_accepted
                    })

                    if total_accepted > 1 and chat_id not in manager.call_timers:
                        manager.call_timers[chat_id] = asyncio.create_task(
                            auto_end_call(chat_id, db)
                        )
                    continue
                
                if action == "call_reject":
                    await manager.send_to_user(chat_id, to_user, {
                        "action": "call_rejected",
                        "from_user": current_user.id,
                        "username": current_user.username,
                        "avatar_url": current_user.avatar_url,
                    })
                    continue

                if action == "call_join":
                    manager.mark_user_accepted(chat_id, current_user.id)
                    
                    session = manager.group_call_sessions.get(chat_id)
                    if session:
                        await websocket.send_json({
                            "action": "call_info",
                            "call_type": session.get("call_type", "video"),   # "video" | "voice"
                            "is_audio_only": session.get("call_type") == "voice",
                            "starter_id": session.get("starter_id"),
                            "starter_name": session.get("starter_name"),
                        })
                    
                    await manager.broadcast(chat_id,{
                        "action": "call_join",
                        "user_id": current_user.id,
                        "username": current_user.username,
                        "avatar_url": current_user.avatar_url,
                    }, exclude={websocket})
                    
                    await manager.broadcast(chat_id, {
                        "action": "call_new_peer",
                        "new_user_id": current_user.id,
                        "username": current_user.username,
                        "avatar_url": current_user.avatar_url
                    }, exclude={websocket})
                    
                    total_accepted = manager.get_total_accepted(chat_id)
                    await manager.broadcast(chat_id, {
                        "action": "total_accepted",
                        "total": total_accepted
                    })
                    continue
                
                if action == "call_leave":
                    
                    manager.remove_user_accepted(chat_id, current_user.id)
                    total_accepted = manager.get_total_accepted(chat_id)
                    
                    await manager.broadcast(chat_id,{
                        "action": "call_leave",
                        "user_id": current_user.id
                    })
                    
                    await manager.broadcast(chat_id, {
                        "action": "total_accepted",
                        "total": total_accepted
                    })
                    
                    session = manager.group_call_sessions.get(chat_id)
                    if session:
                        starter_id = session.get("starter_id")
                        message_id = session.get("start_message_id")
                        if message_id:
                            msg = db.query(GroupMessage).filter(GroupMessage.id == message_id).first()
                            if msg and current_user.id == starter_id:
                                call_type = session.get("call_type", "call")
                                type_text = "video call" if call_type == "video" else "voice call"
                                starter_name = session.get("starter_name", "Someone")

                                msg.call_content = f"{starter_name} ended the {type_text}"
                                msg.updated_at = datetime.utcnow()
                                db.commit()

                                # Broadcast call end immediately
                                await manager.broadcast(chat_id, {
                                    "action": "call_end",
                                    "call_message_id": message_id,
                                    "call_content": msg.call_content,
                                    "can_join": False,
                                    "updated_at": to_local_iso(msg.updated_at, tz_offset_hours=7)
                                })

                    
                    timer = manager.call_timers.pop(chat_id, None)
                    if timer:
                        timer.cancel()
                    
                    if total_accepted < 1:
                        await manager.end_group_call(chat_id, db)
                    continue
                
                if action == "call_offer":
                    await manager.send_to_user(chat_id, to_user, {
                        "action": "call_offer",
                        "from_user": current_user.id,
                        "username": current_user.username,
                        "avatar_url": current_user.avatar_url,
                        "sdp": sdp
                    })
                    continue
                
                if action == "call_answer":
                    await manager.send_to_user(chat_id, to_user, {
                        "action": "call_answer",
                        "from_user": current_user.id,
                        "username": current_user.username,
                        "avatar_url": current_user.avatar_url,
                        "sdp": sdp
                    })
                    continue
                
                if action == "call_ice":
                    await manager.send_to_user(chat_id, to_user, {
                        "action": "call_ice",
                        "from_user": current_user.id,
                        "candidate": data["candidate"]
                    })
                    continue
                
                try:
                    msg = GroupMessage(
                        group_id=group_id,
                        sender_id=current_user.id,
                        content=content,
                        message_type=message_type,
                        parent_message_id=parent_message_id
                    )
                    db.add(msg)
                    db.commit()
                    db.refresh(msg)
                except Exception as e:
                    db.rollback()
                    print(f"[DB Error] {e}")
                    await websocket.send_json({
                        "error": "Failed to save message",
                        "temp_id": incoming_temp_id
                    })
                    continue

                parent_msg_data = None
                if msg.parent_message:
                    parent = msg.parent_message
                    parent_msg_data = {
                        "id": parent.id,
                        "content": parent.content,
                        "call_content": parent.call_content,
                        "file_url": parent.file_url,
                        "voice_url": parent.voice_url,
                        "sender": {
                            "id": parent.sender.id,
                            "username": parent.sender.username,
                            "avatar_url": parent.sender.avatar_url
                        }
                    }

                # Build message output
                msg_out = {
                    "id": msg.id,
                    "temp_id": incoming_temp_id,
                    "sender": {
                        "id": msg.sender.id,
                        "username": msg.sender.username,
                        "avatar_url": msg.sender.avatar_url
                    },
                    "group_id": msg.group_id,
                    "content": msg.content,
                    "call_content": msg.call_content,
                    "created_at": to_local_iso(msg.created_at, tz_offset_hours=7),
                    "file_url": msg.file_url,
                    "voice_url": msg.voice_url,
                    "parent_message": parent_msg_data
                }

                try:
                    await manager.broadcast(chat_id, msg_out)
                except Exception as e:
                    print(f"[Broadcast Error] Group {group_id}: {e}")
                    await websocket.send_json({
                        "error": "Failed to broadcast message",
                        "temp_id": incoming_temp_id
                    })
                    continue

        except WebSocketDisconnect:
            manager.disconnect(chat_id, websocket, user_id=current_user.id)
        except Exception as e:
            traceback.print_exc()
            print(f"[WS Error] {e}")
            await websocket.close(code=1011, reason="Server error")

    except Exception as e:
        traceback.print_exc()
        print(f"[WS Error] {e}")
        await websocket.close(code=1011, reason="Server error")
    finally:
        db.close()
        
async def auto_end_call(chat_id: str, db):
    from app.services.ws_manager_group import manager
    
    await asyncio.sleep(30)

    total = manager.get_total_accepted(chat_id)

    if total < 1:
        await manager.end_group_call(chat_id, db)

    manager.call_timers.pop(chat_id, None)

    

