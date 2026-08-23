"""
models/schemas.py

Pydantic models used across the ingestion pipeline. Keeping these in one
place gives every router/service a single, typed contract to depend on,
which is critical when several lawyers' documents may be processed
concurrently and metadata must never be mixed up between bundles.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import List, Optional
from uuid import uuid4

from pydantic import BaseModel, Field


class TransactionType(str, Enum):
    PROPERTY = "property"
    LOAN = "loan"
    ACQUISITION = "acquisition"
    UNSPECIFIED = "unspecified"


class PageSource(str, Enum):
    NATIVE_TEXT = "native_text"   # extracted directly from PDF text layer
    OCR = "ocr"                   # extracted via pytesseract after rasterization


class DocumentMetadata(BaseModel):
    """Metadata attached to a single uploaded PDF file."""

    document_id: str = Field(default_factory=lambda: str(uuid4()))
    filename: str
    upload_timestamp: datetime = Field(default_factory=datetime.utcnow)
    transaction_type: TransactionType = TransactionType.UNSPECIFIED
    session_id: str
    total_pages: int = 0
    is_password_protected: bool = False
    is_corrupted: bool = False


class PageContent(BaseModel):
    """Raw extracted content for a single page, before cleaning/chunking."""

    document_id: str
    filename: str
    page_number: int  # 1-indexed, matches what a lawyer sees in Acrobat
    text: str
    source: PageSource
    char_count: int = 0


class ChunkMetadata(BaseModel):
    """Metadata stored alongside every embedded chunk in ChromaDB."""

    chunk_id: str = Field(default_factory=lambda: str(uuid4()))
    document_id: str
    filename: str
    page_number: int
    transaction_type: TransactionType
    session_id: str
    chunk_index: int  # position of this chunk within the document


class Chunk(BaseModel):
    text: str
    metadata: ChunkMetadata


class UploadSessionResult(BaseModel):
    session_id: str
    documents: List[DocumentMetadata]
    total_chunks: int = 0
    collection_name: str
    errors: List[str] = Field(default_factory=list)


class RetrievedChunk(BaseModel):
    rank: int
    similarity_score: float
    filename: str
    page_number: int
    text: str
    document_id: str


class QueryResult(BaseModel):
    query: str
    session_id: str
    results: List[RetrievedChunk]
