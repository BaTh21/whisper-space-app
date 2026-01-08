from sqlalchemy.orm import Session
from sqlalchemy import or_, and_, text
from app.models.note import Note
from app.schemas.note import NoteCreate, NoteUpdate, ShareNoteRequest
from typing import List, Optional
import secrets
from datetime import datetime, timedelta
import json

def create_note(db: Session, note: NoteCreate, user_id: int) -> Note:
    db_note = Note(
        title=note.title,
        content=note.content,
        user_id=user_id,
        is_pinned=note.is_pinned or False,
        is_archived=note.is_archived or False,
        color=note.color or "#ffffff",
        share_type=str(note.share_type.value) if hasattr(note.share_type, 'value') else str(note.share_type),
        shared_with=note.shared_with or [],
        can_edit=note.can_edit or False
    )
    db.add(db_note)
    db.commit()
    db.refresh(db_note)
    return db_note

def get_note_by_id(db: Session, note_id: int, user_id: int) -> Optional[Note]:
    note = db.query(Note).filter(
        Note.id == note_id,
        Note.user_id == user_id
    ).first()
    
    if note:
        return note
    
    shared_note = db.query(Note).filter(
        Note.id == note_id,
        Note.share_type == "shared",
        text(f"shared_with::jsonb @> '[{user_id}]'")
    ).first()
    
    return shared_note

def get_notes_by_user(
    db: Session, 
    user_id: int, 
    skip: int = 0, 
    limit: int = 100,
    archived: bool = False
) -> List[Note]:
    try:
        user_notes = db.query(Note).filter(
            Note.user_id == user_id,
            Note.is_archived == archived
        ).all()
        
        shared_notes = db.query(Note).filter(
            Note.share_type == "shared",
            Note.is_archived == False,  # Don't show archived shared notes
            text(f"shared_with::jsonb @> '[{user_id}]'")
        ).all()
        
        all_notes = user_notes + shared_notes
        all_notes.sort(
            key=lambda x: (
                x.is_pinned,
                x.updated_at or x.created_at
            ),
            reverse=True
        )

        
        return all_notes
        
    except Exception as e:
        print(f"❌ CRUD Error in get_notes_by_user: {str(e)}")
        import traceback
        traceback.print_exc()
        return []

def get_shared_notes(db: Session, user_id: int) -> List[Note]:
    try:
        notes = db.query(Note).filter(
            Note.share_type == "shared",
            Note.user_id != user_id,  # Exclude user's own notes
            Note.is_archived == False,
            text(f"shared_with::jsonb @> '[{user_id}]'")
        ).order_by(Note.updated_at.desc()).all()
        
        return notes
    except Exception as e:
        print(f"❌ CRUD Error in get_shared_notes: {str(e)}")
        return []

def update_note(db: Session, note_id: int, user_id: int, note_update: NoteUpdate) -> Optional[Note]:
    """Update a note - only owner or users with edit permission can update"""
    db_note = get_note_by_id(db, note_id, user_id)
    if not db_note:
        return None
        
    # Check permissions
    if db_note.user_id == user_id:
        # Owner can always edit
        pass
    elif db_note.share_type == "shared" and db_note.can_edit:
        # Check if user is in shared_with array using text query
        shared_note = db.query(Note).filter(
            Note.id == note_id,
            Note.share_type == "shared",
            Note.can_edit == True,
            text(f"shared_with::jsonb @> '[{user_id}]'")
        ).first()
        if not shared_note:
            return None
    else:
        # No permission to edit
        return None
    
    update_data = note_update.dict(exclude_unset=True)
    for field, value in update_data.items():
        setattr(db_note, field, value)
    
    db.commit()
    db.refresh(db_note)
    return db_note

def delete_note(db: Session, note_id: int, user_id: int) -> bool:
    """Delete a note - only owner can delete"""
    db_note = db.query(Note).filter(
        Note.id == note_id,
        Note.user_id == user_id  # Only owner can delete
    ).first()
    
    if db_note:
        db.delete(db_note)
        db.commit()
        return True
    return False

def toggle_pin_note(db: Session, note_id: int, user_id: int) -> Optional[Note]:
    """Toggle pin status - only owner can pin"""
    db_note = db.query(Note).filter(
        Note.id == note_id,
        # Note.user_id == user_id 
    ).first()
    
    if db_note:
        db_note.is_pinned = not db_note.is_pinned
        db.commit()
        db.refresh(db_note)
        return db_note
    return None

def archive_note(db: Session, note_id: int, user_id: int) -> Optional[Note]:
    """Toggle archive status - only owner can archive"""
    db_note = db.query(Note).filter(
        Note.id == note_id,
        Note.user_id == user_id  # Only owner can archive
    ).first()
    
    if db_note:
        db_note.is_archived = not db_note.is_archived
        db.commit()
        db.refresh(db_note)
        return db_note
    return None

def generate_share_token() -> str:
    return secrets.token_urlsafe(32)

def share_note(db: Session, note_id: int, user_id: int, share_data: ShareNoteRequest) -> Optional[Note]:
    """Share a note with friends or make it public"""
    db_note = db.query(Note).filter(
        Note.id == note_id,
        Note.user_id == user_id  # Only owner can share
    ).first()
    
    if not db_note:
        return None
        
    db_note.share_type = share_data.share_type.value if hasattr(share_data.share_type, 'value') else share_data.share_type
    db_note.can_edit = share_data.can_edit
    
    if share_data.share_type == "public":
        db_note.share_token = generate_share_token()
        db_note.shared_with = []
        if share_data.expires_in_hours:
            db_note.share_expires = datetime.utcnow() + timedelta(hours=share_data.expires_in_hours)
        else:
            db_note.share_expires = None
            
    elif share_data.share_type == "shared":
        db_note.shared_with = share_data.friend_ids or []
        db_note.share_token = None
        db_note.share_expires = None
    else:  # PRIVATE
        db_note.shared_with = []
        db_note.share_token = None
        db_note.share_expires = None
        db_note.can_edit = False
        
    db.commit()
    db.refresh(db_note)
    return db_note

def remove_current_user_from_shared_with(
    db: Session,
    note_id: int,
    current_user_id: int
) -> Optional[Note]:
    note = db.query(Note).filter(Note.id == note_id).first()
    if not note:
        return None

    # Owner cannot remove themselves
    if note.user_id == current_user_id:
        return None

    # Only for shared notes
    if note.share_type != "shared":
        return None

    shared_users = note.shared_with or []

    if current_user_id not in shared_users:
        return None

    # Remove user
    note.shared_with = [
        uid for uid in shared_users if uid != current_user_id
    ]

    # Optional: revert to private if no users left
    if not note.shared_with:
        note.share_type = "private"
        note.can_edit = False

    db.commit()
    db.refresh(note)
    return note


def get_public_note(db: Session, share_token: str) -> Optional[Note]:
    """Get a publicly shared note by share token"""
    return db.query(Note).filter(
        Note.share_token == share_token,
        Note.share_type == "public",
        Note.is_archived == False,
        or_(
            Note.share_expires.is_(None),
            Note.share_expires > datetime.utcnow()
        )
    ).first()

def stop_sharing(db: Session, note_id: int, user_id: int) -> Optional[Note]:
    """Stop sharing a note (make it private)"""
    db_note = db.query(Note).filter(
        Note.id == note_id,
        Note.user_id == user_id  # Only owner can stop sharing
    ).first()
    
    if db_note:
        db_note.share_type = "private"
        db_note.share_token = None
        db_note.share_expires = None
        db_note.shared_with = []
        db_note.can_edit = False
        db.commit()
        db.refresh(db_note)
        return db_note
    return None