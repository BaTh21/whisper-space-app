import asyncio
from datetime import datetime, timedelta
import json
from typing import Optional
from fastapi import Depends, HTTPException, WebSocket, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session
from app.core.config import settings
from app.core.database import get_db
from app.models.user import User

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def verify_token(token: str) -> Optional[dict]:
    """
    Verify JWT token and return payload
    """
    # First check if token is valid/not dummy
    if not token or token == "dummy-dev-token":
        print("⚠️ Invalid or dummy token provided")
        return None
    
    # Additional validation for JWT format
    if not isinstance(token, str):
        print("❌ Token is not a string")
        return None
    
    # Check if token has the basic JWT structure (3 parts separated by dots)
    parts = token.split('.')
    if len(parts) != 3:
        print(f"❌ Invalid JWT format: expected 3 parts, got {len(parts)}")
        return None
    
    try:
        # Decode and verify the JWT token
        payload = jwt.decode(
            token,
            settings.JWT_SECRET,
            algorithms=[settings.JWT_ALGORITHM],
            options={"verify_exp": True}
        )
        return payload
        
    except jwt.ExpiredSignatureError:
        print("❌ Token has expired")
        return None
    except jwt.JWTError as e:
        print(f"❌ JWT Error: {e}")
        return None
    except Exception as e:
        print(f"❌ Token verification error: {e}")
        return None

def create_access_token(user_id: int) -> str:
    """
    Create JWT access token
    """
    expire = datetime.utcnow() + timedelta(minutes=settings.JWT_ACCESS_EXPIRE_MINUTES)
    payload = {
        "sub": str(user_id),  # JWT standard requires string for 'sub'
        "exp": expire,
        "type": "access",
        "iat": datetime.utcnow()  # Issued at time
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)

def create_refresh_token(user_id: int) -> str:
    """
    Create JWT refresh token
    """
    expire = datetime.utcnow() + timedelta(days=settings.JWT_REFRESH_EXPIRE_DAYS)
    payload = {
        "sub": str(user_id),
        "exp": expire,
        "type": "refresh",
        "iat": datetime.utcnow()
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)

def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db)
) -> User:
    """
    Get current user from JWT token
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    
    # Verify token
    payload = verify_token(token)
    if not payload:
        raise credentials_exception
    
    # Check token type
    token_type = payload.get("type")
    if token_type != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token type"
        )
    
    # Get user ID from token
    user_id_str = payload.get("sub")
    if not user_id_str:
        raise credentials_exception
    
    # Convert to integer
    try:
        user_id = int(user_id_str)
    except (ValueError, TypeError):
        raise credentials_exception
    
    # Get user from database
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise credentials_exception
    
    return user

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verify a plain password against a hashed password
    """
    # You should use a proper password hashing library like passlib
    # For now, using a simple comparison (replace with actual hashing)
    from passlib.context import CryptContext
    
    pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    return pwd_context.verify(plain_password, hashed_password)

def hash_password(password: str) -> str:
    """
    Hash a password
    """
    from passlib.context import CryptContext
    
    pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    return pwd_context.hash(password)

# WebSocket-specific authentication
async def get_current_user_ws(
    websocket: WebSocket,
    db: Session = Depends(get_db)
) -> Optional[User]:
    """
    Get current user from WebSocket connection
    """
    try:
        # Try to get token from query params first
        token = None
        query_params = dict(websocket.query_params)
        if "token" in query_params:
            token = query_params["token"]
        
        # If no token in query params, try to receive auth message
        if not token:
            try:
                data = await asyncio.wait_for(websocket.receive_json(), timeout=5.0)
                if data.get("type") == "auth" and data.get("token"):
                    token = data["token"]
            except (asyncio.TimeoutError, json.JSONDecodeError):
                return None
        
        if not token:
            return None
        
        # Verify token
        payload = verify_token(token)
        if not payload:
            return None
        
        # Check token type
        token_type = payload.get("type")
        if token_type != "access":
            return None
        
        # Get user ID
        user_id_str = payload.get("sub")
        if not user_id_str:
            return None
        
        # Convert to integer
        try:
            user_id = int(user_id_str)
        except (ValueError, TypeError):
            return None
        
        # Get user from database
        user = db.query(User).filter(User.id == user_id).first()
        return user
        
    except Exception as e:
        print(f"WebSocket auth error: {e}")
        return None