# websocket_server.py
import asyncio
import json
import logging
from datetime import datetime
from typing import Dict, Set
import jwt
from fastapi import WebSocket, WebSocketDisconnect, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models.private_message import PrivateMessage
from app.models.user import User



logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[int, WebSocket] = {}
        self.user_connections: Dict[int, Set[int]] = {}

    async def connect(self, websocket: WebSocket, user_id: int, friend_id: int):
        await websocket.accept()
        self.active_connections[user_id] = websocket
        
        if user_id not in self.user_connections:
            self.user_connections[user_id] = set()
        self.user_connections[user_id].add(friend_id)
        
        logger.info(f"User {user_id} connected to friend {friend_id}")

    def disconnect(self, user_id: int, friend_id: int):
        if user_id in self.active_connections:
            del self.active_connections[user_id]
        
        if user_id in self.user_connections:
            self.user_connections[user_id].discard(friend_id)
            if not self.user_connections[user_id]:
                del self.user_connections[user_id]
        
        logger.info(f"User {user_id} disconnected from friend {friend_id}")

    async def send_personal_message(self, message: dict, user_id: int):
        if user_id in self.active_connections:
            try:
                await self.active_connections[user_id].send_text(json.dumps(message))
            except Exception as e:
                logger.error(f"Error sending message to user {user_id}: {e}")

    async def broadcast_to_friend(self, message: dict, sender_id: int, receiver_id: int):
        """Send message to both sender and receiver if they're connected"""
        # Send to receiver
        if receiver_id in self.active_connections:
            await self.send_personal_message(message, receiver_id)
        
        # Send to sender (for confirmation)
        if sender_id in self.active_connections:
            await self.send_personal_message(message, sender_id)

manager = ConnectionManager()

async def authenticate_token(token: str) -> User:
    """Authenticate user from JWT token"""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
        user_id: int = payload.get("sub")
        if user_id is None:
            raise HTTPException(status_code=401, detail="Invalid token")
        
        db = next(get_db())
        user = db.query(User).filter(User.id == user_id).first()
        if user is None:
            raise HTTPException(status_code=401, detail="User not found")
        return user
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")

async def handle_websocket_private(websocket: WebSocket, friend_id: int, token: str):
    """Handle private chat WebSocket connection"""
    user = await authenticate_token(token)
    user_id = user.id
    
    await manager.connect(websocket, user_id, friend_id)
    
    try:
        while True:
            data = await websocket.receive_text()
            message_data = json.loads(data)
            
            # Handle different message types
            message_type = message_data.get("type")
            
            if message_type == "message":
                await handle_private_message(user_id, friend_id, message_data)
            elif message_type == "read":
                await handle_read_receipt(user_id, friend_id, message_data)
            elif message_type == "typing":
                await handle_typing_indicator(user_id, friend_id, message_data)
            elif message_type == "heartbeat":
                # Just ignore heartbeat, connection is alive
                continue
            else:
                logger.warning(f"Unknown message type: {message_type}")
                
    except WebSocketDisconnect:
        manager.disconnect(user_id, friend_id)
    except Exception as e:
        logger.error(f"WebSocket error for user {user_id}: {e}")
        manager.disconnect(user_id, friend_id)

async def handle_private_message(sender_id: int, receiver_id: int, message_data: dict):
    """Handle sending a private message"""
    db = next(get_db())
    
    try:
        # Create message in database
        message = PrivateMessage(
            sender_id=sender_id,
            receiver_id=receiver_id,
            content=message_data["content"],
            message_type=message_data.get("message_type", "text"),
            reply_to_id=message_data.get("reply_to_id"),
            created_at=datetime.utcnow()
        )
        
        db.add(message)
        db.commit()
        db.refresh(message)
        
        # Get sender info
        sender = db.query(User).filter(User.id == sender_id).first()
        
        # Prepare message for broadcasting
        ws_message = {
            "type": "message",
            "id": message.id,
            "sender_id": sender_id,
            "sender_username": sender.username,
            "receiver_id": receiver_id,
            "content": message.content,
            "message_type": message.message_type,
            "reply_to": get_reply_to_info(db, message.reply_to_id),
            "created_at": message.created_at.isoformat(),
            "is_read": False
        }
        
        # Broadcast to both users
        await manager.broadcast_to_friend(ws_message, sender_id, receiver_id)
        
        logger.info(f"Message {message.id} sent from {sender_id} to {receiver_id}")
        
    except Exception as e:
        db.rollback()
        logger.error(f"Error handling private message: {e}")

async def handle_read_receipt(user_id: int, friend_id: int, message_data: dict):
    """Handle read receipts"""
    db = next(get_db())
    
    try:
        message_id = message_data.get("message_id")
        
        # Update message as read in database
        message = db.query(PrivateMessage).filter(
            PrivateMessage.id == message_id,
            PrivateMessage.receiver_id == user_id
        ).first()
        
        if message:
            message.is_read = True
            message.read_at = datetime.utcnow()
            db.commit()
            
            # Send read receipt to sender
            read_receipt = {
                "type": "read_receipt",
                "message_id": message_id,
                "reader_id": user_id,
                "read_at": message.read_at.isoformat()
            }
            
            # Notify the sender
            if message.sender_id in manager.active_connections:
                await manager.send_personal_message(read_receipt, message.sender_id)
                
            logger.info(f"Message {message_id} marked as read by user {user_id}")
            
    except Exception as e:
        db.rollback()
        logger.error(f"Error handling read receipt: {e}")

async def handle_typing_indicator(user_id: int, friend_id: int, message_data: dict):
    """Handle typing indicators"""
    try:
        typing_data = {
            "type": "typing",
            "user_id": user_id,
            "is_typing": message_data.get("is_typing", False),
            "friend_id": friend_id
        }
        
        # Send typing indicator to friend
        if friend_id in manager.active_connections:
            await manager.send_personal_message(typing_data, friend_id)
            
    except Exception as e:
        logger.error(f"Error handling typing indicator: {e}")

def get_reply_to_info(db: Session, reply_to_id: int) -> dict:
    """Get reply_to message info"""
    if not reply_to_id:
        return None
    
    reply_message = db.query(PrivateMessage).filter(PrivateMessage.id == reply_to_id).first()
    if not reply_message:
        return None
    
    sender = db.query(User).filter(User.id == reply_message.sender_id).first()
    
    return {
        "id": reply_message.id,
        "content": reply_message.content,
        "sender_id": reply_message.sender_id,
        "sender_username": sender.username if sender else "Unknown",
        "message_type": reply_message.message_type
    }