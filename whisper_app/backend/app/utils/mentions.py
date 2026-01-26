# In app/utils/mentions.py (create this file)
import re
from typing import List, Set
from sqlalchemy.orm import Session

MENTION_PATTERN = r'@(\w+)'  # Matches @username

def extract_mentions(text: str) -> List[int]:
    """
    Extract mentioned usernames from text
    Returns list of user IDs
    """
    if not text:
        return []
    
    # Find all @mentions
    mentions = re.findall(MENTION_PATTERN, text)
    return list(set(mentions))  # Remove duplicates

def extract_and_validate_mentions(db: Session, text: str) -> Set[int]:
    """
    Extract mentions and validate they exist in database
    Returns set of valid user IDs
    """
    from app.models.user import User
    
    usernames = extract_mentions(text)
    if not usernames:
        return set()
    
    # Find users with these usernames
    users = db.query(User).filter(User.username.in_(usernames)).all()
    return {user.id for user in users}

def format_mention_links(text: str) -> str:
    """
    Convert @mentions to HTML links (for frontend display)
    """
    def replace_mention(match):
        username = match.group(1)
        return f'<a href="/users/{username}" class="mention">@{username}</a>'
    
    return re.sub(MENTION_PATTERN, replace_mention, text)