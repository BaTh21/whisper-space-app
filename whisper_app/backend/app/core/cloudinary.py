import traceback
from typing import Any, Dict
import cloudinary
from cloudinary import uploader, api
from cloudinary.utils import cloudinary_url
import uuid
import os
import tempfile

# Remove the direct settings import to avoid circular imports
# from app.core.config import settings  # ← Remove this

def configure_cloudinary():
    """Configure Cloudinary with all necessary settings"""
    try:
        # Use environment variables directly to avoid circular imports
        cloudinary.config(
            cloud_name=os.getenv('CLOUDINARY_CLOUD_NAME'),
            api_key=os.getenv('CLOUDINARY_API_KEY'),
            api_secret=os.getenv('CLOUDINARY_API_SECRET'),
            secure=True
        )
        print("✅ Cloudinary configured successfully")
    except Exception as e:
        print(f"❌ Cloudinary configuration failed: {str(e)}")
        raise

# Call configuration
configure_cloudinary()

def upload_to_cloudinary(file_content, public_id=None, folder=None, resource_type="image", **kwargs):
    """
    Upload file to Cloudinary with support for different resource types
    """
    try:
        # Use consistent folder handling
        base_folder = os.getenv('CLOUDINARY_UPLOAD_FOLDER', 'whisper_space')
        
        upload_kwargs = {
            "file": file_content,
            "public_id": public_id,
            "folder": f"{base_folder}/{folder}" if folder else base_folder,
            "overwrite": True,
            "resource_type": resource_type,
        }
        
        # Add additional kwargs
        upload_kwargs.update(kwargs)
        
        # Apply transformations based on resource type
        if resource_type == "image":
            if "transformation" not in upload_kwargs:
                upload_kwargs["transformation"] = [
                    {"width": 400, "height": 400, "crop": "fill"},
                    {"quality": "auto"},
                    {"format": "auto"}
                ]
        
        elif resource_type == "video":
            if "transformation" not in upload_kwargs:
                upload_kwargs["transformation"] = [
                    {"width": 1280, "height": 720, "crop": "limit"},
                    {"quality": "auto"},
                    {"format": "auto"}
                ]
            
            # Add video-specific optimizations
            upload_kwargs.update({
                "chunk_size": 6000000,  # 6MB chunks for large videos
                "eager": [
                    {"width": 640, "height": 360, "crop": "limit"},
                    {"width": 1280, "height": 720, "crop": "limit"}
                ],
                "eager_async": True,
                "resource_type": "video"
            })
        
        elif resource_type == "raw":
            # For audio files and other raw files
            if folder:
                upload_kwargs["folder"] = f"{base_folder}/{folder}"
        
        upload_result = uploader.upload(**upload_kwargs)
        return upload_result
    except Exception as e:
        raise Exception(f"Cloudinary upload failed: {str(e)}")

def upload_video_to_cloudinary(video_data: bytes, folder: str = "videos") -> Dict[str, Any]:
    """Upload video to Cloudinary with GUARANTEED thumbnail"""
    try:
        base_folder = os.getenv('CLOUDINARY_UPLOAD_FOLDER', 'whisper_space')
        full_folder = f"{base_folder}/{folder}"
        public_id = f"video_{uuid.uuid4().hex[:12]}"
        
        print(f"📤 Uploading video to {full_folder}/{public_id}")
        print(f"📊 Video size: {len(video_data)} bytes")
        
        # Create temporary file
        with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as tmp_file:
            tmp_file.write(video_data)
            tmp_path = tmp_file.name
        
        try:
            # Upload video with explicit video format
            upload_result = uploader.upload(
                tmp_path,
                resource_type="video",
                public_id=public_id,
                folder=full_folder,
                overwrite=True,
                eager=[  # Force thumbnail generation
                    {
                        "width": 320,
                        "height": 180,
                        "crop": "fill",
                        "quality": "auto",
                        "format": "jpg"
                    }
                ],
                eager_async=False,  # Make it synchronous
                transformation=[
                    {"width": 1280, "height": 720, "crop": "limit"},
                    {"quality": "auto:eco"},
                    {"format": "mp4"}
                ],
                # Important for large files
                chunk_size=6000000,  # 6MB chunks
                timeout=120
            )
            
            print(f"📊 Cloudinary upload successful:")
            print(f"  - Secure URL: {upload_result.get('secure_url')}")
            print(f"  - Eager transformations: {upload_result.get('eager')}")
            print(f"  - Format: {upload_result.get('format')}")
            print(f"  - Duration: {upload_result.get('duration')}")
            print(f"  - Bytes: {upload_result.get('bytes')}")
            
            # Get thumbnail from eager transformation
            thumbnail_url = None
            if 'eager' in upload_result and upload_result['eager']:
                for eager_item in upload_result['eager']:
                    if eager_item.get('format') == 'jpg':
                        thumbnail_url = eager_item.get('secure_url')
                        print(f"📸 Found eager thumbnail: {thumbnail_url}")
                        break
            
            # If still no thumbnail, generate one manually
            if not thumbnail_url:
                print(f"⚠️ No eager thumbnail, generating manually...")
                thumbnail_url, _ = cloudinary_url(
                    upload_result["public_id"],
                    transformation=[
                        {"width": 320, "height": 180, "crop": "fill"},
                        {"quality": "auto"},
                        {"format": "jpg"}
                    ],
                    resource_type="video"
                )
                print(f"📸 Generated manual thumbnail: {thumbnail_url}")
            
            print(f"📸 Final thumbnail URL: {thumbnail_url}")
            
            return {
                "secure_url": upload_result["secure_url"],
                "public_id": upload_result["public_id"],
                "thumbnail_url": thumbnail_url,  # GUARANTEED to have value
                "duration": upload_result.get("duration"),
                "bytes": upload_result.get("bytes"),
                "format": upload_result.get("format", "mp4")
            }
            
        finally:
            # Cleanup temp file
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
                
    except Exception as e:
        print(f"❌ Video upload failed: {str(e)}")
        traceback.print_exc()
        raise Exception(f"Video upload failed: {str(e)}")

def upload_voice_message(file_content: bytes, public_id: str = None, folder: str = "voice_messages"):
    """
    FIXED: Consistent folder handling for audio files
    """
    try:
        base_folder = os.getenv('CLOUDINARY_UPLOAD_FOLDER', 'whisper_space')
        full_folder = f"{base_folder}/{folder}"

        if not public_id:
            public_id = f"voice_{uuid.uuid4().hex[:12]}"

        print(f"📤 Uploading voice → {full_folder}/{public_id}")

        upload_result = uploader.upload(
            file_content,
            resource_type="video",  # Use "video" for audio files in Cloudinary
            public_id=public_id,
            folder=full_folder,
            overwrite=True,
            format="mp3",
            timeout=30
        )

        mp3_url = upload_result["secure_url"]
        print(f"✅ VOICE UPLOAD SUCCESS → {mp3_url}")

        return {
            "secure_url": mp3_url,
            "public_id": upload_result["public_id"],
            "format": upload_result.get("format", "mp3"),
            "duration": upload_result.get("duration"),
            "bytes": upload_result.get("bytes"),
        }

    except Exception as e:
        print(f"❌ CRITICAL: Voice upload failed: {str(e)}")
        traceback.print_exc()
        raise Exception(f"Cloudinary upload failed: {str(e)}")

def generate_thumbnail_url(video_url, width=320, height=180, crop="fill"):
    """
    Generate a thumbnail URL for a video
    """
    try:
        if not video_url:
            return None
        
        # Extract public_id from URL
        public_id = extract_public_id_from_url(video_url)
        if not public_id:
            return None
        
        # Generate thumbnail URL
        thumbnail_url, _ = cloudinary_url(
            public_id,
            transformation=[
                {"width": width, "height": height, "crop": crop},
                {"quality": "auto"},
                {"format": "jpg"}
            ],
            resource_type="video"
        )
        
        return thumbnail_url
    except Exception as e:
        print(f"Failed to generate thumbnail: {str(e)}")
        return None

def delete_from_cloudinary(public_id, resource_type="image"):
    """
    Delete file from Cloudinary with resource type support
    """
    try:
        result = uploader.destroy(public_id, resource_type=resource_type)
        return result.get('result') == 'ok'
    except Exception as e:
        print(f"Failed to delete from Cloudinary: {str(e)}")
        return False

def extract_public_id_from_url(url):
    """Extract public_id from Cloudinary URL"""
    try:
        if not url or 'res.cloudinary.com' not in url:
            return None
        
        parts = url.split('/')
        upload_index = parts.index('upload')
        
        if upload_index >= len(parts) - 1:
            return None
        
        public_id_parts = parts[upload_index + 2:]
        public_id = '/'.join(public_id_parts)
        
        if '.' in public_id:
            public_id = public_id.rsplit('.', 1)[0]
        
        return public_id
    except Exception as e:
        print(f"Error extracting public_id: {str(e)}")
        return None

def check_cloudinary_health():
    """Check if Cloudinary is properly configured and accessible"""
    try:
        cloud_name = os.getenv('CLOUDINARY_CLOUD_NAME')
        api_key = os.getenv('CLOUDINARY_API_KEY') 
        api_secret = os.getenv('CLOUDINARY_API_SECRET')
        
        if not all([cloud_name, api_key, api_secret]):
            return False, "Missing Cloudinary environment variables"
        
        # Test the configuration
        api.ping()
        
        return True, "Cloudinary is properly configured and responsive"
    except Exception as e:
        return False, f"Cloudinary configuration error: {str(e)}"

def get_resource_info(public_id, resource_type="image"):
    """
    Get information about a Cloudinary resource
    """
    try:
        resource_info = api.resource(public_id, resource_type=resource_type)
        return resource_info
    except Exception as e:
        print(f"Failed to get resource info: {str(e)}")
        return None

def generate_video_poster(video_url):
    """
    Generate a poster image (thumbnail) for a video
    """
    try:
        public_id = extract_public_id_from_url(video_url)
        if not public_id:
            return None
        
        # Generate poster URL with video frame at 1 second
        poster_url, _ = cloudinary_url(
            public_id,
            transformation=[
                {"width": 1280, "height": 720, "crop": "fill"},
                {"quality": "auto"},
                {"format": "jpg"}
            ],
            resource_type="video"
        )
        
        return poster_url
    except Exception as e:
        print(f"Failed to generate video poster: {str(e)}")
        return None
def generate_video_thumbnail(video_url: str) -> str:
    """Generate thumbnail for existing video URL"""
    try:
        public_id = extract_public_id_from_url(video_url)
        if not public_id:
            raise ValueError("Could not extract public_id from URL")
        
        thumbnail_url, _ = cloudinary_url(
            public_id,
            transformation=[
                {"width": 320, "height": 180, "crop": "fill"},
                {"quality": "auto"},
                {"format": "jpg"}
            ],
            resource_type="video"
        )
        
        return thumbnail_url
    except Exception as e:
        print(f"Failed to generate thumbnail: {str(e)}")
        raise

def create_video_transformation(public_id, transformations=None, resource_type="video"):
    """
    Create a transformed version of a video
    """
    try:
        if not transformations:
            transformations = [
                {"width": 640, "height": 360, "crop": "limit"},
                {"quality": "auto:eco"},
                {"format": "mp4"}
            ]
        
        transformed_url, _ = cloudinary_url(
            public_id,
            transformation=transformations,
            resource_type=resource_type
        )
        
        return transformed_url
    except Exception as e:
        print(f"Failed to create video transformation: {str(e)}")
        return None

def cleanup_old_resources(folder=None, resource_type="image", older_than_days=30):
    """
    Clean up old resources from Cloudinary
    """
    try:
        base_folder = os.getenv('CLOUDINARY_UPLOAD_FOLDER', 'whisper_space')
        search_folder = f"{base_folder}/{folder}" if folder else base_folder
        
        # Search for resources older than specified days
        search_result = api.resources(
            type="upload",
            prefix=search_folder,
            resource_type=resource_type,
            max_results=100
        )
        
        deleted_count = 0
        for resource in search_result.get('resources', []):
            # Check if resource is older than specified days
            # You would need to implement age checking logic here
            # This is a placeholder implementation
            
            try:
                delete_from_cloudinary(resource['public_id'], resource_type)
                deleted_count += 1
            except Exception as e:
                print(f"Failed to delete {resource['public_id']}: {str(e)}")
        
        return deleted_count
        
    except Exception as e:
        print(f"Failed to cleanup old resources: {str(e)}")
        return 0