from datetime import datetime, timezone, timedelta

def to_local_iso(dt, tz_offset_hours=7):
    if not dt:
        return None
    local_dt = dt.astimezone(timezone(timedelta(hours=tz_offset_hours)))
    return local_dt.isoformat()

