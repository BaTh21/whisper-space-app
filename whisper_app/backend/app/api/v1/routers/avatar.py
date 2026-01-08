from fastapi import APIRouter, Depends, File, UploadFile, HTTPException, status
from sqlalchemy.orm import Session
import uuid
from pathlib import Path
from app.core.database import get_db
from app.core.security import get_current_user
from app.core.cloudinary import (
    configure_cloudinary, 
    upload_to_cloudinary, 
    delete_from_cloudinary,
    extract_public_id_from_url
)
from app.models.user import User

# Configure Cloudinary on startup
configure_cloudinary()

router = APIRouter(tags=["avatars"])

# Avatar configuration
ALLOWED_EXTENSIONS = {".png", ".jpg", ".jpeg"}
MAX_FILE_SIZE = 2 * 1024 * 1024  # 2MB

@router.post("/upload")
async def upload_avatar(
    avatar: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Upload a new avatar for the current user to Cloudinary
    """
    try:
        # Validate file extension
        file_extension = Path(avatar.filename).suffix.lower()
        if file_extension not in ALLOWED_EXTENSIONS:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid file type. Only PNG and JPG files are allowed."
            )

        # Read file content
        content = await avatar.read()
        
        # Validate file size
        if len(content) > MAX_FILE_SIZE:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="File too large. Maximum size is 2MB."
            )

        # Generate unique filename
        unique_filename = f"{uuid.uuid4().hex}{file_extension}"

        # Upload to Cloudinary
        upload_result = upload_to_cloudinary(content, public_id=unique_filename)
        
        if not upload_result or 'secure_url' not in upload_result:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to upload avatar to cloud storage."
            )

        # Delete old avatar from Cloudinary if it exists and is not default
        if current_user.avatar_url and not current_user.avatar_url.startswith('/static/'):
            public_id = extract_public_id_from_url(current_user.avatar_url)
            if public_id:
                delete_from_cloudinary(public_id)

        # Update user's avatar URL in database
        current_user.avatar_url = upload_result['secure_url']
        db.commit()

        return {
            "avatar_url": upload_result['secure_url'],
            "message": "Avatar uploaded successfully",
            "filename": unique_filename
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to upload avatar: {str(e)}"
        )

@router.delete("/delete")
async def delete_avatar(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Delete current user's avatar from Cloudinary and set to default
    """
    try:
        if not current_user.avatar_url:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No avatar to delete"
            )

        # Delete from Cloudinary if it's a Cloudinary URL
        if not current_user.avatar_url.startswith('/static/'):
            public_id = extract_public_id_from_url(current_user.avatar_url)
            if public_id:
                delete_from_cloudinary(public_id)

        # Set avatar_url to null in database
        current_user.avatar_url = None
        db.commit()

        return {"message": "Avatar deleted successfully"}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete avatar: {str(e)}"
        )

@router.get("/info/files")
async def list_avatar_files():
    """
    This endpoint is no longer needed as files are stored in Cloudinary
    """
    return {
        "message": "Avatars are stored in Cloudinary",
        "total_files": 0,
        "files": []
    }