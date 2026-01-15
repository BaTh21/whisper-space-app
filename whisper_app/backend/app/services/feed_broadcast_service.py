# app/services/feed_broadcast_service.py
import asyncio
from typing import List, Set
from sqlalchemy.orm import Session
from datetime import datetime

from app.services.websocket_manager import manager
from app.crud.friend import get_friend_ids
from app.crud.group import get_group_members
from app.core.database import SessionLocal
from app.models.user import User
from app.models.diary import Diary


class FeedBroadcastService:
    
    @staticmethod
    async def broadcast_new_diary(diary_data: dict, author_id: int, share_type: str, group_ids: List[int] = None):
        """
        Broadcast new diary to appropriate users based on share type
        """
        db = SessionLocal()
        try:
            # Get users who should see this diary
            target_user_ids = await FeedBroadcastService._get_target_users(
                db, author_id, share_type, group_ids
            )
            
            # Broadcast to each user's feed room
            for user_id in target_user_ids:
                user_room = f"feed_{user_id}"
                await manager.broadcast_to_user(user_room, {
                    "type": "new_diary",
                    "data": diary_data,
                    "timestamp": datetime.utcnow().isoformat()
                })
            
            print(f"✅ Broadcast new diary {diary_data['id']} to {len(target_user_ids)} users")
            
        except Exception as e:
            print(f"❌ Error broadcasting diary: {e}")
        finally:
            db.close()
    
    @staticmethod
    async def _get_target_users(db: Session, author_id: int, share_type: str, group_ids: List[int] = None) -> Set[int]:
        """
        Get list of user IDs who should receive the diary
        """
        target_users = set()
        target_users.add(author_id)  # Always include author
        
        if share_type == "public":
            # Get all users (you might want to limit this in production)
            all_users = db.query(User.id).all()
            target_users.update([user.id for user in all_users])
            
        elif share_type == "friends":
            # Get friends
            friend_ids = get_friend_ids(db, author_id)
            target_users.update(friend_ids)
            
        elif share_type == "group" and group_ids:
            # Get group members
            for group_id in group_ids:
                member_ids = get_group_members(db, group_id)
                target_users.update([member.id for member in member_ids])
        
        return target_users
    
    @staticmethod
    async def broadcast_diary_like(diary_id: int, user_id: int):
        """
        Broadcast like to relevant users
        """
        db = SessionLocal()
        try:
            # Get diary author
            diary = db.query(Diary).filter(Diary.id == diary_id).first()
            if not diary:
                return
            
            # Get user who liked
            user = db.query(User).filter(User.id == user_id).first()
            if not user:
                return
            
            # Notify diary author
            author_room = f"feed_{diary.author_id}"
            await manager.broadcast_to_user(author_room, {
                "type": "diary_liked",
                "diary_id": diary_id,
                "user_id": user_id,
                "user_username": user.username,
                "timestamp": datetime.utcnow().isoformat()
            })
            
            # Also broadcast to users who have this diary in their feed
            # (simplified - in production you'd track who can see the diary)
            
        except Exception as e:
            print(f"❌ Error broadcasting like: {e}")
        finally:
            db.close()
    
    @staticmethod
    async def broadcast_diary_comment(diary_id: int, comment_data: dict):
        """
        Broadcast new comment
        """
        db = SessionLocal()
        try:
            # Get diary author
            diary = db.query(Diary).filter(Diary.id == diary_id).first()
            if not diary:
                return
            
            # Notify diary author
            author_room = f"feed_{diary.author_id}"
            await manager.broadcast_to_user(author_room, {
                "type": "diary_commented",
                "diary_id": diary_id,
                "comment": comment_data,
                "timestamp": datetime.utcnow().isoformat()
            })
            
            # Notify other commenters on this diary
            # (You'd need to track who has commented)
            
        except Exception as e:
            print(f"❌ Error broadcasting comment: {e}")
        finally:
            db.close()
    
    @staticmethod
    async def broadcast_diary_deleted(diary_id: int, author_id: int):
        """
        Broadcast diary deletion
        """
        try:
            # Get all users who might have this diary in their feed
            # This is simplified - in production you'd track who can see it
            
            # Broadcast to author
            author_room = f"feed_{author_id}"
            await manager.broadcast_to_user(author_room, {
                "type": "diary_deleted",
                "diary_id": diary_id,
                "timestamp": datetime.utcnow().isoformat()
            })
            
            # You might want to broadcast to others who can see it
            
        except Exception as e:
            print(f"❌ Error broadcasting deletion: {e}")

feed_broadcast = FeedBroadcastService()