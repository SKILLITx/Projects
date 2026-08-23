"""
Domain exception taxonomy.

Every failure the system can produce is one of these types.  Each carries an
HTTP status, a stable machine-readable ``code`` that the client can branch on,
and a message written for a lawyer rather than for a log file.  ``main.py``
installs a single handler that renders any of them as a consistent JSON body,
which removes the scattering of bare ``HTTPException(400, "...")`` calls that
made client-side error handling guesswork.
"""

from __future__ import annotations

from typing import Any


class LegalRagError(Exception):
    """Base class for every expected failure in the system."""

    status_code: int = 500
    code: str = "internal_error"
    message: str = "An unexpected error occurred."

    def __init__(self, message: str | None = None, **details: Any) -> None:
        self.message = message or self.__class__.message
        self.details: dict[str, Any] = {k: v for k, v in details.items() if v is not None}
        super().__init__(self.message)

    def to_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {"code": self.code, "message": self.message}
        if self.details:
            payload["details"] = self.details
        return payload


# ── Client-side faults ────────────────────────────────────────────────────
class ValidationError(LegalRagError):
    status_code = 400
    code = "validation_error"
    message = "The request was not valid."


class UnsupportedFileError(ValidationError):
    code = "unsupported_file"
    message = "Only PDF documents are accepted."


class FileTooLargeError(ValidationError):
    code = "file_too_large"
    message = "The uploaded file exceeds the size limit."


class BundleTooLargeError(ValidationError):
    code = "bundle_too_large"
    message = "The uploaded bundle exceeds the total size limit."


class TooManyFilesError(ValidationError):
    code = "too_many_files"
    message = "Too many files in a single upload."


class EmptyUploadError(ValidationError):
    code = "empty_upload"
    message = "No documents were supplied."


class CorruptPdfError(ValidationError):
    code = "corrupt_pdf"
    message = "The file could not be read as a valid PDF."


# ── Authentication ────────────────────────────────────────────────────────
class AuthenticationError(LegalRagError):
    status_code = 401
    code = "unauthenticated"
    message = "A valid API key is required for this request."


# ── Resource state ────────────────────────────────────────────────────────
class SessionNotFoundError(LegalRagError):
    status_code = 404
    code = "session_not_found"
    message = "That review session does not exist or has expired."


class ResultsNotReadyError(LegalRagError):
    status_code = 409
    code = "results_not_ready"
    message = "The review is still running. Poll the status endpoint until it reports 'complete'."


class PipelineFailedError(LegalRagError):
    status_code = 422
    code = "pipeline_failed"
    message = "The review pipeline did not complete successfully."


class ArtefactNotFoundError(LegalRagError):
    status_code = 404
    code = "artefact_not_found"
    message = "The requested document has not been generated for this session."


# ── Dependencies ──────────────────────────────────────────────────────────
class ConfigurationError(LegalRagError):
    status_code = 503
    code = "not_configured"
    message = "The system is missing required configuration."


class OcrUnavailableError(LegalRagError):
    status_code = 503
    code = "ocr_unavailable"
    message = "OCR is required for this document but the OCR toolchain is unavailable."


class LlmUnavailableError(LegalRagError):
    status_code = 503
    code = "llm_unavailable"
    message = "The language model could not be reached after repeated attempts."


class RateLimitedError(LegalRagError):
    status_code = 429
    code = "rate_limited"
    message = "Too many requests. Please retry shortly."
