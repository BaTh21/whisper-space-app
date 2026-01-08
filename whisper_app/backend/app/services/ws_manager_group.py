from __future__ import annotations
from typing import Dict, Set
from fastapi import WebSocket
import asyncio
from datetime import datetime
from app.models.group_message import GroupMessage
from app.helpers.to_utc_iso import to_local_iso

class WebSocketManager:
    def __init__(self) -> None:
        self.active_connections: Dict[str, Dict[WebSocket, dict]] = {}
        self.online_users: Dict[str, Set[int]] = {}
        self.group_call_accepts: Dict[str, Set[int]] = {}
        self.group_call_sessions: Dict[str, dict] = {}
        self.call_timers: Dict[str, asyncio.Task] = {}

    async def connect(self, chat_id: str, websocket: WebSocket, user_id: int) -> None:
        self.active_connections.setdefault(chat_id, {})[websocket] = {"user_id": user_id}
        self.online_users.setdefault(chat_id, set()).add(user_id)
        
        await self.broadcast(chat_id, {
            "action": "user_online",
            "user_id": user_id
        }, exclude={websocket})
        
        await websocket.send_json({
            "action": "online_users",
            "user_ids": list(self.online_users[chat_id])
        })

    def disconnect(self, chat_id: str, websocket: WebSocket, user_id: int) -> None:
        if chat_id in self.active_connections and websocket in self.active_connections[chat_id]:
            info = self.active_connections[chat_id].pop(websocket)
            user_id = user_id or info["user_id"]
            
            if not self.active_connections[chat_id]:
                del self.active_connections[chat_id]
                
        if chat_id in self.online_users:
                self.online_users[chat_id].discard(user_id)
                if not self.online_users[chat_id]:
                    del self.online_users[chat_id]
                    
        self.remove_user_accepted(chat_id, user_id)
                    
        try:
            asyncio.create_task(self.broadcast(chat_id, {
                "action": "user_offline",
                "user_id": user_id,
                "remove_stream": True,
                "total_accepted": self.get_total_accepted(chat_id)
            }))
        except Exception as e:
            print(f"[Disconnect Broadcast Error] {e}")

    async def broadcast(self, chat_id: str, message: dict, exclude: Set[WebSocket] = None) -> None:
        if chat_id not in self.active_connections:
            return
        exclude = exclude or set()
        dead = set()
        for ws in list(self.active_connections[chat_id].keys()):
            if ws in exclude:
                continue
            try:
                await ws.send_json(message)
            except Exception:
                dead.add(ws)

        for ws in dead:
            user_id = self.active_connections[chat_id][ws]["user_id"] if ws in self.active_connections[chat_id] else None
            self.disconnect(chat_id, ws, user_id)
            
    async def send_to_user(self, chat_id: str, user_id: int, message: dict, exclude: Set[WebSocket] = None) -> None:
        if chat_id not in self.active_connections:
            return

        exclude = exclude or set()

        for ws, info in self.active_connections[chat_id].items():
            if ws in exclude:
                continue
            if info["user_id"] == user_id:
                try:
                    await ws.send_json(message)
                except:
                    self.disconnect(chat_id, ws, user_id)
            
    def get_online_users(self, chat_id: str) -> Set[int]:
        return self.online_users.get(chat_id, set())
    
    def mark_user_accepted(self, chat_id: str, user_id: int) -> None:
        if chat_id not in self.group_call_accepts:
            self.group_call_accepts[chat_id] = set()
        self.group_call_accepts[chat_id].add(user_id)

    def remove_user_accepted(self, chat_id: str, user_id: int) -> None:
        if chat_id in self.group_call_accepts:
            self.group_call_accepts[chat_id].discard(user_id)
            if not self.group_call_accepts[chat_id]:
                del self.group_call_accepts[chat_id]

    def get_total_accepted(self, chat_id: str) -> int:
        return len(self.group_call_accepts.get(chat_id, set()))
    
    async def end_group_call(self, chat_id: str, db):
        session = self.group_call_sessions.get(chat_id)
        if not session:
            return

        end_time = datetime.utcnow()
        message_id = session.get("start_message_id")
        msg = None

        if message_id:
            msg = db.query(GroupMessage).filter(GroupMessage.id == message_id).first()
            if msg:
                starter = session.get("starter_name", "Someone")
                call_type = session.get("call_type", "call")
                type_text = "video call" if call_type == "video" else "voice call"
                msg.call_content = f"{starter} ended the {type_text}"
                msg.updated_at = end_time
                db.commit()

        await self.broadcast(chat_id, {
            "action": "call_end",
            "call_message_id": message_id,
            "call_content": msg.call_content if msg else None,
            "can_join": False,
            "updated_at": to_local_iso(end_time, tz_offset_hours=7),
        })

        self.group_call_accepts.pop(chat_id, None)
        self.group_call_sessions.pop(chat_id, None)

        timer = self.call_timers.pop(chat_id, None)
        if timer:
            timer.cancel()

manager = WebSocketManager()