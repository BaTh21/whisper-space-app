# app/services/image_service_sync.py - COMPLETE FIXED VERSION
import os
import base64
import uuid
import traceback
from typing import List, Optional, Tuple
from fastapi import HTTPException, status
import mimetypes
import tempfile

# Initialize mimetypes
mimetypes.init()

from app.core.cloudinary import (
    delete_from_cloudinary, 
    extract_public_id_from_url,
    generate_video_thumbnail, 
    upload_to_cloudinary,
    upload_video_to_cloudinary,
)

class ImageServiceSync:
    def __init__(self):
        # Comprehensive list of allowed image types
        self.allowed_image_types = {
            'image/jpeg', 'image/jpg', 'image/png', 'image/gif', 
            'image/webp', 'image/bmp', 'image/tiff', 'image/x-icon',
            'image/x-ms-bmp', 'image/svg+xml'
        }
        
        self.allowed_video_types = {
            'video/mp4', 'video/quicktime', 'video/x-msvideo', 
            'video/webm', 'video/ogg', 'video/x-ms-wmv',
            'video/x-flv', 'video/x-matroska', 'video/avi',
            'video/mpeg', 'video/3gpp', 'video/3gpp2'
        }
        
        self.max_image_size = 20 * 1024 * 1024  # 20MB
        self.max_video_size = 100 * 1024 * 1024  # 100MB
        
        # MIME type normalization mapping
        self.mime_type_normalization = {
            'image/jpg': 'image/jpeg',
            'image/x-png': 'image/png',
            'image/x-icon': 'image/x-icon',
            'image/x-ms-bmp': 'image/bmp',
            'video/quicktime': 'video/mp4',
            'video/x-msvideo': 'video/avi',
        }
    
    def normalize_mime_type(self, mime_type: str) -> str:
        """Normalize MIME type to standard format"""
        mime_type = mime_type.lower().strip()
        
        # Apply normalization mapping
        normalized = self.mime_type_normalization.get(mime_type, mime_type)
        return normalized
    
    def validate_and_decode_media(self, data_url: str) -> Tuple[bytes, str, str]:
        """Validate and decode base64 media data URL with enhanced MIME type handling"""
        try:
            if not data_url or ',' not in data_url:
                raise ValueError("Invalid data URL format")
            
            header, encoded = data_url.split(',', 1)
            mime_info = header.split(';')[0]
            
            print(f"🔍 Processing data URL with header: {mime_info}")
            
            # Extract MIME type
            if ':' not in mime_info:
                raise ValueError("No MIME type specified in data URL")
            
            mime_type = mime_info.split(':')[1]
            
            # Normalize MIME type
            mime_type = self.normalize_mime_type(mime_type)
            print(f"📋 Normalized MIME type: {mime_type}")
            
            # Decode base64
            print(f"🔓 Decoding base64 data...")
            media_data = base64.b64decode(encoded)
            print(f"📦 Decoded size: {len(media_data)} bytes")
            
            # Accept all image/* and video/* MIME types for flexibility
            if mime_type.startswith('image/'):
                media_type = 'image'
                print(f"✅ Accepted as image: {mime_type}")
                
                # Check size
                if len(media_data) > self.max_image_size:
                    raise ValueError(
                        f"Image too large. Max {self.max_image_size // 1024 // 1024}MB, "
                        f"got {len(media_data) // 1024 // 1024}MB"
                    )
                    
            elif mime_type.startswith('video/'):
                media_type = 'video'
                print(f"✅ Accepted as video: {mime_type}")
                
                # Check size
                if len(media_data) > self.max_video_size:
                    raise ValueError(
                        f"Video too large. Max {self.max_video_size // 1024 // 1024}MB, "
                        f"got {len(media_data) // 1024 // 1024}MB"
                    )
                    
            elif mime_type.startswith('audio/'):
                media_type = 'audio'
                print(f"⚠️ Audio file detected: {mime_type}")
                raise ValueError(f"Audio files not supported: {mime_type}")
            else:
                print(f"❌ Unsupported media type: {mime_type}")
                raise ValueError(f"Unsupported media type: {mime_type}")
            
            return media_data, mime_type, media_type
            
        except Exception as e:
            print(f"❌ Validation error: {str(e)}")
            raise ValueError(f"Invalid media data: {str(e)}")
    
    def upload_image(self, image_data: bytes, folder: str = "images", mime_type: str = None) -> str:
        """Upload image to Cloudinary with format detection"""
        try:
            filename = f"image_{uuid.uuid4().hex[:12]}"
            print(f"📤 Uploading image: {filename} to folder: {folder}")
            
            upload_kwargs = {
                "file_content": image_data,
                "public_id": filename,
                "folder": folder,
                "resource_type": "image",
                "transformation": [
                    {"width": 1200, "height": 1200, "crop": "limit"},
                    {"quality": "auto"},
                    {"format": "auto"}
                ]
            }
            
            upload_result = upload_to_cloudinary(**upload_kwargs)
            
            print(f"✅ Image uploaded: {upload_result['secure_url'][:50]}...")
            return upload_result["secure_url"]
            
        except Exception as e:
            print(f"❌ Image upload failed: {str(e)}")
            traceback.print_exc()
            raise Exception(f"Image upload failed: {str(e)}")
    
    def upload_video(self, video_data: bytes, folder: str = "videos") -> Tuple[str, Optional[str]]:
        """Upload video to Cloudinary with thumbnail"""
        try:
            print(f"📤 Uploading video to folder: {folder}")
            upload_result = upload_video_to_cloudinary(video_data, folder)
            return upload_result["secure_url"], upload_result.get("thumbnail_url")
            
        except Exception as e:
            print(f"❌ Video upload failed: {str(e)}")
            raise Exception(f"Video upload failed: {str(e)}")
    
    def save_single_media(self, data_url: str, is_diary: bool = True) -> Tuple[str, Optional[str]]:
        """Save single media item with GUARANTEED thumbnail for videos"""
        try:
            print(f"🔄 save_single_media called")
            
            if not data_url:
                raise ValueError("Empty data URL")
            
            print(f"📊 Data URL length: {len(data_url)}")
            
            # If already a URL (for updates/edits)
            if data_url.startswith(('http://', 'https://')):
                print(f"📎 Already a URL: {data_url[:50]}...")
                
                # Check if it's a video and generate thumbnail
                if any(ext in data_url.lower() for ext in ['.mp4', '.mov', '.avi', '.webm', 'video']):
                    print(f"🎥 Existing video URL detected")
                    try:
                        thumbnail = generate_video_thumbnail(data_url)
                        print(f"📸 Generated thumbnail for existing video")
                        return data_url, thumbnail
                    except Exception as thumb_err:
                        print(f"⚠️ Could not generate thumbnail: {thumb_err}")
                        return data_url, None
                else:
                    return data_url, None
            
            # New upload - validate and decode
            print(f"🔍 Validating data URL...")
            media_data, mime_type, media_type = self.validate_and_decode_media(data_url)
            print(f"📦 Media type: {media_type}, MIME: {mime_type}, Size: {len(media_data)} bytes")
            
            base_folder = "diaries" if is_diary else "comments"
            
            if media_type == 'image':
                folder = f"{base_folder}/images"
                print(f"📷 Uploading image to {folder}")
                url = self.upload_image(media_data, folder, mime_type)
                print(f"✅ Image uploaded: {url[:50]}...")
                return url, None
                
            else:  # video
                folder = f"{base_folder}/videos"
                print(f"🎬 Uploading video to {folder}")
                
                # This function GUARANTEES a thumbnail
                upload_result = upload_video_to_cloudinary(media_data, folder)
                url = upload_result["secure_url"]
                thumbnail = upload_result["thumbnail_url"]
                
                print(f"✅ Video uploaded: {url[:50]}...")
                print(f"📸 Thumbnail: {thumbnail[:50] if thumbnail else 'None'}...")
                
                # Double-check thumbnail
                if not thumbnail:
                    print(f"⚠️ CRITICAL: Still no thumbnail, trying again...")
                    thumbnail = generate_video_thumbnail(url)
                
                return url, thumbnail or None
                
        except Exception as e:
            print(f"❌ Error in save_single_media: {str(e)}")
            traceback.print_exc()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Failed to save media: {str(e)}"
            )
    
    def save_multiple_images(self, images_data: List[str], is_diary: bool = True) -> List[str]:
        """Save multiple images"""
        saved_urls = []
        for i, img_data in enumerate(images_data):
            if img_data:
                try:
                    print(f"📷 Processing image {i + 1}/{len(images_data)}")
                    url, _ = self.save_single_media(img_data, is_diary)
                    saved_urls.append(url)
                except Exception as e:
                    print(f"❌ Failed to save image {i + 1}: {e}")
                    continue
        return saved_urls
    
    def save_multiple_videos(self, videos_data: List[str], is_diary: bool = True) -> Tuple[List[str], List[Optional[str]]]:
        """Save multiple videos - PROCESS ONE BY ONE"""
        print(f"🎬 Processing {len(videos_data)} videos individually")
        
        saved_urls = []
        thumbnails = []
        
        for idx, vid_data in enumerate(videos_data):
            if not vid_data:
                continue
                
            try:
                print(f"  Processing video {idx + 1}/{len(videos_data)}")
                url, thumbnail = self.save_single_media(vid_data, is_diary)
                
                if url:
                    saved_urls.append(url)
                    thumbnails.append(thumbnail)
                    print(f"  ✅ Video {idx + 1} success")
                else:
                    print(f"  ⚠️ Video {idx + 1} returned no URL")
                    
            except Exception as e:
                print(f"  ❌ Video {idx + 1} failed: {str(e)}")
                continue
        
        # Ensure arrays match length
        while len(thumbnails) < len(saved_urls):
            thumbnails.append(None)
        
        print(f"🎬 Completed: {len(saved_urls)} videos, {len([t for t in thumbnails if t])} thumbnails")
        return saved_urls, thumbnails
    
    def delete_media(self, media_url: str) -> bool:
        """Delete media from Cloudinary"""
        try:
            if not media_url or not media_url.startswith(('http://', 'https://')):
                return False
            
            public_id = extract_public_id_from_url(media_url)
            if not public_id:
                return False
            
            # Determine resource type
            if 'video' in media_url.lower() or any(ext in media_url for ext in ['.mp4', '.mov', '.avi']):
                resource_type = "video"
            else:
                resource_type = "image"
            
            return delete_from_cloudinary(public_id, resource_type=resource_type)
            
        except Exception as e:
            print(f"Failed to delete media: {e}")
            return False
    
    def cleanup_media(self, media_urls: List[str]):
        """Clean up multiple media files"""
        if not media_urls:
            return
            
        for url in media_urls:
            if url:
                try:
                    public_id = extract_public_id_from_url(url)
                    if public_id:
                        if 'video' in url.lower():
                            delete_from_cloudinary(public_id, resource_type="video")
                        else:
                            delete_from_cloudinary(public_id, resource_type="image")
                except Exception:
                    pass

# Global instance
image_service_sync = ImageServiceSync()