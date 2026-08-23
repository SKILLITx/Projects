"""
services/document_processor/pdf_extractor.py

Responsible for STEP 2 and STEP 3 of Day 2: page-by-page extraction with
automatic native-text-vs-scanned detection. This module never decides
*how* to OCR a page (that's services/ocr) — it only decides *whether*
a page needs OCR, then delegates.

Single Responsibility: extraction + page-level metadata only. No
chunking, no embedding, no cleaning beyond what pdfplumber gives us.
"""

from pathlib import Path
from typing import List

import pdfplumber

from config import settings
from models.schemas import PageContent, PageSource
from services.ocr.ocr_service import OCRService
from utils.logger import get_logger

logger = get_logger(__name__)


class PDFExtractor:
    """Extracts text from a single PDF, falling back to OCR per-page."""

    def __init__(self, ocr_service: OCRService | None = None):
        # Dependency injection: a caller (e.g. tests) can supply a mock
        # OCRService instead of the real pytesseract-backed one.
        self.ocr_service = ocr_service or OCRService()

    def extract(self, pdf_path: Path, document_id: str) -> List[PageContent]:
        pages: List[PageContent] = []

        with pdfplumber.open(pdf_path) as pdf:
            total_pages = len(pdf.pages)
            logger.info(f"Opened '{pdf_path.name}' with {total_pages} page(s) for extraction.")

            for index, page in enumerate(pdf.pages, start=1):
                native_text = (page.extract_text() or "").strip()

                if len(native_text) >= settings.MIN_TEXT_CHARS_PER_PAGE:
                    pages.append(
                        PageContent(
                            document_id=document_id,
                            filename=pdf_path.name,
                            page_number=index,
                            text=native_text,
                            source=PageSource.NATIVE_TEXT,
                            char_count=len(native_text),
                        )
                    )
                else:
                    logger.info(
                        f"Page {index} of '{pdf_path.name}' has insufficient native text "
                        f"({len(native_text)} chars) — falling back to OCR."
                    )
                    ocr_text = self.ocr_service.ocr_single_page(pdf_path, page_number=index)
                    pages.append(
                        PageContent(
                            document_id=document_id,
                            filename=pdf_path.name,
                            page_number=index,
                            text=ocr_text,
                            source=PageSource.OCR,
                            char_count=len(ocr_text),
                        )
                    )

        return pages
