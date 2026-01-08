from __future__ import annotations
from typing import Dict, List, Set, Optional
from fastapi import WebSocket
from datetime import datetime, timezone
import asyncio

from typing import Dict, Set, Optional
from datetime import datetime, timezone
import asyncio
from fastapi import WebSocket

class WebSocketManager:
    def __init__(self) -> None:
        self.active_connections: Dict[str, Dict[WebSocket, dict]] = {}
        self.online_users: Dict[str, Set[int]] = {}
        self.user_chats: Dict[int, Set[str]] = {}
        self.last_activity: Dict[int, datetime] = {}
        self.active_calls: Dict[str, dict] = {}

    async def _update_user_online_status_db(self, user_id: int, is_online: bool):
        try:
            from app.core.database import SessionLocal
            from app.crud.chat import update_user_online_status
            
            db = SessionLocal()
            try:
                update_user_online_status(db, user_id, is_online)
            finally:
                db.close()
        except ImportError:
            pass
        except Exception as e:
            print(f"Error updating user online status in DB: {e}")

    async def connect(self, chat_id: str, websocket: WebSocket, user_id: int) -> None:
        if chat_id not in self.active_connections:
            self.active_connections[chat_id] = {}
        self.active_connections[chat_id][websocket] = {
            "user_id": user_id,
            "connected_at": datetime.now(timezone.utc)
        }
        if chat_id not in self.online_users:
            self.online_users[chat_id] = set()
        self.online_users[chat_id].add(user_id)
        if user_id not in self.user_chats:
            self.user_chats[user_id] = set()
        self.user_chats[user_id].add(chat_id)
        self.last_activity[user_id] = datetime.now(timezone.utc)
        await self._update_user_online_status_db(user_id, True)
        await self.broadcast(chat_id, {
            "type": "user_online",
            "user_id": user_id,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }, exclude={websocket})
        await websocket.send_json({
            "type": "online_users",
            "user_ids": list(self.online_users[chat_id]),
            "timestamp": datetime.now(timezone.utc).isoformat()
        })

    def disconnect(self, chat_id: str, websocket: WebSocket, user_id: Optional[int] = None) -> None:
        if chat_id in self.active_connections and websocket in self.active_connections[chat_id]:
            if user_id is None:
                user_info = self.active_connections[chat_id][websocket]
                user_id = user_info["user_id"]
            del self.active_connections[chat_id][websocket]
            if not self.active_connections[chat_id]:
                del self.active_connections[chat_id]
            if chat_id in self.online_users:
                self.online_users[chat_id].discard(user_id)
                if not self.online_users[chat_id]:
                    del self.online_users[chat_id]
            if user_id in self.user_chats:
                self.user_chats[user_id].discard(chat_id)
                if not self.user_chats[user_id]:
                    asyncio.create_task(self._handle_user_offline(user_id))

    async def _handle_user_offline(self, user_id: int):
        await asyncio.sleep(3)
        if user_id in self.user_chats and self.user_chats[user_id]:
            return
        await self._update_user_online_status_db(user_id, False)
        await self._broadcast_user_offline(user_id)
        self.last_activity.pop(user_id, None)
        self.user_chats.pop(user_id, None)

    async def _broadcast_user_offline(self, user_id: int):
        offline_time = datetime.now(timezone.utc)
        chats_to_notify = {chat_id for chat_id, users in self.online_users.items() if user_id in users}
        for chat_id in chats_to_notify:
            await self.broadcast(chat_id, {
                "type": "user_offline",
                "user_id": user_id,
                "timestamp": offline_time.isoformat(),
                "last_seen": offline_time.isoformat()
            })

    async def broadcast(self, chat_id: str, message: dict, exclude: Set[WebSocket] = None) -> None:

        if chat_id not in self.active_connections:
            return

        exclude = exclude or set()
        dead_connections = set()

        for websocket in list(self.active_connections[chat_id].keys()):
            if websocket in exclude:
                continue
            try:
                await websocket.send_json(message)
            except Exception:
                dead_connections.add(websocket)

        for websocket in dead_connections:
            self.disconnect(chat_id, websocket)

    async def send_to_user(self, chat_id: str, user_id: int, message: dict) -> bool:
        if chat_id not in self.active_connections:
            print(f"[WS] chat_id {chat_id} not found")
            return False

        sent = False
        for websocket, info in self.active_connections[chat_id].items():
            print(f"[WS] checking user {info['user_id']}")
            if info["user_id"] == user_id:
                await websocket.send_json(message)
                sent = True

        if not sent:
            print(f"[WS] user {user_id} not connected to chat {chat_id}")

        return sent

    def get_online_users(self, chat_id: str) -> Set[int]:
        return self.online_users.get(chat_id, set())

    def is_user_online(self, user_id: int) -> bool:
        return user_id in self.user_chats and bool(self.user_chats[user_id])

    def get_user_chats(self, user_id: int) -> Set[str]:
        return self.user_chats.get(user_id, set())

    async def update_user_activity(self, user_id: int):
        self.last_activity[user_id] = datetime.now(timezone.utc)
        try:
            from app.core.database import SessionLocal
            from app.models.user import User
            db = SessionLocal()
            try:
                user = db.query(User).filter(User.id == user_id).first()
                if user:
                    user.last_activity = datetime.now(timezone.utc)
                    db.commit()
            except:
                db.rollback()
            finally:
                db.close()
        except:
            pass

    def get_user_last_activity(self, user_id: int) -> Optional[datetime]:
        return self.last_activity.get(user_id)

    async def force_user_offline(self, user_id: int):
        user_chats = self.get_user_chats(user_id).copy()
        for chat_id in user_chats:
            sockets_to_disconnect = [ws for ws, info in self.active_connections.get(chat_id, {}).items() if info["user_id"] == user_id]
            for websocket in sockets_to_disconnect:
                self.disconnect(chat_id, websocket, user_id)
        await self._update_user_online_status_db(user_id, False)
        await self._broadcast_user_offline(user_id)

    async def get_user_online_status_from_db(self, user_id: int) -> Optional[dict]:
        try:
            from app.core.database import SessionLocal
            from app.crud.chat import get_user_online_status
            db = SessionLocal()
            try:
                return get_user_online_status(db, user_id)
            finally:
                db.close()
        except:
            return None

    def get_connection_stats(self) -> dict:
        total_connections = sum(len(connections) for connections in self.active_connections.values())
        total_online_users = len(self.user_chats)
        total_active_chats = len(self.active_connections)
        return {
            "total_connections": total_connections,
            "total_online_users": total_online_users,
            "total_active_chats": total_active_chats,
            "online_users_per_chat": {chat_id: len(users) for chat_id, users in self.online_users.items()}
        }

    async def health_check(self) -> dict:
        stats = self.get_connection_stats()
        db_healthy = False
        try:
            from app.core.database import SessionLocal
            db = SessionLocal()
            db.execute("SELECT 1")
            db.close()
            db_healthy = True
        except:
            db_healthy = False
        return {
            "websocket_manager": "healthy",
            "database_connection": "healthy" if db_healthy else "unhealthy",
            "stats": stats,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

    async def broadcast_to_user(self, user_room: str, data: dict):
        if user_room in self.active_connections:
            for websocket in self.active_connections[user_room].keys():
                try:
                    await websocket.send_json(data)
                except:
                    pass

    async def _end_call(self, chat_id: str, reason: str, ended_by: Optional[int] = None):
        call = self.active_calls.get(chat_id)
        if not call:
            return
        timeout_task = call.get("timeout_task")
        if timeout_task and not timeout_task.done():
            timeout_task.cancel()
        await self.broadcast(chat_id, {
            "type": "call_ended",
            "reason": reason,
            "ended_by": ended_by
        })
        del self.active_calls[chat_id]

    async def _auto_cancel_call(self, chat_id: str):
        await asyncio.sleep(30)
        call = self.active_calls.get(chat_id)
        if call and call["status"] == "ringing":
            await self._end_call(chat_id, "timeout")

manager = WebSocketManager()
