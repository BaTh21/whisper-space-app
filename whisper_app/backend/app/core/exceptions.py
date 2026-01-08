from fastapi import HTTPException, status

NotFound = lambda detail="Not found": HTTPException(status.HTTP_404_NOT_FOUND, detail)
Unauthorized = lambda detail="Unauthorized": HTTPException(status.HTTP_401_UNAUTHORIZED, detail)
Forbidden = lambda detail="Forbidden": HTTPException(status.HTTP_403_FORBIDDEN, detail)
Conflict = lambda detail="Conflict": HTTPException(status.HTTP_409_CONFLICT, detail)
BadRequest = lambda detail="Bad request": HTTPException(status.HTTP_400_BAD_REQUEST, detail)