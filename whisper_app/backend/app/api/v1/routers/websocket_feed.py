# app/api/endpoints/websocket_feed.py
import asyncio
import json
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import verify_token
from app.models.user import User
from app.services.websocket_manager import manager

router = APIRouter()

@router.websocket("/ws/feed")
async def websocket_feed(websocket: WebSocket, db: Session = Depends(get_db)):
    """
    WebSocket endpoint for real-time feed updates
    """
    current_user = None
    
    try:
        # Accept connection first
        await websocket.accept()
        print("🔌 Feed WebSocket connection accepted")
        
        # 1. Get token from query params or headers
        token = None
        query_params = dict(websocket.query_params)
        if "token" in query_params:
            token = query_params["token"]
            print(f"🔑 Token from query params: {token[:20]}...")
        
        if not token:
            token_header = websocket.headers.get("Authorization")
            if token_header and token_header.startswith("Bearer "):
                token = token_header.split(" ")[1]
                print(f"🔑 Token from headers: {token[:20]}...")
        
        # 2. If no token, wait for auth message
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
        
        # 3. Verify token
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
        
        # 4. Get user from token
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
        
        # 5. Load user from DB
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
        
        # 6. Send auth success
        await websocket.send_json({
            "type": "auth_success",
            "message": "Connected to feed updates",
            "user_id": current_user.id,
            "username": current_user.username,
            "timestamp": asyncio.get_event_loop().time()
        })
        
        # 7. Join user's feed room
        user_room = f"feed_{current_user.id}"
        await manager.connect(user_room, websocket, user_id=current_user.id)
        
        print(f"📰 User {current_user.id} connected to feed updates")
        
        # 8. Send initial connection info
        await websocket.send_json({
            "type": "connection_info",
            "status": "connected",
            "user_room": user_room,
            "timestamp": asyncio.get_event_loop().time()
        })
        
        # 9. Keep connection alive
        while True:
            try:
                # Wait for messages with timeout
                data = await asyncio.wait_for(
                    websocket.receive_json(),
                    timeout=30.0  # 30 second timeout
                )
                
                message_type = data.get("type")
                
                if message_type == "ping":
                    # Respond to ping
                    await websocket.send_json({
                        "type": "pong",
                        "timestamp": asyncio.get_event_loop().time()
                    })
                    
                elif message_type == "heartbeat":
                    # Update user activity
                    await manager.update_user_activity(current_user.id)
                    await websocket.send_json({
                        "type": "pong",
                        "timestamp": asyncio.get_event_loop().time()
                    })
                    
                elif message_type == "subscribe":
                    # Subscribe to specific feed types
                    feed_types = data.get("feed_types", ["global", "friends"])
                    await websocket.send_json({
                        "type": "subscription_confirmed",
                        "feed_types": feed_types,
                        "timestamp": asyncio.get_event_loop().time()
                    })
                    
                elif message_type == "unsubscribe":
                    # Unsubscribe from feed types
                    await websocket.send_json({
                        "type": "unsubscribed",
                        "timestamp": asyncio.get_event_loop().time()
                    })
                    
                else:
                    # Unknown message type
                    await websocket.send_json({
                        "type": "error",
                        "error": f"Unknown message type: {message_type}",
                        "timestamp": asyncio.get_event_loop().time()
                    })
                    
            except asyncio.TimeoutError:
                # Send ping to check if client is still alive
                try:
                    await websocket.send_json({
                        "type": "ping",
                        "timestamp": asyncio.get_event_loop().time()
                    })
                except:
                    break  # Client disconnected
                    
            except WebSocketDisconnect:
                print(f"📰 User {current_user.id} disconnected from feed")
                break
                
            except Exception as e:
                print(f"📰 Error in feed WebSocket: {e}")
                try:
                    await websocket.send_json({
                        "type": "error",
                        "error": "Internal server error",
                        "timestamp": asyncio.get_event_loop().time()
                    })
                except:
                    break  # Client disconnected
                    
    except WebSocketDisconnect:
        print(f"📰 Feed WebSocket disconnected normally")
        
    except Exception as e:
        print(f"❌ Feed WebSocket error: {e}")
        import traceback
        traceback.print_exc()
        
    finally:
        # Clean up connection
        if current_user:
            user_room = f"feed_{current_user.id}"
            await manager.disconnect(user_room, websocket)
            print(f"📰 User {current_user.id} disconnected from feed")