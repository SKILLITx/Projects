"""
services/ocr/ocr_service.py

Automatic OCR fallback (STEP 2). Rasterizes a single page with
pdf2image, then runs pytesseract with combined English+Urdu language
data — Pakistani legal documents routinely mix both scripts in the
same clause.

This is invoked transparently by PDFExtractor; no manual selection by
the user is required or supported, per the Day 2 spec.
"""

from pathlib import Path

import pytesseract
from pdf2image import convert_from_path
from pytesseract import TesseractNotFoundError

from config import settings
from utils.logger import get_logger
from utils.text_cleaning import remove_ocr_artifacts

logger = get_logger(__name__)


class MissingOCRExecutableError(Exception):
    """Raised when the tesseract binary is not installed on the host."""


class OCRService:
    def __init__(self, languages: str = settings.OCR_LANGUAGES, dpi: int = settings.OCR_DPI):
        self.languages = languages
        self.dpi = dpi

    def ocr_single_page(self, pdf_path: Path, page_number: int) -> str:
        """
        page_number is 1-indexed to match how it is presented everywhere
        else in the system (and how a lawyer would reference it).
        """
        logger.info(f"OCR started for '{pdf_path.name}' page {page_number}.")
        try:
            images = convert_from_path(
                str(pdf_path),
                dpi=self.dpi,
                first_page=page_number,
                last_page=page_number,
            )
        except Exception as exc:
            logger.error(f"pdf2image failed to rasterize page {page_number} of '{pdf_path.name}': {exc}")
            return ""

        if not images:
            logger.warning(f"No image produced for page {page_number} of '{pdf_path.name}'.")
            return ""

        try:
            raw_text = pytesseract.image_to_string(images[0], lang=self.languages)
        except TesseractNotFoundError as exc:
            raise MissingOCRExecutableError(
                "Tesseract binary not found. Install it via "
                "'apt-get install tesseract-ocr tesseract-ocr-urd'."
            ) from exc

        cleaned = remove_ocr_artifacts(raw_text)
        logger.info(f"OCR completed for '{pdf_path.name}' page {page_number} ({len(cleaned)} chars).")
        return cleaned.strip()
