"""
services/ingestion_service.py

Orchestrates the full Day 2 pipeline for one upload session:
  validate -> extract (native/OCR) -> clean -> chunk -> embed -> store -> index

This is the single place that knows the *order* of operations. Routers
stay thin; individual services stay single-purpose and testable in
isolation.
"""

from pathlib import Path
from typing import List
from uuid import uuid4

from config import settings
from models.schemas import DocumentMetadata, TransactionType, UploadSessionResult
from services.document_processor.chunker import DocumentChunker
from services.document_processor.pdf_extractor import PDFExtractor
from services.llamaindex.index_manager import IndexManager
from utils.logger import get_logger
from utils.validators import (
    CorruptedPDFError,
    FileTooLargeError,
    PasswordProtectedPDFError,
    UnsupportedFileError,
    validate_extension,
    validate_pdf_integrity,
    validate_size,
)

logger = get_logger(__name__)


class IngestionService:
    def __init__(self):
        self.extractor = PDFExtractor()
        self.chunker = DocumentChunker()
        self.index_manager = IndexManager()

    def ingest_bundle(
        self,
        files: List[tuple[str, bytes]],
        transaction_type: TransactionType = TransactionType.UNSPECIFIED,
    ) -> UploadSessionResult:
        """
        files: list of (filename, raw_bytes) tuples, as received from a
        FastAPI UploadFile bundle.
        """
        session_id = str(uuid4())
        session_upload_dir = settings.UPLOAD_DIR / session_id
        session_upload_dir.mkdir(parents=True, exist_ok=True)

        documents: List[DocumentMetadata] = []
        all_chunks = []
        errors: List[str] = []

        logger.info(f"Upload received: session '{session_id}' with {len(files)} file(s).")

        for filename, raw_bytes in files:
            doc_meta = DocumentMetadata(filename=filename, session_id=session_id, transaction_type=transaction_type)
            file_path = session_upload_dir / filename

            try:
                validate_extension(filename)
                validate_size(raw_bytes, filename)
                file_path.write_bytes(raw_bytes)
                validate_pdf_integrity(file_path)

                pages = self.extractor.extract(file_path, document_id=doc_meta.document_id)
                if not pages:
                    errors.append(f"'{filename}': no extractable pages (possibly empty PDF).")
                    continue

                doc_meta.total_pages = len(pages)
                documents.append(doc_meta)

                chunks = self.chunker.chunk_pages(pages, session_id=session_id, transaction_type=transaction_type)
                all_chunks.extend(chunks)

            except (UnsupportedFileError, FileTooLargeError) as exc:
                logger.warning(f"Validation failed for '{filename}': {exc}")
                errors.append(str(exc))
            except PasswordProtectedPDFError as exc:
                logger.warning(f"Password protected: '{filename}': {exc}")
                errors.append(str(exc))
            except CorruptedPDFError as exc:
                logger.warning(f"Corrupted PDF: '{filename}': {exc}")
                errors.append(str(exc))
            except Exception as exc:  # noqa: BLE001 - last-resort guard so one bad file doesn't kill the bundle
                logger.error(f"Unexpected error processing '{filename}': {exc}")
                errors.append(f"'{filename}': unexpected error - {exc}")

        if all_chunks:
            self.index_manager.build_index(session_id=session_id, chunks=all_chunks)
        else:
            logger.warning(f"Session '{session_id}' produced zero chunks; no index created.")

        return UploadSessionResult(
            session_id=session_id,
            documents=documents,
            total_chunks=len(all_chunks),
            collection_name=session_id,
            errors=errors,
        )
