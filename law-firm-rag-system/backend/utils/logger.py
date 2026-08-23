"""
utils/logger.py

Single logging entry point used by every service. Each pipeline stage
(Upload received, OCR started, Chunking complete, etc.) logs through this
so that a lawyer-facing ops team can audit exactly what happened to a
given document bundle — important for legal defensibility of the review
process itself.
"""

import logging
import sys
from pathlib import Path

from config import settings


def get_logger(name: str) -> logging.Logger:
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger  # already configured, avoid duplicate handlers

    logger.setLevel(logging.INFO)

    formatter = logging.Formatter(
        fmt="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    file_handler = logging.FileHandler(Path(settings.LOG_DIR) / "pipeline.log", encoding="utf-8")
    file_handler.setFormatter(formatter)

    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setFormatter(formatter)

    logger.addHandler(file_handler)
    logger.addHandler(stream_handler)
    return logger
