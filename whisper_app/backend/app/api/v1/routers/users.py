from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List
from app.core.database import get_db
from app.core.security import get_current_user
from app.crud.user import search, update, get_friend_suggestions
from app.models.user import User
from app.schemas.user import UserOut, UserUpdate

router = APIRouter()


@router.get("/me", response_model=UserOut)
def get_me(current_user: User = Depends(get_current_user)):
    return UserOut.from_orm(current_user)


@router.put("/me", response_model=UserOut)
def update_me(
    user_in: UserUpdate, 
    db: Session = Depends(get_db), 
    current_user: User = Depends(get_current_user)
):
    updated = update(db, current_user, user_in)
    return UserOut.from_orm(updated)


@router.get("/search", response_model=List[dict])
def search_users(
    q: str = Query(..., min_length=2, description="Search query for users"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Search for users by username or email"""
    try:
        if len(q) < 2:
            return []
            
        # Search in username and email fields
        users = db.query(User).filter(
            (User.username.ilike(f"%{q}%")) | (User.email.ilike(f"%{q}%"))
        ).limit(10).all()
        
        # Return user data with avatar URL
        results = []
        for user in users:
            user_data = {
                "id": user.id,
                "username": user.username,
                "email": user.email,
                "avatar_url": user.avatar_url  # Make sure this is included
            }
            results.append(user_data)
        
        print(f"🔍 Search results for '{q}': {len(results)} users found")
        for user in results:
            print(f"   - {user['username']} (avatar: {user['avatar_url']})")
        
        return results
        
    except Exception as e:
        print(f"❌ Error searching users: {str(e)}")
        import traceback
        traceback.print_exc()
        return []
    
@router.get("/suggestions", response_model=list[UserOut])
def friend_suggestions(
    limit: int = 20,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)  # replace with auth later
):
    return get_friend_suggestions(db, current_user.id, limit)