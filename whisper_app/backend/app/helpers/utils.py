import uuid
from datetime import datetime
from typing import Any

def generate_id() -> str:
    return str(uuid.uuid4())

def now() -> datetime:
    return datetime.utcnow()

def paginate(query, page: int = 1, size: int = 20):
    offset = (page - 1) * size
    total = query.count()
    items = query.offset(offset).limit(size).all()
    pages = (total + size - 1) // size
    return items, total, page, size, pages