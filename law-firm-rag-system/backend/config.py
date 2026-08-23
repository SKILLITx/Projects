"""
config.py

Central configuration for the Legal Due Diligence ingestion pipeline.
All paths, model names, and tunables live here so that no other module
hardcodes a magic string. This keeps the system easy to re-tune for a
specific law firm's document set without touching business logic.
"""

from pathlib import Path
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # --- Filesystem layout ---
    BASE_DIR: Path = Path(__file__).resolve().parent
    UPLOAD_DIR: Path = BASE_DIR / "uploads"
    INDEX_DIR: Path = BASE_DIR / "indexes"
    LOG_DIR: Path = BASE_DIR / "logs"

    # --- Chunking (LlamaIndex SentenceSplitter) ---
    CHUNK_SIZE: int = 512
    CHUNK_OVERLAP: int = 50

    # --- Embedding model (local, no API calls) ---
    EMBEDDING_MODEL_NAME: str = "sentence-transformers/all-MiniLM-L6-v2"

    # --- OCR ---
    OCR_LANGUAGES: str = "eng+urd"  # English + Urdu (requires tesseract-ocr-urd)
    OCR_DPI: int = 300
    MIN_TEXT_CHARS_PER_PAGE: int = 20  # below this -> treat page as scanned, trigger OCR

    # --- Uploads ---
    MAX_FILE_SIZE_MB: int = 100
    ALLOWED_EXTENSIONS: tuple = (".pdf",)

    # --- ChromaDB ---
    CHROMA_PERSIST_DIR: Path = BASE_DIR / "indexes" / "chroma"

    class Config:
        env_file = ".env"


settings = Settings()

# Ensure required directories exist at import time.
for directory in (settings.UPLOAD_DIR, settings.INDEX_DIR, settings.LOG_DIR, settings.CHROMA_PERSIST_DIR):
    directory.mkdir(parents=True, exist_ok=True)
