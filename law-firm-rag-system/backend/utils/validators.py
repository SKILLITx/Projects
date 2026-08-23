"""
utils/validators.py

Pre-flight checks run before a file enters the pipeline. Catching bad
input here means downstream services (OCR, embedding) never have to
defensively re-check the same conditions.
"""

from pathlib import Path

import pikepdf

from config import settings


class UnsupportedFileError(Exception):
    pass


class CorruptedPDFError(Exception):
    pass


class PasswordProtectedPDFError(Exception):
    pass


class FileTooLargeError(Exception):
    pass


def validate_extension(filename: str) -> None:
    suffix = Path(filename).suffix.lower()
    if suffix not in settings.ALLOWED_EXTENSIONS:
        raise UnsupportedFileError(f"'{filename}' has unsupported extension '{suffix}'. Only PDF is supported.")


def validate_size(file_bytes: bytes, filename: str) -> None:
    size_mb = len(file_bytes) / (1024 * 1024)
    if size_mb > settings.MAX_FILE_SIZE_MB:
        raise FileTooLargeError(
            f"'{filename}' is {size_mb:.1f}MB, exceeding the {settings.MAX_FILE_SIZE_MB}MB limit."
        )


def validate_pdf_integrity(file_path: Path) -> None:
    """
    Opens the PDF with pikepdf to detect corruption or password
    protection before any heavier processing (pdfplumber/OCR) is
    attempted.
    """
    try:
        with pikepdf.open(file_path):
            pass
    except pikepdf.PasswordError as exc:
        raise PasswordProtectedPDFError(f"'{file_path.name}' is password protected.") from exc
    except pikepdf.PdfError as exc:
        raise CorruptedPDFError(f"'{file_path.name}' appears to be corrupted: {exc}") from exc
