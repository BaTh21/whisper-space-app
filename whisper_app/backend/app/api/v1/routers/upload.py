# api/v1/routers/upload.py - NEW FILE
from fastapi import APIRouter, Depends, HTTPException, status, Body
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.services.image_service_sync import image_service_sync
import base64

router = APIRouter(tags=["uploads"])

@router.post("/media")
async def upload_media(
    data_url: str = Body(...),
    filename: str = Body(...),
    is_diary: bool = Body(True),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Upload media from Flutter app (images or videos)
    Accepts base64 data URL and returns Cloudinary URL
    """
    print(f"📤 Upload media request from user {current_user.id}")
    print(f"📁 Filename: {filename}")
    print(f"📊 Data URL length: {len(data_url) if data_url else 0}")
    
    try:
        # Validate data_url format
        if not data_url or ',' not in data_url:
            print("❌ Invalid data URL format")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid data URL format. Expected: data:[mime];base64,[data]"
            )
        
        # Validate it's a proper data URL
        if not data_url.startswith('data:'):
            print("❌ Not a data URL")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Not a valid data URL"
            )
        
        print("✅ Data URL format is valid")
        
        # Upload using image_service_sync
        try:
            print("🔄 Calling image_service_sync.save_single_media...")
            url, thumbnail = image_service_sync.save_single_media(data_url, is_diary=is_diary)
            
            print(f"✅ Upload successful!")
            print(f"   URL: {url[:100]}...")
            print(f"   Has thumbnail: {'Yes' if thumbnail else 'No'}")
            
            response_data = {
                "success": True,
                "url": url,
                "type": "video" if thumbnail else "image",
                "thumbnail": thumbnail
            }
            
            return response_data
            
        except ValueError as ve:
            print(f"❌ Validation error: {ve}")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid media data: {str(ve)}"
            )
        except Exception as e:
            print(f"❌ Upload error: {str(e)}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to upload media: {str(e)}"
            )
            
    except HTTPException:
        raise
    except Exception as e:
        print(f"❌ Unexpected error: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Internal server error: {str(e)}"
        )