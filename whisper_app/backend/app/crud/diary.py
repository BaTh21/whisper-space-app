import traceback
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload
from app.models.diary import Diary, ShareType
from app.models.diary_favorite import DiaryFavorite
from app.models.user import User
from app.models.activity import ActivityType
from app.models.diary_comment import DiaryComment
from app.models.diary_like import DiaryLike
from app.models.diary_group import DiaryGroup
from app.schemas.diary import DiaryCreate, DiaryUpdate, CreateDiaryForGroup, CommentUpdate, DiaryShare
from typing import List, Optional
from app.models.friend import Friend, FriendshipStatus
from app.models.group_member import GroupMember
from sqlalchemy import or_, and_, select
from fastapi import HTTPException, status
from datetime import datetime, timezone
from app.models.group import Group
from app.services.image_service_sync import image_service_sync
from app.crud.activity import create_activity

def create_diary(db: Session, user_id: int, diary_in: DiaryCreate) -> Diary:
    
    # Handle "private" -> "personal" conversion BEFORE creating ShareType
    share_type_value = diary_in.share_type.lower()
    if share_type_value == "private":
        share_type_value = "personal"
        print(f"Converting 'private' to 'personal' for ShareType enum")
    
    # Handle images
    image_urls = []
    if diary_in.images:
        print(f"📷 Uploading {len(diary_in.images)} images")
        try:
            image_urls = image_service_sync.save_multiple_images(diary_in.images, is_diary=True)
            print(f"✅ {len(image_urls)} images uploaded successfully")
        except Exception as e:
            print(f"❌ Image upload failed: {str(e)}")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Failed to upload images: {str(e)}"
            )
    
    # Handle videos - PROCESS INDIVIDUALLY FOR THUMBNAIL GUARANTEE
    video_urls = []
    video_thumbnails = []
    if diary_in.videos:
        
        try:
            # Process each video individually
            for idx, video_data in enumerate(diary_in.videos):
                print(f"  Processing video {idx+1}/{len(diary_in.videos)}")
                
                try:
                    # This method GUARANTEES a thumbnail for videos
                    video_url, video_thumbnail = image_service_sync.save_single_media(video_data, is_diary=True)
                    
                    if video_url:
                        video_urls.append(video_url)
                        video_thumbnails.append(video_thumbnail)  # Could be None, but array position preserved
                        print(f"  ✅ Video {idx+1} - URL: {video_url[:50]}...")
                        print(f"  📸 Thumbnail: {'PRESENT' if video_thumbnail else 'NONE'}")
                    else:
                        print(f"  ⚠️ Video {idx+1} returned no URL")
                        
                except Exception as video_error:
                    print(f"  ❌ Video {idx+1} error: {str(video_error)}")
                    # Don't fail entire diary if one video fails
                    continue
            
            # CRITICAL: Ensure arrays are the same length
            if len(video_thumbnails) != len(video_urls):
                print(f"⚠️ Array mismatch: videos={len(video_urls)}, thumbnails={len(video_thumbnails)}")
                # Fix by adding None for missing thumbnails
                while len(video_thumbnails) < len(video_urls):
                    video_thumbnails.append(None)
            
            # Debug output
            for i in range(len(video_urls)):
                thumb_status = "✅" if video_thumbnails[i] else "❌"
                print(f"  Video {i}: {thumb_status} {video_urls[i][:50]}...")
                
        except Exception as e:
            # Clean up any uploaded images
            if image_urls:
                image_service_sync.cleanup_media(image_urls)
            print(f"❌ Video upload failed: {str(e)}")
            traceback.print_exc()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Failed to upload videos: {str(e)}"
            )
    
    # Determine media type
    if image_urls and video_urls:
        media_type = 'mixed'
    elif video_urls:
        media_type = 'video'
    elif image_urls:
        media_type = 'image'
    else:
        media_type = 'text'
    
    # Create diary - USE CONVERTED share_type_value
    diary = Diary(
        user_id=user_id,
        title=diary_in.title,
        content=diary_in.content,
        share_type=ShareType(share_type_value),  # Use converted value
        is_deleted=False,
        created_at=datetime.now(timezone.utc),
        updated_at=datetime.now(timezone.utc),
        images=image_urls,
        videos=video_urls,
        video_thumbnails=video_thumbnails,  # This array will always match videos array
        media_type=media_type
    )
    
    db.add(diary)
    db.flush()

    # Handle group sharing - Check the original share_type from request
    if diary_in.share_type.lower() == "group" and diary_in.group_ids:
        diary_groups = [
            DiaryGroup(diary_id=diary.id, group_id=group_id)
            for group_id in diary_in.group_ids
        ]
        db.add_all(diary_groups)

    db.commit()
    db.refresh(diary)
    
    return diary

def create_diary_for_group(db: Session, group_id: int, diary_data: CreateDiaryForGroup, current_user_id: int):
    group = db.query(Group).filter(Group.id == group_id).first()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                           detail="Group not found")

    check_member = db.query(GroupMember).filter(
        GroupMember.group_id == group_id,
        GroupMember.user_id == current_user_id
    ).first()
    if not check_member:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                           detail="Only member can create diary")
    
    image_urls = []
    if diary_data.images:
        image_urls = image_service_sync.save_multiple_images(diary_data.images, is_diary=True)
    
    new_diary = Diary(
        title=diary_data.title,
        content=diary_data.content,
        share_type=ShareType.group,
        created_at=datetime.now(timezone.utc),
        user_id=current_user_id,
        is_deleted=False,
        images=image_urls
    )
    
    db.add(new_diary)
    db.flush()

    diary_groups = DiaryGroup(diary_id=new_diary.id, group_id=group_id)
    db.add(diary_groups)

    db.commit()
    db.refresh(new_diary)
    return new_diary

def get_by_id(db: Session, diary_id: int) -> Optional[Diary]:
    return db.query(Diary).filter(Diary.id == diary_id, Diary.is_deleted == False).first()

def get_visible(db: Session, user_id: int) -> List[Diary]:
    # Get IDs of friends (people I added as friends)
    my_friends = (
        db.query(Friend.friend_id)
        .filter(
            Friend.user_id == user_id,
            Friend.status == FriendshipStatus.accepted
        )
        .subquery()
    )
    
    # Get IDs of people who added me as friend
    friends_of_me = (
        db.query(Friend.user_id)
        .filter(
            Friend.friend_id == user_id,
            Friend.status == FriendshipStatus.accepted
        )
        .subquery()
    )
    
    all_friends_union = (
        db.query(Friend.friend_id.label('friend_id'))
        .filter(Friend.user_id == user_id, Friend.status == FriendshipStatus.accepted)
        .union(
            db.query(Friend.user_id.label('friend_id'))
            .filter(Friend.friend_id == user_id, Friend.status == FriendshipStatus.accepted)
        )
        .subquery()
    )
    
    user_groups = (
        db.query(GroupMember.group_id)
        .filter(GroupMember.user_id == user_id)
        .subquery()
    )

    group_diaries = (
        db.query(DiaryGroup.diary_id)
        .filter(DiaryGroup.group_id.in_(select(user_groups.c.group_id)))
        .subquery()
    )

    diaries = (
        db.query(Diary)
        .filter(
            Diary.is_deleted.is_(False),
            or_(
                Diary.share_type == ShareType.public,
                
                and_(
                    Diary.share_type == ShareType.friends,
                    or_(
                        and_(
                            Diary.user_id.in_(select(my_friends.c.friend_id)),
                            Diary.user_id != user_id
                        ),
                        and_(
                            Diary.user_id.in_(select(friends_of_me.c.user_id)),
                            Diary.user_id != user_id
                        )
                    )
                ),
                
                and_(
                    Diary.share_type == ShareType.group,
                    Diary.id.in_(select(group_diaries.c.diary_id))
                ),
                
                Diary.user_id == user_id
            )
        )
        .order_by(Diary.created_at.desc())
        .all()
    )

    return diaries

def can_view(db: Session, diary: Diary, user_id: int) -> bool:
    if diary.is_deleted:
        return False
    
    if diary.user_id == user_id:
        return True
    
    if diary.share_type == ShareType.public:
        return True
    
    if diary.share_type == ShareType.personal:
        return False
    
    if diary.share_type == ShareType.friends:
        is_friend = db.query(Friend).filter(
            or_(
                and_(
                    Friend.user_id == diary.user_id,
                    Friend.friend_id == user_id,
                    Friend.status == FriendshipStatus.accepted
                ),
                and_(
                    Friend.user_id == user_id,
                    Friend.friend_id == diary.user_id,
                    Friend.status == FriendshipStatus.accepted
                )
            )
        ).first() is not None
        return is_friend
    
    if diary.share_type == ShareType.group:
        group_ids = [dg.group_id for dg in diary.diary_groups]
        if diary.group_id:
            group_ids.append(diary.group_id)
        
        group_ids = list(set(group_ids))
        
        if not group_ids:
            return False
        
        is_member = db.query(GroupMember).filter(
            GroupMember.group_id.in_(group_ids),
            GroupMember.user_id == user_id
        ).first() is not None
        return is_member
    
    return False

def update_diary(db: Session, diary_id: int, diary_data: DiaryUpdate, current_user_id: int) -> Diary:
    
    diary = db.query(Diary).filter(Diary.id == diary_id, Diary.is_deleted == False).first()
    if not diary:
        raise HTTPException(status_code=404, detail="Diary not found")
    if diary.user_id != current_user_id:
        raise HTTPException(status_code=403, detail="Only creator can edit this diary")
    
    update_dict = diary_data.dict(exclude_unset=True)
    
    if "title" in update_dict:
        diary.title = update_dict["title"]
    if "content" in update_dict:
        diary.content = update_dict["content"]
    
    if "share_type" in update_dict:
        new_share_type = update_dict["share_type"]
        try:
            diary.share_type = ShareType(new_share_type.lower().strip())
        except ValueError:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid share_type. Must be one of: {[t.value for t in ShareType]}"
            )
        
        db.query(DiaryGroup).filter(DiaryGroup.diary_id == diary_id).delete()
        
        if diary.share_type == ShareType.group:
            group_ids = update_dict.get("group_ids") or []
            if group_ids:
                diary_groups = [DiaryGroup(diary_id=diary_id, group_id=gid) for gid in group_ids]
                db.add_all(diary_groups)
    
    if "images" in update_dict:
        new_images = update_dict["images"] or []
        if diary.images:
            to_remove = [img for img in diary.images if img not in new_images]
            if to_remove:
                image_service_sync.cleanup_media(to_remove)
        diary.images = new_images
    
    if "videos" in update_dict:
        new_videos = update_dict["videos"] or []

        # Find videos that are being removed
        to_remove_vids = [vid for vid in diary.videos if vid not in new_videos]
        to_remove_thumbs = []
        if diary.video_thumbnails:
            for i, vid in enumerate(diary.videos):
                if vid in to_remove_vids and i < len(diary.video_thumbnails):
                    to_remove_thumbs.append(diary.video_thumbnails[i])

        # Cleanup removed media
        if to_remove_vids:
            image_service_sync.cleanup_media(to_remove_vids)
        if to_remove_thumbs:
            image_service_sync.cleanup_media(to_remove_thumbs)

        # Generate thumbnails for new videos only
        updated_thumbnails = []
        for vid in new_videos:
            if vid in diary.videos:  # existing video, preserve thumbnail
                idx = diary.videos.index(vid)
                updated_thumbnails.append(diary.video_thumbnails[idx])
            else:
                # New video, generate thumbnail
                _, thumbnail = image_service_sync.save_single_media(vid, is_diary=True)
                updated_thumbnails.append(thumbnail)

        diary.videos = new_videos
        diary.video_thumbnails = updated_thumbnails
    
    if diary.images and diary.videos:
        diary.media_type = "mixed"
    elif diary.videos:
        diary.media_type = "video"
    elif diary.images:
        diary.media_type = "image"
    else:
        diary.media_type = "text"
    
    diary.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(diary)
    return diary

def delete_diary(db: Session, diary_id: int, current_user_id: int):
    diary = db.query(Diary).filter(Diary.id == diary_id, Diary.is_deleted == False).first()
    if not diary:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                           detail="Diary not found")
    
    if diary.user_id != current_user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                           detail="Only creator can delete this diary")
    
    # Clean up images from Cloudinary
    if diary.images:
        image_service_sync.cleanup_media(diary.images)
    
    # Clean up videos and thumbnails
    if diary.videos:
        image_service_sync.cleanup_media(diary.videos)
    
    if diary.video_thumbnails:
        image_service_sync.cleanup_media(diary.video_thumbnails)
    
    # Also clean up comment images
    comments = db.query(DiaryComment).filter(DiaryComment.diary_id == diary_id).all()
    for comment in comments:
        if comment.images:
            image_service_sync.cleanup_media(comment.images)
    
    # HARD DELETE
    db.delete(diary)
    
    db.query(DiaryComment).filter(DiaryComment.diary_id == diary_id).delete()
    db.query(DiaryLike).filter(DiaryLike.diary_id == diary_id).delete()
    db.query(DiaryGroup).filter(DiaryGroup.diary_id == diary_id).delete()
    
    db.commit()
    return {"detail": "Diary has been permanently deleted"}

def share_diary(db: Session, diary_id: int, diary_data: DiaryShare, current_user_id: int):
    diary = db.query(Diary).filter(Diary.id == diary_id, Diary.is_deleted == False).first()
    if not diary:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                           detail="Diary not found")
    
    if diary.user_id != current_user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                           detail="Only diary owner can share this diary")
    
    shared_groups = []
    for group_id in diary_data.group_ids:
        check_existing = db.query(DiaryGroup).filter(
            DiaryGroup.group_id == group_id,
            DiaryGroup.diary_id == diary_id
        ).first()
        if check_existing:
            continue
        
        new_share = DiaryGroup(
            diary_id=diary_id,
            group_id=group_id,
            shared_by=current_user_id,
            is_shared=True,
            shared_at=datetime.utcnow()
        )
        
        db.add(new_share)
        shared_groups.append(group_id)
    
    if not shared_groups:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                           detail="Diary already shared to selected group")
    
    db.commit()
    db.refresh(diary)
    return diary

def delete_share(db: Session, share_id: int, current_user_id: int):
    share = db.query(DiaryGroup).filter(DiaryGroup.id == share_id).first()
    if not share:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                           detail="Share not found")
    
    if share.shared_by != current_user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                           detail="Only who share can delete this share")

    db.delete(share)
    db.commit()
    return {"detail": "Share has been removed"}

def create_comment(db: Session, diary_id: int, current_user: User , content: str, parent_id: Optional[int] = None, images: Optional[List[str]] = None) -> DiaryComment:
    diary = db.query(Diary).filter(Diary.id == diary_id, Diary.is_deleted == False).first()
    if not diary:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                          detail="Diary not found")
    
    if parent_id:
        parent_comment = db.query(DiaryComment).filter(DiaryComment.id == parent_id).first()
        if not parent_comment or parent_comment.diary_id != diary_id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                             detail="Parent comment not found")
    
    image_urls = []
    if images:
        image_urls = image_service_sync.save_multiple_images(images, is_diary=False)
    
    comment = DiaryComment(
        diary_id=diary_id,
        user_id=current_user.id,
        content=content,
        parent_id=parent_id,
        images=image_urls,
        created_at=datetime.now(timezone.utc)
    )
    db.add(comment)
    db.commit()
    db.refresh(comment)
    
    activity = create_activity(
        db,
        actor_id=current_user.id,
        recipient_id=diary.user_id,
        activity_type=ActivityType.post_comment,
        post_id=diary_id,
        extra_data = f"{current_user.username} comment on your status"
    )
    
    comment = db.query(DiaryComment).options(joinedload(DiaryComment.user)).filter(DiaryComment.id == comment.id).first()
    
    return comment

def create_like(db: Session, diary_id: int, current_user: User) -> None:
    diary = db.query(Diary).filter(Diary.id == diary_id, Diary.is_deleted == False).first()
    if not diary:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                          detail="Diary not found")
    
    like = db.query(DiaryLike).filter(
        DiaryLike.diary_id == diary_id,
        DiaryLike.user_id == current_user.id
    ).first()
    if like:
        db.delete(like)
    else:
        like = DiaryLike(diary_id=diary_id, user_id=current_user.id)
        db.add(like)
        
        activity = create_activity(
        db,
        actor_id=current_user.id,
        recipient_id=diary.user_id,
        activity_type=ActivityType.post_like,
        post_id=diary_id,
        extra_data = f"{current_user.username} liked your status"
        )
    
    db.commit()

def get_diary_comments(db: Session, diary_id: int) -> List[DiaryComment]:
    diary = db.query(Diary).filter(Diary.id == diary_id, Diary.is_deleted == False).first()
    if not diary:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                          detail="Diary not found")
    
    return (
        db.query(DiaryComment)
        .options(joinedload(DiaryComment.user))
        .filter(DiaryComment.diary_id == diary_id)
        .order_by(DiaryComment.created_at.asc())
        .all()
    )

def get_diary_likes_count(db: Session, diary_id: int) -> int:
    diary = db.query(Diary).filter(Diary.id == diary_id, Diary.is_deleted == False).first()
    if not diary:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                          detail="Diary not found")
    
    return db.query(DiaryLike).filter(
        DiaryLike.diary_id == diary_id
    ).count()

def delete_comment(db: Session, comment_id: int, current_user_id: int):
    comment = db.query(DiaryComment).filter(DiaryComment.id == comment_id).first()
    if not comment:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                           detail="Comment not found")
    
    if comment.user_id != current_user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                           detail="Only owner can delete this comment")
    
    if comment.images:
        image_service_sync.cleanup_media(comment.images)
    
    if comment.replies:
        for reply in comment.replies:
            if reply.images:
                image_service_sync.cleanup_media(reply.images)
    
    db.delete(comment)
    db.commit()
    return {"detail": "Comment has been deleted"}

def update_comment(db: Session,
                  comment_id: int,
                  comment_data: CommentUpdate,
                  current_user_id: int
                  ):
    
    comment = db.query(DiaryComment).filter(DiaryComment.id == comment_id).first()
    if not comment:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                           detail="Comment not found")
    
    if comment.user_id != current_user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                           detail="Only owner can update this comment")
    
    update_data = comment_data.dict(exclude_unset=True)
    
    if 'images' in update_data:
        if comment.images:
            image_service_sync.cleanup_media(comment.images)
        
        if update_data['images']:
            image_urls = image_service_sync.save_multiple_images(update_data['images'], is_diary=False)
            comment.images = image_urls
        else:
            comment.images = []
    
    if 'content' in update_data:
        comment.content = update_data['content']
    
    db.commit()
    db.refresh(comment)
    return comment

def save_diary_to_favorites(db, user_id: int, diary_id: int):
    favorite = (
        db.query(DiaryFavorite)
        .filter_by(user_id=user_id, diary_id=diary_id)
        .first()
    )

    if favorite:
        return favorite  # already saved

    favorite = DiaryFavorite(
        user_id=user_id,
        diary_id=diary_id
    )

    db.add(favorite)
    db.commit()
    db.refresh(favorite)

    return favorite

def remove_diary_from_favorites(db, user_id: int, diary_id: int):
    favorite = (
        db.query(DiaryFavorite)
        .filter_by(user_id=user_id, diary_id=diary_id)
        .first()
    )

    if favorite:
        db.delete(favorite)
        db.commit()
        
    return True

def get_favorite_diaries(db, user_id: int):
    favovites = (
        db.query(DiaryFavorite)
        .filter(DiaryFavorite.user_id == user_id)
        .order_by(DiaryFavorite.created_at.desc())
        .all()
    )
    
    return favovites

def get_list_favorite_diarie(db, user_id: int):
    favovites = (
        db.query(Diary)
        .join(DiaryFavorite)
        .options(
            joinedload(Diary.favorited_by),
        )
        .filter(DiaryFavorite.user_id == user_id)
        .order_by(DiaryFavorite.created_at.desc())
        .all()
    )
    
    return favovites
