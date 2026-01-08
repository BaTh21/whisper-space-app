from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks, Request
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
import random
from typing import Optional

from app.schemas.base import BaseResponse
from app.schemas.auth import ForgotPasswordRequest, ResetPasswordRequest, Token, UserCreate, UserLogin, VerifyCodeRequest
from app.core.database import get_db
from app.crud.user import get_by_email, create, get_by_email_or_username, verify
from app.crud.auth import create_password_reset_code, create_verification_code, delete_code, delete_reset_code, get_valid_code, get_valid_refresh_token, get_valid_reset_code, revoke_refresh_token, store_refresh_token
from app.services.email import send_password_reset_email, send_verification_email, send_verification_email_sync
from app.core.security import create_access_token, create_refresh_token, get_current_user, verify_password, hash_password
from app.schemas.refresh_token import RefreshTokenRequest
from app.models.user import User
from app.crud.system_log import log_user_activity

router = APIRouter()


@router.post("/refresh", response_model=Token)
def refresh_token(
    req: RefreshTokenRequest,
    request: Request,
    db: Session = Depends(get_db)
):
    rt = get_valid_refresh_token(db, req.refresh_token)
    if not rt:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, 
            detail="Invalid or expired refresh token"
        )

    revoke_refresh_token(db, req.refresh_token)
    new_access = create_access_token(rt.user_id)
    new_refresh = create_refresh_token(rt.user_id)
    store_refresh_token(db, rt.user_id, new_refresh)
    
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")
    log_user_activity(db, rt.user_id, "refresh_token", ip_address, user_agent)

    return Token(
        access_token=new_access, 
        refresh_token=new_refresh,
        token_type="bearer"
    )


@router.post("/register", response_model=BaseResponse)
async def register(
    user_in: UserCreate, 
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db), 
):
    existing_email = db.query(User).filter(User.email == user_in.email).first()
    if existing_email:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, 
            detail="Email already registered"
        )
    
    existing_username = db.query(User).filter(User.username == user_in.username).first()
    if existing_username:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, 
            detail="Username already taken"
        )
    
    code = "".join(random.choices("0123456789", k=6))
    
    new_user = create(db, user_in)
    
    create_verification_code(db, new_user.id, code)
    
    email_sent = False
    try:
        email_sent = send_verification_email_sync(user_in.email, code)
    except Exception:
        background_tasks.add_task(send_verification_email_sync, user_in.email, code)
    
    if email_sent:
        return BaseResponse(
            success=True,
            msg="Verification email sent! Please check your inbox.",
            data={"email": user_in.email}
        )
    else:
        return BaseResponse(
            success=True,
            msg="Registration complete! Check your email for verification code.",
            data={"email": user_in.email}
        )


@router.post("/verify-code", response_model=Token)
def verify_code(
    req: VerifyCodeRequest,
    request: Request,
    db: Session = Depends(get_db)
):
    user = get_by_email(db, req.email)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, 
            detail="User not found"
        )

    code_obj = get_valid_code(db, user.id, req.code)
    if not code_obj:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, 
            detail="Invalid or expired code"
        )

    verify(db, user.id)
    delete_code(db, code_obj.id)
    
    access_token = create_access_token(user.id)
    refresh_token_jwt = create_refresh_token(user.id)
    store_refresh_token(db, user.id, refresh_token_jwt)
    
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")
    log_user_activity(db, user.id, "login", ip_address, user_agent)

    return Token(
        access_token=access_token,
        refresh_token=refresh_token_jwt,
        token_type="bearer"
    )


@router.post("/login", response_model=Token)
def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    request: Request = None,
    db: Session = Depends(get_db)
):
    user = get_by_email_or_username(db, form_data.username)
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials"
        )
    
    if not verify_password(form_data.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials"
        )
    
    if not user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email not verified"
        )

    access_token = create_access_token(user.id)
    refresh_token_jwt = create_refresh_token(user.id)
    store_refresh_token(db, user.id, refresh_token_jwt)
    
    if request:
        ip_address = request.client.host if request.client else None
        user_agent = request.headers.get("user-agent")
        log_user_activity(db, user.id, "login", ip_address, user_agent)
    
    return Token(
        access_token=access_token,
        refresh_token=refresh_token_jwt,
        token_type="bearer"
    )

@router.post("/logout", response_model=BaseResponse)
def logout(
    logout_request: RefreshTokenRequest,  # Use existing RefreshTokenRequest schema
    request: Request,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")
    
    revoke_refresh_token(db, logout_request.refresh_token)
    
    log_user_activity(db, current_user.id, "logout", ip_address, user_agent)
    
    return BaseResponse(
        success=True,
        msg="Logged out successfully"
    )


@router.post("/resend-verification", response_model=BaseResponse)
async def resend_verification(email: str, db: Session = Depends(get_db)):
    user = get_by_email(db, email)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User not found"
        )
    
    if user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already verified"
        )
    
    code = "".join(random.choices("0123456789", k=6))
    create_verification_code(db, user.id, code)
    
    email_sent = await send_verification_email(email, code)
    
    if not email_sent:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to send verification email"
        )
    
    return BaseResponse(msg="Verification code sent")


@router.post("/forgot-password", response_model=BaseResponse)
async def forgot_password(
    req: ForgotPasswordRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    user = get_by_email(db, req.email)
    if not user:
        return BaseResponse(msg="If the email is registered, a reset code has been sent.")

    reset_obj = create_password_reset_code(db, user.id)

    email_sent = await send_password_reset_email(req.email, reset_obj.code)
    if not email_sent:
        background_tasks.add_task(send_password_reset_email, req.email, reset_obj.code)

    return BaseResponse(msg="If the email is registered, a reset code has been sent.")


@router.post("/reset-password", response_model=BaseResponse)
def reset_password(
    req: ResetPasswordRequest,
    db: Session = Depends(get_db)
):
    reset_obj = get_valid_reset_code(db, req.code)
    if not reset_obj:
        raise HTTPException(status_code=400, detail="Invalid or expired reset code")

    user = db.query(User).filter(User.id == reset_obj.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user.password_hash = hash_password(req.new_password)
    db.commit()

    delete_reset_code(db, reset_obj.id)

    return BaseResponse(msg="Password reset successfully. You can now log in.")