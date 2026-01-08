from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.schemas.note import NoteCreate, NoteUpdate, NoteOut, ShareNoteRequest, PublicNoteOut, UserResponse
from app.crud.note import (
    create_note, get_notes_by_user, get_note_by_id, 
    update_note, delete_note, toggle_pin_note, archive_note,
    share_note, get_public_note, get_shared_notes, stop_sharing,
    remove_current_user_from_shared_with
)

router = APIRouter(tags=["notes"])

@router.post("", response_model=NoteOut)
def create_new_note(
    note: NoteCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    db_note  = create_note(db, note, current_user.id)

    return NoteOut.from_orm(db_note)

@router.get("", response_model=List[NoteOut])
def get_user_notes(
    archived: Optional[bool] = Query(False, description="Filter by archived status"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        notes = get_notes_by_user(db, current_user.id, archived=archived)
        return notes
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to load notes: {str(e)}")

@router.get("/{note_id}", response_model=NoteOut)
def get_note(
    note_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    note = get_note_by_id(db, note_id, current_user.id)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    return note

@router.put("/{note_id}", response_model=NoteOut)
def update_user_note(
    note_id: int,
    note_update: NoteUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    note = update_note(db, note_id, current_user.id, note_update)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found or no edit permission")
    return note

@router.delete("/{note_id}")
def delete_user_note(
    note_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    success = delete_note(db, note_id, current_user.id)
    if not success:
        raise HTTPException(status_code=404, detail="Note not found")
    return {"message": "Note deleted successfully"}

@router.post("/{note_id}/share", response_model=NoteOut)
def share_note_endpoint(
    note_id: int,
    share_data: ShareNoteRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    note = share_note(db, note_id, current_user.id, share_data)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found or no permission")
    return note

@router.post("/{note_id}/stop-sharing", response_model=NoteOut)
def stop_sharing_endpoint(
    note_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    note = stop_sharing(db, note_id, current_user.id)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    return note

@router.get("/public/{share_token}", response_model=PublicNoteOut)
def get_public_note_endpoint(
    share_token: str,
    db: Session = Depends(get_db)
):
    note = get_public_note(db, share_token)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found or link expired")
    return note

@router.get("/shared/with-me", response_model=List[NoteOut])
def get_notes_shared_with_me(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Get notes that friends have shared with current user"""
    try:
        notes = get_shared_notes(db, current_user.id)
        return notes
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to load shared notes: {str(e)}")

@router.post("/{note_id}/leave", response_model=NoteOut)
def leave_shared_note(
    note_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    note = remove_current_user_from_shared_with(
        db,
        note_id,
        current_user.id
    )

    if not note:
        raise HTTPException(
            status_code=404,
            detail="Note not found or not shared with you"
        )

    return note


@router.get("/{note_id}/share-link")
def get_share_link(
    note_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    note = get_note_by_id(db, note_id, current_user.id)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    
    if note.share_type != "public" or not note.share_token:
        raise HTTPException(status_code=400, detail="Note is not publicly shared")
    
    return {"share_link": f"/notes/public/{note.share_token}"}

@router.post("/{note_id}/pin")
def pin_note(
    note_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    note = toggle_pin_note(db, note_id, current_user.id)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    return {"message": "Note pinned" if note.is_pinned else "Note unpinned"}

@router.post("/{note_id}/archive")
def archive_user_note(
    note_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    note = archive_note(db, note_id, current_user.id)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    return {"message": "Note archived" if note.is_archived else "Note unarchived"}