import traceback
from fastapi import APIRouter, Depends, HTTPException, status, Query, WebSocket, WebSocketDisconnect, BackgroundTasks
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
from datetime import datetime
from app.core.database import get_db
from app.core.security import get_current_user, verify_token
from app.crud.diary import (
    create_diary, get_comment_by_id, get_list_favorite_diaries, get_visible, get_by_id, can_view, create_comment, 
    create_like, update_comment, delete_comment, update_diary, 
    delete_diary, create_diary_for_group, share_diary, delete_share,
    save_diary_to_favorites, remove_diary_from_favorites, 
    get_favorite_diaries, get_diary_likes_count,
    get_diary_comments, 
)
from app.models.user import User
from app.schemas.diary import (
    DiaryCreate, CommentResponse, DiaryOut, DiaryCommentCreate, 
    DiaryCommentOut, CreatorResponse, GroupResponse, DiaryLikeResponse, 
    DiaryUpdate, CreateDiaryForGroup, CommentUpdate, DiaryShare, 
    DiaryFavoriteResponse
)
from app.models.diary import Diary
from app.models.diary_like import DiaryLike
from app.models.diary_comment import DiaryComment
from app.models.diary_favorite import DiaryFavorite
from app.crud.activity import create_activity
from app.models.activity import ActivityType
from app.services.websocket_manager import manager

router = APIRouter()

async def send_websocket_notification(user_room: str, message: dict):
    """Send WebSocket notification to a specific user room"""
    try:
        await manager.broadcast_to_user(user_room, message)
    except Exception as e:
        print(f"WebSocket notification failed: {e}")

# ============ DIARY CRUD ENDPOINTS ============

@router.post("/", response_model=DiaryOut, status_code=status.HTTP_201_CREATED)
def create_diary_endpoint(
    diary_in: DiaryCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        diary = create_diary(db, current_user.id, diary_in)
        
        diary = db.query(Diary).options(
            joinedload(Diary.author),
            joinedload(Diary.groups),
            joinedload(Diary.likes).joinedload(DiaryLike.user),
            joinedload(Diary.comments).joinedload(DiaryComment.user)
        ).filter(Diary.id == diary.id).first()
        
        filtered_thumbnails = []
        if diary.video_thumbnails:
            filtered_thumbnails = [thumb for thumb in diary.video_thumbnails if thumb is not None]
        
        response = DiaryOut(
            id=diary.id,
            author=CreatorResponse(
                id=current_user.id,
                username=current_user.username,
                avatar_url=current_user.avatar_url
            ),
            title=diary.title,
            content=diary.content,
            share_type=diary.share_type.value,
            groups=[
                GroupResponse(id=g.id, name=g.name) for g in diary.groups
            ],
            images=diary.images if diary.images else [],
            videos=diary.videos if diary.videos else [],
            video_thumbnails=filtered_thumbnails,
            media_type=diary.media_type,
            likes=[
                DiaryLikeResponse(
                    id=like.id,
                    user=CreatorResponse(
                        id=like.user.id,
                        username=like.user.username,
                        avatar_url=like.user.avatar_url
                    )
                ) for like in diary.likes or []
            ] if hasattr(diary, 'likes') and diary.likes else [],
            is_deleted=diary.is_deleted,
            created_at=diary.created_at,
            updated_at=diary.updated_at,
            comments=[],
            favorited_user_ids=[]
        )
        
        # Notify via WebSocket
        background_tasks.add_task(
            send_websocket_notification,
            f"feed_{current_user.id}",
            {
                "type": "new_diary",
                "diary": response.dict(),
                "timestamp": datetime.utcnow().isoformat()
            }
        )
        
        return response
        
    except HTTPException as e:
        raise
    except Exception as e:
        print(f"Unexpected error in create_diary_endpoint: {str(e)}")
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Internal server error: {str(e)}"
        )

@router.get("/feed", response_model=List[DiaryOut])
def get_feed(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    limit: int = Query(25, ge=1, le=100),
    offset: int = Query(0, ge=0)  
):
    visible_ids = [d.id for d in get_visible(db, current_user.id)]
    diaries = (
        db.query(Diary)
        .options(
            joinedload(Diary.author),
            joinedload(Diary.groups),
            joinedload(Diary.comments).joinedload(DiaryComment.user),
            joinedload(Diary.likes).joinedload(DiaryLike.user),
            joinedload(Diary.favorited_by)
        )
        .filter(Diary.id.in_(visible_ids))
        .order_by(Diary.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    
    result = []
    for d in diaries:
        diary_out = DiaryOut(
            id=d.id,
            author=CreatorResponse(
                id=d.author.id,
                username=d.author.username,
                avatar_url=d.author.avatar_url
            ),
            title=d.title,
            content=d.content,
            share_type=d.share_type.value,
            groups=[GroupResponse(id=g.id, name=g.name) for g in d.groups or []],
            images=d.images or [],
            videos=d.videos or [],
            video_thumbnails=[thumb for thumb in (d.video_thumbnails or []) if thumb],
            media_type=d.media_type,
            likes=[
                DiaryLikeResponse(
                    id=l.id,
                    user=CreatorResponse(
                        id=l.user.id if l.user else -1,
                        username=l.user.username if l.user else "Deleted User",
                        avatar_url=l.user.avatar_url if l.user else None
                    )
                )
                for l in d.likes or []
            ],
            is_deleted=d.is_deleted,
            created_at=d.created_at,
            updated_at=d.updated_at,
            favorited_user_ids=[f.user_id for f in d.favorited_by or []],
            comments=[
                CommentResponse(
                    content=c.content,
                    created_at=c.created_at,
                    user=CreatorResponse(
                        id=c.user.id if c.user else -1,
                        username=c.user.username if c.user else "Deleted User",
                        avatar_url=c.user.avatar_url if c.user else None
                    ),
                    images=c.images or [],
                    parent_id=c.parent_id,
                    replies=[]
                )
                for c in d.comments or []
            ]
        )
        result.append(diary_out)

    return result

@router.get("/{diary_id}", response_model=DiaryOut)
def get_diary_by_id(
    diary_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    diary = db.query(Diary).options(
        joinedload(Diary.author),
        joinedload(Diary.groups),
        joinedload(Diary.likes).joinedload(DiaryLike.user),
        joinedload(Diary.comments).joinedload(DiaryComment.user),
        joinedload(Diary.favorited_by)
    ).filter(Diary.id == diary_id).first()
    
    if not diary:
        raise HTTPException(status_code=404, detail="Diary not found")
    
    if diary.is_deleted:
        if diary.user_id != current_user.id:
            raise HTTPException(status_code=404, detail="Diary not found")
    
    if diary.user_id != current_user.id:
        if not can_view(db, diary, current_user.id):
            raise HTTPException(status_code=403, detail="You don't have permission to view this diary")
    
    filtered_thumbnails = []
    if diary.video_thumbnails:
        filtered_thumbnails = [thumb for thumb in diary.video_thumbnails if thumb is not None]
    
    return DiaryOut(
        id=diary.id,
        author=CreatorResponse(
            id=diary.author.id,
            username=diary.author.username,
            avatar_url=diary.author.avatar_url
        ),
        title=diary.title,
        content=diary.content,
        share_type=diary.share_type.value,
        groups=[GroupResponse(id=g.id, name=g.name) for g in diary.groups],
        images=diary.images if diary.images else [],
        videos=diary.videos if diary.videos else [],
        video_thumbnails=filtered_thumbnails,
        likes=[
            DiaryLikeResponse(
                id=l.id,
                user=CreatorResponse(
                    id=l.user.id,
                    username=l.user.username,
                    avatar_url=l.user.avatar_url
                )
            ) for l in diary.likes
        ],
        is_deleted=diary.is_deleted,
        created_at=diary.created_at,
        updated_at=diary.updated_at,
        favorited_user_ids=[f.user_id for f in diary.favorited_by or []],
        comments=[
            CommentResponse(
                content=c.content,
                created_at=c.created_at,
                user=CreatorResponse(
                    id=c.user.id if c.user else -1,
                    username=c.user.username if c.user else "Deleted User",
                    avatar_url=c.user.avatar_url if c.user else None
                ),
                images=c.images or [],
                parent_id=c.parent_id,
                replies=[]
            ) for c in diary.comments
        ]
    )

# ============ COMMENT ENDPOINTS (FIXED - NO DUPLICATES) ============

@router.post("/{diary_id}/comments", response_model=DiaryCommentOut)
def create_diary_comment(
    diary_id: int,
    comment_in: DiaryCommentCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Create a comment on a diary
    """
    try:
        diary = db.query(Diary).filter(Diary.id == diary_id).first()
        if not diary:
            raise HTTPException(status_code=404, detail="Diary not found")
        
        if diary.is_deleted:
            raise HTTPException(status_code=404, detail="Diary not found")
        
        if diary.user_id != current_user.id:
            if not can_view(db, diary, current_user.id):
                raise HTTPException(status_code=403, detail="No permission to comment")
        
        comment = DiaryComment(
            diary_id=diary_id,
            user_id=current_user.id,
            content=comment_in.content,
            parent_id=comment_in.parent_id,
            images=comment_in.images or [],
            created_at=datetime.utcnow()
        )
        
        db.add(comment)
        db.commit()
        db.refresh(comment)
        
        comment = db.query(DiaryComment).options(
            joinedload(DiaryComment.user)
        ).filter(DiaryComment.id == comment.id).first()
        
        create_activity(
            db,
            actor_id=current_user.id,
            recipient_id=diary.user_id,
            activity_type=ActivityType.post_comment,
            post_id=diary_id,
            extra_data=f"{current_user.username} commented on your diary"
        )
        
        response = DiaryCommentOut(
            id=comment.id,
            diary_id=comment.diary_id,
            user=CreatorResponse(
                id=comment.user.id,
                username=comment.user.username,
                avatar_url=comment.user.avatar_url
            ),
            content=comment.content,
            images=comment.images or [],
            parent_id=comment.parent_id,
            created_at=comment.created_at
        )
        
        # Notify via WebSocket
        background_tasks.add_task(
            send_websocket_notification,
            f"feed_{diary.user_id}",
            {
                "type": "new_comment",
                "comment": response.dict(),
                "diary_id": diary_id,
                "user_id": current_user.id,
                "username": current_user.username,
                "timestamp": datetime.utcnow().isoformat()
            }
        )
        
        return response
        
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Failed to create comment: {str(e)}"
        )

@router.get("/{diary_id}/comments", response_model=List[DiaryCommentOut])
def get_diary_comments_endpoint(
    diary_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get all comments for a diary with nested replies
    """
    diary = db.query(Diary).filter(Diary.id == diary_id).first()
    if not diary:
        raise HTTPException(status_code=404, detail="Diary not found")
    
    if diary.user_id != current_user.id:
        if not can_view(db, diary, current_user.id):
            raise HTTPException(status_code=403, detail="No permission to view comments")
    
    comments = get_diary_comments(db, diary_id)
    
    comment_map = {}
    root_comments = []
    
    for comment in comments:
        comment_map[comment.id] = {
            'comment': comment,
            'children': []
        }
    
    for comment in comments:
        node = comment_map[comment.id]
        if comment.parent_id is None:
            root_comments.append(node)
        else:
            parent_node = comment_map.get(comment.parent_id)
            if parent_node:
                parent_node['children'].append(node)
    
    def build_nested(node):
        comment = node['comment']
        return DiaryCommentOut(
            id=comment.id,
            diary_id=comment.diary_id,
            user=CreatorResponse(
                id=comment.user.id,
                username=comment.user.username,
                avatar_url=comment.user.avatar_url
            ),
            content=comment.content,
            images=comment.images or [],
            parent_id=comment.parent_id,
            replies=[build_nested(child) for child in node['children']],
            created_at=comment.created_at
        )
    
    return [build_nested(node) for node in root_comments]

@router.put("/comments/{comment_id}", response_model=DiaryCommentOut)
def update_comment_by_id(
    comment_id: int,
    comment_data: CommentUpdate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Update a comment
    """
    try:
        # Use the new function
        comment = get_comment_by_id(db, comment_id)
        if not comment:
            raise HTTPException(status_code=404, detail="Comment not found")
        
        if comment.user_id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized to edit this comment")
        
        # Use existing update_comment function
        updated_comment = update_comment(db, comment_id, comment_data, current_user.id)
        
        # Reload with relationships
        updated_comment = get_comment_by_id(db, comment_id)
        
        response = DiaryCommentOut(
            id=updated_comment.id,
            diary_id=updated_comment.diary_id,
            user=CreatorResponse(
                id=updated_comment.user.id,
                username=updated_comment.user.username,
                avatar_url=updated_comment.user.avatar_url
            ),
            content=updated_comment.content,
            images=updated_comment.images or [],
            parent_id=updated_comment.parent_id,
            created_at=updated_comment.created_at
        )
        
        # Notify via WebSocket
        background_tasks.add_task(
            send_websocket_notification,
            f"feed_{comment.diary.user_id}",
            {
                "type": "comment_updated",
                "comment": response.dict(),
                "diary_id": comment.diary_id,
                "timestamp": datetime.utcnow().isoformat()
            }
        )
        
        return response
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to update comment: {str(e)}"
        )

@router.delete("/comments/{comment_id}", status_code=status.HTTP_200_OK)
def delete_comment_by_id(
    comment_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Delete a comment
    """
    try:
        # Use the new function
        comment = get_comment_by_id(db, comment_id)
        if not comment:
            raise HTTPException(status_code=404, detail="Comment not found")
        
        if comment.user_id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized to delete this comment")
        
        diary_id = comment.diary_id
        
        # Use existing delete_comment function
        delete_comment(db, comment_id, current_user.id)
        
        # Notify via WebSocket
        background_tasks.add_task(
            send_websocket_notification,
            f"feed_{comment.diary.user_id}",
            {
                "type": "comment_deleted",
                "comment_id": comment_id,
                "diary_id": diary_id,
                "timestamp": datetime.utcnow().isoformat()
            }
        )
        
        return {"detail": "Comment deleted successfully"}
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to delete comment: {str(e)}"
        )

# ============ LIKE ENDPOINTS ============

@router.post("/{diary_id}/like", status_code=status.HTTP_200_OK)
def like_diary_endpoint(
    diary_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Like or unlike a diary
    """
    try:
        # Get the diary
        diary = db.query(Diary).filter(Diary.id == diary_id, Diary.is_deleted == False).first()
        if not diary:
            raise HTTPException(status_code=404, detail="Diary not found")
        
        # Check if user can view (and therefore like) this diary
        if not can_view(db, diary, current_user.id):
            raise HTTPException(status_code=403, detail="No permission to like this diary")
        
        # Check if like already exists
        existing_like = db.query(DiaryLike).filter(
            DiaryLike.diary_id == diary_id,
            DiaryLike.user_id == current_user.id
        ).first()
        
        action = ""
        if existing_like:
            # Unlike: delete the existing like
            db.delete(existing_like)
            action = "removed"
        else:
            # Like: create new like
            new_like = DiaryLike(
                diary_id=diary_id,
                user_id=current_user.id,
                created_at=datetime.utcnow()
            )
            db.add(new_like)
            action = "added"
            
            # Create activity notification
            if diary.user_id != current_user.id:
                create_activity(
                    db,
                    actor_id=current_user.id,
                    recipient_id=diary.user_id,
                    activity_type=ActivityType.post_like,
                    post_id=diary_id,
                    extra_data=f"{current_user.username} liked your diary"
                )
        
        db.commit()
        
        # Get updated like count
        likes_count = db.query(DiaryLike).filter(DiaryLike.diary_id == diary_id).count()
        
        # Check if user currently likes this diary
        current_user_likes = db.query(DiaryLike).filter(
            DiaryLike.diary_id == diary_id,
            DiaryLike.user_id == current_user.id
        ).first() is not None
        
        # Send WebSocket notification
        background_tasks.add_task(
            send_websocket_notification,
            f"feed_{diary.user_id}",
            {
                "type": "like_updated",
                "diary_id": diary_id,
                "user_id": current_user.id,
                "username": current_user.username,
                "avatar_url": current_user.avatar_url,
                "action": action,
                "likes_count": likes_count,
                "current_user_likes": current_user_likes,
                "timestamp": datetime.utcnow().isoformat()
            }
        )
        
        return {
            "message": f"Like {action} successfully", 
            "liked": current_user_likes,
            "likes_count": likes_count
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in like endpoint: {str(e)}")
        traceback.print_exc()
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Failed to update like: {str(e)}"
        )


@router.get("/{diary_id}/likes", response_model=int)
def get_diary_likes_count_endpoint(
    diary_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    diary = db.query(Diary).filter(Diary.id == diary_id).first()
    
    if not diary:
        raise HTTPException(status_code=404, detail="Diary not found")
    
    if diary.user_id != current_user.id:
        if not can_view(db, diary, current_user.id):
            raise HTTPException(status_code=403, detail="No permission to view likes")
    
    likes_count = get_diary_likes_count(db, diary_id)
    return likes_count

# ============ FAVORITE ENDPOINTS ============

@router.post("/{diary_id}/favorites", response_model=DiaryFavoriteResponse, status_code=status.HTTP_201_CREATED)
def save_diary_to_favorites_endpoint(
    diary_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Save diary to favorites
    """
    try:
        # Get the diary
        diary = db.query(Diary).filter(Diary.id == diary_id, Diary.is_deleted == False).first()
        if not diary:
            raise HTTPException(status_code=404, detail="Diary not found")
        
        # Check if user can view (and therefore favorite) this diary
        if not can_view(db, diary, current_user.id):
            raise HTTPException(status_code=403, detail="No permission to favorite this diary")
        
        # Check if already favorited
        existing_favorite = db.query(DiaryFavorite).filter(
            DiaryFavorite.diary_id == diary_id,
            DiaryFavorite.user_id == current_user.id
        ).first()
        
        if existing_favorite:
            raise HTTPException(status_code=400, detail="Already in favorites")
        
        # Create new favorite
        favorite = DiaryFavorite(
            diary_id=diary_id,
            user_id=current_user.id,
            created_at=datetime.utcnow()
        )
        
        db.add(favorite)
        db.commit()
        db.refresh(favorite)
        
        # Send WebSocket notification
        background_tasks.add_task(
            send_websocket_notification,
            f"feed_{current_user.id}",
            {
                "type": "diary_favorited",
                "diary_id": diary_id,
                "favorite_id": favorite.id,
                "timestamp": datetime.utcnow().isoformat()
            }
        )
        
        return favorite
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in favorite endpoint: {str(e)}")
        traceback.print_exc()
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Failed to save to favorites: {str(e)}"
        )


@router.delete("/{diary_id}/favorites", status_code=status.HTTP_200_OK)
def remove_diary_from_favorites_endpoint(
    diary_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Remove diary from favorites
    """
    try:
        # Get the diary
        diary = db.query(Diary).filter(Diary.id == diary_id, Diary.is_deleted == False).first()
        if not diary:
            raise HTTPException(status_code=404, detail="Diary not found")
        
        # Find the favorite
        favorite = db.query(DiaryFavorite).filter(
            DiaryFavorite.diary_id == diary_id,
            DiaryFavorite.user_id == current_user.id
        ).first()
        
        if not favorite:
            raise HTTPException(status_code=404, detail="Not found in favorites")
        
        db.delete(favorite)
        db.commit()
        
        # Send WebSocket notification
        background_tasks.add_task(
            send_websocket_notification,
            f"feed_{current_user.id}",
            {
                "type": "diary_unfavorited",
                "diary_id": diary_id,
                "timestamp": datetime.utcnow().isoformat()
            }
        )
        
        return {"detail": "Removed from favorites"}
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in unfavorite endpoint: {str(e)}")
        traceback.print_exc()
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Failed to remove from favorites: {str(e)}"
        )
        
@router.get("/favorites", response_model=List[DiaryFavoriteResponse])
def get_favorite_diaries_endpoint(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get user's favorite diaries
    """
    return get_favorite_diaries(db, current_user.id)

@router.get("/favorite-list", response_model=List[DiaryOut])
def get_favorite_diaries_list_endpoint(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get list of favorited diaries with full details
    """
    try:
        diaries = get_list_favorite_diaries(db, current_user.id)  # Use correct function name
        
        result = []
        for d in diaries:
            diary_out = DiaryOut(
                id=d.id,
                author=CreatorResponse(
                    id=d.author.id,
                    username=d.author.username,
                    avatar_url=d.author.avatar_url
                ),
                title=d.title,
                content=d.content,
                share_type=d.share_type.value,
                groups=[GroupResponse(id=g.id, name=g.name) for g in d.groups or []],
                images=d.images or [],
                videos=d.videos or [],
                video_thumbnails=[thumb for thumb in (d.video_thumbnails or []) if thumb],
                media_type=d.media_type,
                likes=[
                    DiaryLikeResponse(
                        id=l.id,
                        user=CreatorResponse(
                            id=l.user.id if l.user else -1,
                            username=l.user.username if l.user else "Deleted User",
                            avatar_url=l.user.avatar_url if l.user else None
                        )
                    )
                    for l in d.likes or []
                ],
                is_deleted=d.is_deleted,
                created_at=d.created_at,
                updated_at=d.updated_at,
                favorited_user_ids=[f.user_id for f in d.favorited_by or []],
                comments=[
                    CommentResponse(
                        content=c.content,
                        created_at=c.created_at,
                        user=CreatorResponse(
                            id=c.user.id if c.user else -1,
                            username=c.user.username if c.user else "Deleted User",
                            avatar_url=c.user.avatar_url if c.user else None
                        ),
                        images=c.images or [],
                        parent_id=c.parent_id,
                        replies=[]
                    )
                    for c in d.comments or []
                ]
            )
            result.append(diary_out)

        return result
        
    except Exception as e:
        print(f"Error getting favorite diaries: {str(e)}")
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail=f"Failed to get favorite diaries: {str(e)}"
        )

# ============ DIARY UPDATE & DELETE ============

@router.patch("/{diary_id}", response_model=DiaryOut)
def update_diary_by_id(
    diary_id: int,
    diary_data: DiaryUpdate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        diary = update_diary(db, diary_id, diary_data, current_user.id)

        diary = db.query(Diary).options(
            joinedload(Diary.author),
            joinedload(Diary.groups),
            joinedload(Diary.likes).joinedload(DiaryLike.user),
            joinedload(Diary.comments).joinedload(DiaryComment.user),
            joinedload(Diary.favorited_by)
        ).filter(Diary.id == diary.id).first()
        
        filtered_thumbnails = []
        if diary.video_thumbnails:
            filtered_thumbnails = [thumb for thumb in diary.video_thumbnails if thumb is not None]
        
        response = DiaryOut(
            id=diary.id,
            author=CreatorResponse(
                id=diary.author.id,
                username=diary.author.username,
                avatar_url=diary.author.avatar_url
            ),
            title=diary.title,
            content=diary.content,
            share_type=diary.share_type.value,
            groups=[GroupResponse(id=g.id, name=g.name) for g in diary.groups],
            images=diary.images if diary.images else [],
            videos=diary.videos if diary.videos else [],
            video_thumbnails=filtered_thumbnails,
            likes=[
                DiaryLikeResponse(
                    id=l.id,
                    user=CreatorResponse(
                        id=l.user.id,
                        username=l.user.username,
                        avatar_url=l.user.avatar_url
                    )
                ) for l in diary.likes
            ],
            is_deleted=diary.is_deleted,
            created_at=diary.created_at,
            updated_at=diary.updated_at,
            favorited_user_ids=[f.user_id for f in diary.favorited_by or []],
            comments=[
                CommentResponse(
                    content=c.content,
                    created_at=c.created_at,
                    user=CreatorResponse(
                        id=c.user.id if c.user else -1,
                        username=c.user.username if c.user else "Deleted User",
                        avatar_url=c.user.avatar_url if c.user else None
                    ),
                    images=c.images or [],
                    parent_id=c.parent_id,
                    replies=[]
                ) for c in diary.comments
            ]
        )
        
        # Notify via WebSocket
        background_tasks.add_task(
            send_websocket_notification,
            f"feed_{current_user.id}",
            {
                "type": "diary_updated",
                "diary": response.dict(),
                "timestamp": datetime.utcnow().isoformat()
            }
        )
        
        return response
    except HTTPException:
        raise
    except Exception as e:
        print(f"Update diary error: {str(e)}")
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(e)
        )

@router.delete("/{diary_id}", status_code=status.HTTP_200_OK)
def delete_diary_by_id(
    diary_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        diary = get_by_id(db, diary_id)
        if not diary:
            raise HTTPException(status_code=404, detail="Diary not found")
        
        result = delete_diary(db, diary_id, current_user.id)
        
        # Notify via WebSocket
        background_tasks.add_task(
            send_websocket_notification,
            f"feed_{current_user.id}",
            {
                "type": "diary_deleted",
                "diary_id": diary_id,
                "timestamp": datetime.utcnow().isoformat()
            }
        )
        
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Internal server error: {str(e)}"
        )

# ============ WEB SOCKET ENDPOINT ============

@router.websocket("/ws/feed")
async def websocket_feed(websocket: WebSocket):
    """
    WebSocket endpoint for real-time feed updates
    """
    await manager.connect_to_feed(websocket)