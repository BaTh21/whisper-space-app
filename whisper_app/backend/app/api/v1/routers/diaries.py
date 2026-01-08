import traceback
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session, joinedload
from typing import List
from datetime import datetime
from app.core.database import get_db
from app.core.security import get_current_user
from app.crud.diary import create_diary, get_visible, get_by_id, can_view, create_comment, create_like, get_diary_comments, get_diary_likes_count, update_diary, delete_diary, create_diary_for_group, delete_comment, update_comment, share_diary, delete_share, save_diary_to_favorites, remove_diary_from_favorites, get_favorite_diaries,get_list_favorite_diarie
from app.models.user import User
from app.schemas.diary import DiaryCreate, CommentResponse, DiaryOut, DiaryCommentCreate, DiaryCommentOut, CreatorResponse, GroupResponse, DiaryLikeResponse, DiaryUpdate, CreateDiaryForGroup, CommentUpdate, DiaryShare, DiaryFavoriteResponse
from app.models.diary import Diary
from app.models.friend import Friend, FriendshipStatus
from app.models.diary_like import DiaryLike
from app.models.group_member import GroupMember
from app.models.diary_comment import DiaryComment
from app.models.diary_favorite import DiaryFavorite

router = APIRouter()

@router.post("/", response_model=DiaryOut, status_code=status.HTTP_201_CREATED)
def create_diary_endpoint(
    diary_in: DiaryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        
        # Create the diary
        diary = create_diary(db, current_user.id, diary_in)
        
        # Refresh the diary with all relationships
        diary = db.query(Diary).options(
            joinedload(Diary.author),
            joinedload(Diary.groups),
            joinedload(Diary.likes).joinedload(DiaryLike.user)
        ).filter(Diary.id == diary.id).first()
        
        # Ensure arrays are never None
        images = diary.images if diary.images else []
        videos = diary.videos if diary.videos else []
        video_thumbnails = diary.video_thumbnails if diary.video_thumbnails else []
        
        # Filter None values from video_thumbnails
        filtered_thumbnails = []
        if video_thumbnails:
            filtered_thumbnails = [thumb for thumb in video_thumbnails if thumb is not None]
        
        # Create the response
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
            images=images,
            videos=videos,  # Make sure this is included
            video_thumbnails=filtered_thumbnails,  # Make sure this is included
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
            updated_at=diary.updated_at
        )
        
        return response
        
    except HTTPException as e:
        print(f"HTTP Exception: {e.detail}")
        raise
    except Exception as e:
        print(f"Unexpected error in create_diary_endpoint: {str(e)}")
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Internal server error: {str(e)}"
        )
@router.post("/groups/{group_id}", response_model=DiaryOut)
def create_diary_for_group_(group_id: int,
                            diary_data: CreateDiaryForGroup,
                            db: Session = Depends(get_db),
                            current_user: User = Depends(get_current_user)
                            ):
    return create_diary_for_group(db, group_id, diary_data, current_user.id)

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

@router.get("/my-feed", response_model=List[DiaryOut])
def get_my_diaries(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    limit: int = Query(25, ge=1, le=100),
    offset: int = Query(0, ge=0)  
):
    diaries = (
        db.query(Diary)
        .options(
            joinedload(Diary.author),
            joinedload(Diary.groups),
            joinedload(Diary.likes).joinedload(DiaryLike.user),
            joinedload(Diary.comments).joinedload(DiaryComment.user),
            joinedload(Diary.favorited_by)
        )
        .filter(Diary.user_id == current_user.id)
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

@router.get("/favorites", response_model=List[DiaryFavoriteResponse])
def get_favorite_dairy(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return get_favorite_diaries(db, current_user.id)

@router.get("/favorite-list", response_model=List[DiaryOut])
def get_favorite_dairy(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return get_list_favorite_diarie(db, current_user.id)

@router.get("/{diary_id}", response_model=DiaryOut)
def get_diary_by_id(
    diary_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    diary = db.query(Diary).options(
        joinedload(Diary.author),
        joinedload(Diary.groups),
        joinedload(Diary.likes).joinedload(DiaryLike.user)
    ).filter(Diary.id == diary_id).first()
    
    if not diary:
        raise HTTPException(status_code=404, detail="Diary not found")
    
    if diary.is_deleted:
        if diary.user_id != current_user.id:
            raise HTTPException(status_code=404, detail="Diary not found")
    
    if diary.user_id == current_user.id:
        pass
    elif not can_view(db, diary, current_user.id):
        raise HTTPException(status_code=403, detail="You don't have permission to view this diary")
    
    # Filter out None values from video_thumbnails
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
        videos=diary.videos if diary.videos else [],  # Make sure this is included
        video_thumbnails=filtered_thumbnails,  # Make sure this is included
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
        updated_at=diary.updated_at
    )

@router.patch("/{diary_id}", response_model=DiaryOut)
def update_diary_by_id(
    diary_id: int,
    diary_data: DiaryUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Update diary endpoint with debugging"""
    try:
        # Check what fields are actually being updated
        update_dict = diary_data.dict(exclude_unset=True)
        
        diary = update_diary(db, diary_id, diary_data, current_user.id)

        # Refresh with relationships
        diary = db.query(Diary).options(
            joinedload(Diary.author),
            joinedload(Diary.groups),
            joinedload(Diary.likes).joinedload(DiaryLike.user)
        ).filter(Diary.id == diary.id).first()
        
        # Filter out None values from video_thumbnails
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
            updated_at=diary.updated_at
        )
    except HTTPException:
        raise
    except Exception as e:
        print(f"Update diary error: {str(e)}")
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(e)
        )

@router.delete("/{diary_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_diary_by_id(diary_id: int,
                       db: Session = Depends(get_db),
                       current_user: User = Depends(get_current_user)):
    delete_diary(db, diary_id, current_user.id)
    return None

@router.post("/{diary_id}/comment", response_model=DiaryCommentOut)
def comment_on_diary(
    diary_id: int,
    comment_in: DiaryCommentCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    diary = db.query(Diary).filter(Diary.id == diary_id).first()
    
    if not diary:
        raise HTTPException(status_code=404, detail="Diary not found")
    
    if diary.user_id == current_user.id:
        pass
    elif not can_view(db, diary, current_user.id):
        raise HTTPException(status_code=404, detail="Diary not found or not visible")
    
    comment = create_comment(db, diary_id, current_user, comment_in.content, 
                           comment_in.parent_id, comment_in.images)
    
    user_response = CreatorResponse(
        id=current_user.id,
        username=current_user.username,
        avatar_url=current_user.avatar_url
    )
    
    return DiaryCommentOut(
        id=comment.id,
        diary_id=comment.diary_id,
        user=user_response,
        content=comment.content,
        images=comment.images,
        parent_id=comment.parent_id,
        created_at=comment.created_at if comment.created_at else datetime.utcnow()
    )

@router.get("/{diary_id}/comments", response_model=List[DiaryCommentOut])
def get_diary_comments_endpoint(
    diary_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # First, check if diary exists
    diary = db.query(Diary).filter(Diary.id == diary_id).first()
    
    # if not diary:
    #     raise HTTPException(404, "Diary not found")
    
    # Allow creator to always view comments (even if share_type is "friends")
    # if diary.user_id == current_user.id:
    #     pass
    # elif not can_view(db, diary, current_user.id):
    #     raise HTTPException(404, "Diary not found or not visible")
    
    comments = (
        db.query(DiaryComment)
        .options(joinedload(DiaryComment.user))
        .filter(DiaryComment.diary_id == diary_id)
        .order_by(DiaryComment.created_at.asc())
        .all()
    )
    
    # Get total count (including replies)
    total_count = db.query(DiaryComment).filter(DiaryComment.diary_id == diary_id).count()
    
    # Build nested comment tree
    comment_tree = build_comment_tree(comments)
    return comment_tree
    
    # Helper function to build nested comments
def build_comment_tree(comments_list):
    """Build nested comment tree with unlimited depth"""
    # Create lookup dictionary
    comment_map = {}
    root_comments = []
    
    # First pass: create nodes for all comments
    for comment in comments_list:
        comment_map[comment.id] = {
            'id': comment.id,
            'comment': comment,
            'children': []
        }
    
    # Second pass: build tree
    for comment in comments_list:
        node = comment_map[comment.id]
        if comment.parent_id is None:
            root_comments.append(node)
        else:
            # Find parent and add this as child
            parent_node = comment_map.get(comment.parent_id)
            if parent_node:
                parent_node['children'].append(node)
            else:
                # Orphan comment (parent not found or not loaded)
                root_comments.append(node)
    
    # Convert to nested structure
    def build_nested(node):
        comment = node['comment']
        user_response = CreatorResponse(
            id=comment.user.id,
            username=comment.user.username,
            avatar_url=comment.user.avatar_url
        ) if comment.user else CreatorResponse(
            id=0,
            username="Unknown",
            avatar_url=None
        )
        
        # Recursively build children
        children = [build_nested(child) for child in node['children']]
        
        return DiaryCommentOut(
            id=comment.id,
            diary_id=comment.diary_id,
            user=user_response,
            content=comment.content,
            images=comment.images if comment.images else None,
            parent_id=comment.parent_id,
            replies=children if children else None,
            created_at=comment.created_at if comment.created_at else datetime.utcnow()
        )
    
    return [build_nested(node) for node in root_comments]

@router.put("/comments/{comment_id}", response_model=DiaryCommentOut)
def update_comment_by_id(comment_id: int,
                         comment_data: CommentUpdate,
                         db: Session = Depends(get_db),
                         current_user: User = Depends(get_current_user)
                         ):
    comment = update_comment(db, comment_id, comment_data, current_user.id)
    
    user_response = CreatorResponse(
        id=comment.user.id,
        username=comment.user.username,
        avatar_url=comment.user.avatar_url
    ) if comment.user else CreatorResponse(
        id=0,
        username="Unknown",
        avatar_url=None
    )
    
    return DiaryCommentOut(
        id=comment.id,
        diary_id=comment.diary_id,
        user=user_response,
        content=comment.content,
        images=comment.images if comment.images else None,
        parent_id=comment.parent_id,
        created_at=comment.created_at if comment.created_at else datetime.utcnow()
    )

@router.delete("/comments/{comment_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_comment_by_id(comment_id: int,
                         db: Session = Depends(get_db),
                         current_user: User = Depends(get_current_user)
                         ):
    delete_comment(db, comment_id, current_user.id)
    return None

@router.post("/{diary_id}/like")
def like_diary_endpoint(
    diary_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    diary = get_by_id(db, diary_id)
    if not diary or not can_view(db, diary, current_user.id):
        raise HTTPException(404, "Diary not found or not visible")

    create_like(db, diary_id, current_user)
    return {"message": "Like toggled successfully"}

@router.get("/{diary_id}/likes", response_model=int)
def get_diary_likes_count_endpoint(
    diary_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    diary = db.query(Diary).filter(Diary.id == diary_id).first()
    
    if not diary:
        raise HTTPException(404, "Diary not found")
    
    if diary.user_id == current_user.id:
        pass
    elif not can_view(db, diary, current_user.id):
        raise HTTPException(404, "Diary not found or not visible")
    
    likes_count = get_diary_likes_count(db, diary_id)
    return likes_count

@router.get("/my-feed/count")
def get_my_diaries_count(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    total = (
        db.query(Diary)
        .filter(Diary.user_id == current_user.id)
        .count()
    )

    public_count = (
        db.query(Diary)
        .filter(
            Diary.user_id == current_user.id,
            Diary.share_type == 'public'
        )
        .count()
    )

    return {
        "total": total,
        "public": public_count
    }
    
@router.post("/{diary_id}/favorites", response_model=DiaryFavoriteResponse, status_code=status.HTTP_201_CREATED)
def save_diary_by_id(diary_id: int, 
                     current_user: User = Depends(get_current_user),
                     db: Session = Depends(get_db)
                     ):
    return save_diary_to_favorites(db, current_user.id, diary_id)

@router.delete("/{diary_id}/favorites", status_code=status.HTTP_204_NO_CONTENT)
def remove_saved_diary_by_id(diary_id: int,
                             current_user: User = Depends(get_current_user),
                            db: Session = Depends(get_db)
                             ):
    return remove_diary_from_favorites(db, current_user.id, diary_id)