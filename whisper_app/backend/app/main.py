from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from app.api.v1.routers import auth, users, chats, diaries, websockets, friends, groups, avatar, notes, message, activity
from app.models import base
from app.core.database import engine
import os
from app.services.websocket_manager import manager
from app.api.v1.routers import upload

from app.core.cloudinary import configure_cloudinary
from app.api.v1.routers import reactions
from app.api.v1.routers import system_log

# Create database tables
base.Base.metadata.create_all(bind=engine)

# Configure Cloudinary
configure_cloudinary()  # ADDED

app = FastAPI(
    title="Whisper Space",
)

# CORS middleware - UPDATED with your React domain
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173", 
        "http://localhost:5174", 
        "https://whisper-space-bot-reactjs.onrender.com",
        "https://whisper-space-two.vercel.app",
    ],
    allow_credentials=True,
    allow_methods=["*"], 
    allow_headers=["*"], 
)

# Include API routers
app.include_router(auth.router, prefix="/api/v1/auth", tags=["auth"])
app.include_router(users.router, prefix="/api/v1/users", tags=["users"])
app.include_router(chats.router, prefix="/api/v1/chats", tags=["chats"])
app.include_router(diaries.router, prefix="/api/v1/diaries", tags=["diaries"])
app.include_router(groups.router, prefix="/api/v1/groups", tags=["groups"])
app.include_router(friends.router, prefix="/api/v1/friends", tags=["friends"])
app.include_router(websockets.router, prefix="/api/v1/ws", tags=["websockets"])
app.include_router(notes.router, prefix="/api/v1/notes", tags=["notes"])
app.include_router(avatar.router, prefix="/api/v1/avatars", tags=["avatars"])
app.include_router(message.router, prefix="/api/v1/messages", tags=["messages"])
app.include_router(reactions.router, prefix="/api/v1", tags=["reactions"])
app.include_router(activity.router, prefix="/api/v1/activities", tags=["activities"])
app.include_router(system_log.router, prefix="/api/v1", tags=["devices"])
app.include_router(upload.router, prefix="/api/v1/upload")


# Create static directories
os.makedirs("static/avatars", exist_ok=True)

# Serve React build files (if you're serving both from same domain)
if os.path.exists("dist"):
    app.mount("/", StaticFiles(directory="dist", html=True), name="react-app")

# Catch-all route for React Router
@app.get("/{full_path:path}")
async def serve_react_app(full_path: str):
    """Serve React app for all unmatched routes"""
    if os.path.exists("dist/index.html"):
        return FileResponse("dist/index.html")
    return {"message": "React app not built"}

@app.get("/")
def root():
    return {"message": "Whisper Space API"}

@app.get("/api/v1/health")
def health_check():
    return {"status": "healthy", "message": "Whisper Space API is running"}

@app.get("/api/v1/test-email")
async def test_email_endpoint():
    """Test email configuration"""
    from app.services.email import send_verification_email_sync
    test_email = "your-test-email@gmail.com"
    code = "999999"
    
    try:
        success = send_verification_email_sync(test_email, code)
        if success:
            return {"status": "success", "message": f"Test email sent to {test_email}"}
        else:
            return {"status": "error", "message": "Failed to send email"}
    except Exception as e:
        return {"status": "error", "message": str(e)}