from datetime import datetime, timedelta
import jwt
from app.core.config import settings

def create_dev_token(user_id=1, username="dev_user"):
    """
    Create a development JWT token using app's JWT_SECRET
    """
    payload = {
        "sub": str(user_id),
        "exp": datetime.utcnow() + timedelta(days=30),
        "type": "access",
        "iat": datetime.utcnow(),
        "username": username
    }
    
    token = jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)
    return token

def print_dev_token():
    """Print a dev token to console"""
    token = create_dev_token()
    print("\n" + "="*50)
    print("🔑 DEVELOPMENT TOKEN")
    print("="*50)
    print(f"Token: {token}")
    print("\n📋 Copy this to use in your frontend:")
    print(f"localStorage.setItem('access_token', '{token}')")
    print("="*50 + "\n")
    return token