from loguru import logger
import sys

logger.remove()
logger.add(sys.stdout, level="INFO", format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level}</level> | {message}")

def log_info(msg: str):
    logger.info(msg)

def log_error(msg: str, exc: Exception = None):
    logger.error(msg)
    if exc:
        logger.exception(exc)