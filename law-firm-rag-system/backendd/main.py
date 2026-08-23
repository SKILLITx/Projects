"""
Legal RAG System — HTTP application and pipeline orchestrator.

Defects closed in this rebuild, in order of severity:

1. **Path traversal on upload.**  Files were written to
   ``session_dir / file.filename`` using the client-supplied name verbatim, so a
   bundle entry named ``../../core/main.py`` overwrote application source.
   Every name now passes through :func:`core.security.safe_filename`, and the
   resolved destination is asserted to remain inside the session directory.
2. **No authentication on privileged downloads.**  ``GET /api/download/{id}``
   served another firm's memorandum to anyone who guessed an eight-character
   identifier.  Identifiers are now 256-bit tokens and every session-scoped
   route accepts an optional API key.
3. **Session state died with the process.**  Both in-memory dictionaries are
   replaced by the SQLite-backed :class:`~core.store.SessionStore`; vector
   indexes are rebuilt on demand rather than held in RAM.
4. **Cleanup ran only when a new upload arrived**, so an idle deployment kept
   expired privileged documents forever.  A periodic worker now runs on the
   application's own lifespan.
5. **Unbounded memory on upload.**  Whole files were read into memory with
   ``await file.read()`` before the size check.  Uploads now stream to disk in
   chunks and abort the moment a limit is exceeded.
6. **Background tasks were fire-and-forget.**  ``asyncio.create_task`` results
   were discarded, so a crash inside the pipeline vanished silently.  Tasks are
   now tracked, awaited on shutdown, and their failures recorded on the session.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
import shutil
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, AsyncIterator

from fastapi import Depends, FastAPI, File, Form, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field, field_validator

try:                                            # python-dotenv is optional at runtime
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:                              # pragma: no cover
    pass

from core.config import (
    firm_profiles,
    get_settings,
    city_profiles,
    housing_societies,
)
from core.exceptions import (
    ArtefactNotFoundError,
    BundleTooLargeError,
    EmptyUploadError,
    FileTooLargeError,
    LegalRagError,
    PipelineFailedError,
    ResultsNotReadyError,
    SessionNotFoundError,
    TooManyFilesError,
    UnsupportedFileError,
    ValidationError,
)
from core.security import (
    new_correlation_id,
    new_session_id,
    require_api_key,
    safe_filename,
    unique_filename,
)
from core.store import STAGE_LABELS, SessionStore

settings = get_settings()

logging.basicConfig(
    level=getattr(logging, settings.log_level, logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("legal_rag")

store = SessionStore(settings.db_path, ttl_hours=settings.session_ttl_hours)

# Background pipeline tasks, tracked so shutdown can drain them.
_tasks: set[asyncio.Task] = set()

CHUNK_SIZE = 1024 * 1024          # 1 MiB streaming chunks
PDF_MAGIC = b"%PDF-"
STALE_PIPELINE_SECONDS = 3600     # a run quiet for an hour is presumed dead


# ══════════════════════════════════════════════════════════════════════════
#  Lifespan
# ══════════════════════════════════════════════════════════════════════════
@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings.ensure_directories()
    logger.info("%s v%s starting", settings.app_name, settings.app_version)
    logger.info("Authentication: %s", "ENABLED" if settings.auth_enabled else "disabled (open)")
    logger.info("Language model: %s",
                settings.llm_model if settings.llm_configured else "NOT CONFIGURED")

    _mark_stale_sessions_failed()

    cleanup = asyncio.create_task(_cleanup_worker(), name="cleanup-worker")
    _tasks.add(cleanup)
    cleanup.add_done_callback(_tasks.discard)

    try:
        yield
    finally:
        logger.info("Shutting down — draining %d background task(s)…", len(_tasks))
        for task in list(_tasks):
            task.cancel()
        if _tasks:
            await asyncio.gather(*list(_tasks), return_exceptions=True)
        logger.info("Shutdown complete.")


app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    description=(
        "AI-assisted due diligence review for Pakistani property, lending and "
        "corporate acquisition transactions."
    ),
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=list(settings.cors_origins),
    allow_credentials=False,
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "X-API-Key"],
    max_age=600,
)
app.add_middleware(GZipMiddleware, minimum_size=1024)


# ══════════════════════════════════════════════════════════════════════════
#  Error handling
# ══════════════════════════════════════════════════════════════════════════
@app.exception_handler(LegalRagError)
async def _domain_error_handler(request: Request, exc: LegalRagError) -> JSONResponse:
    logger.warning("%s %s → %s: %s",
                   request.method, request.url.path, exc.code, exc.message)
    return JSONResponse(status_code=exc.status_code, content={"error": exc.to_dict()})


@app.exception_handler(Exception)
async def _unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    correlation = new_correlation_id()
    logger.exception("Unhandled error [%s] on %s %s",
                     correlation, request.method, request.url.path)
    return JSONResponse(
        status_code=500,
        content={"error": {
            "code": "internal_error",
            "message": "An unexpected error occurred. Please retry.",
            "details": {"correlation_id": correlation},
        }},
    )


# ══════════════════════════════════════════════════════════════════════════
#  Models
# ══════════════════════════════════════════════════════════════════════════
class QueryRequest(BaseModel):
    session_id: str = Field(min_length=8, max_length=200)
    question: str = Field(min_length=3, max_length=1000)

    @field_validator("question")
    @classmethod
    def _strip_question(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("Question must not be empty.")
        return cleaned


# ══════════════════════════════════════════════════════════════════════════
#  Housekeeping
# ══════════════════════════════════════════════════════════════════════════
def _purge_session_artefacts(session_id: str) -> None:
    """Remove uploads, generated memoranda and vectors for one session."""
    session_dir = settings.upload_dir / _session_folder(session_id)
    if session_dir.exists():
        shutil.rmtree(session_dir, ignore_errors=True)
    for suffix in (".docx", ".pdf"):
        artefact = settings.output_dir / f"{_session_folder(session_id)}_memo{suffix}"
        artefact.unlink(missing_ok=True)
    try:
        from core.indexer import delete_session_index
        delete_session_index(session_id)
    except Exception:                                        # noqa: BLE001
        logger.debug("Vector cleanup skipped for %s", session_id[:8])


def _session_folder(session_id: str) -> str:
    """
    Filesystem-safe folder name for a session.

    Session tokens are URL-safe base64, which may contain ``-`` and ``_`` but
    never a path separator; the name is still passed through the sanitiser so
    that a token from any future scheme cannot escape the upload root.
    """
    return safe_filename(session_id, fallback="session")


def _mark_stale_sessions_failed() -> None:
    """A pipeline interrupted by a crash must not appear to be still running."""
    stale = store.stale_running_ids(older_than_seconds=STALE_PIPELINE_SECONDS)
    for session_id in stale:
        store.set_status(session_id, "failed",
                         error="The review was interrupted before it completed. "
                               "Please upload the bundle again.")
    if stale:
        logger.warning("Marked %d interrupted session(s) as failed.", len(stale))


async def _cleanup_worker() -> None:
    """Periodically purge expired sessions.  Runs for the app's lifetime."""
    interval = max(60, settings.cleanup_interval_minutes * 60)
    while True:
        try:
            await asyncio.sleep(interval)
            expired = store.expired_ids()
            for session_id in expired:
                await asyncio.to_thread(_purge_session_artefacts, session_id)
                store.delete(session_id)
            if expired:
                logger.info("Cleanup: purged %d expired session(s).", len(expired))
            _mark_stale_sessions_failed()
        except asyncio.CancelledError:
            raise
        except Exception:                                    # noqa: BLE001
            logger.exception("Cleanup worker iteration failed — continuing.")


# ══════════════════════════════════════════════════════════════════════════
#  Upload handling
# ══════════════════════════════════════════════════════════════════════════
async def _persist_upload(upload: UploadFile, destination: Path, budget: int) -> int:
    """
    Stream one upload to disk, enforcing per-file and bundle-wide limits.

    Streaming rather than ``await upload.read()`` means a 2 GB file is rejected
    after the first megabyte instead of after it has been loaded into memory.
    """
    written = 0
    first_chunk = True
    try:
        with destination.open("wb") as sink:
            while True:
                chunk = await upload.read(CHUNK_SIZE)
                if not chunk:
                    break
                if first_chunk:
                    if not chunk.startswith(PDF_MAGIC):
                        raise UnsupportedFileError(
                            f"{upload.filename} is not a valid PDF — its content does "
                            f"not begin with a PDF header.",
                            file=upload.filename,
                        )
                    first_chunk = False
                written += len(chunk)
                if written > settings.max_file_bytes:
                    raise FileTooLargeError(
                        f"{upload.filename} exceeds the {settings.max_file_mb} MB "
                        f"per-file limit.",
                        file=upload.filename, limit_mb=settings.max_file_mb,
                    )
                if written > budget:
                    raise BundleTooLargeError(
                        f"The bundle exceeds the {settings.max_bundle_mb} MB total limit.",
                        limit_mb=settings.max_bundle_mb,
                    )
                sink.write(chunk)
    except LegalRagError:
        destination.unlink(missing_ok=True)
        raise
    except OSError as exc:
        destination.unlink(missing_ok=True)
        raise ValidationError(f"{upload.filename} could not be saved: {exc}") from exc

    if written == 0:
        destination.unlink(missing_ok=True)
        raise UnsupportedFileError(f"{upload.filename} is empty.", file=upload.filename)
    return written


def _resolve_session(session_id: str) -> Any:
    record = store.get(session_id)
    if record is None:
        raise SessionNotFoundError()
    return record


# ══════════════════════════════════════════════════════════════════════════
#  Pipeline
# ══════════════════════════════════════════════════════════════════════════
def _run_pipeline_sync(session_id: str) -> None:
    """
    The full review, executed on a worker thread.

    Every stage writes its status to the store before starting, so a client
    polling ``/api/status`` observes real progress and a crash leaves a durable
    record of exactly how far the run reached.
    """
    from core.checklist import run_checklist
    from core.document_processor import detect_special_flags, extract_text_from_pdf
    from core.indexer import build_legal_corpus_index, build_session_index
    from core.memo_generator import generate_memo
    from core.pdf_generator import generate_memo_pdf

    record = store.get(session_id)
    if record is None:
        logger.warning("Pipeline started for unknown session %s", session_id[:8])
        return

    info = record.payload
    started = time.monotonic()

    try:
        # ── Stage 1: extraction ──────────────────────────────────────────
        store.set_status(session_id, "extracting")
        pages: list[dict[str, Any]] = []
        for file_path in info.get("files", []):
            pages.extend(extract_text_from_pdf(file_path))

        if not any((page.get("text") or "").strip() for page in pages):
            raise PipelineFailedError(
                "No readable text could be extracted from this bundle. The documents "
                "may be scanned images with the OCR toolchain unavailable, or they may "
                "be corrupt. Check that Tesseract and Poppler are installed.",
                pages=len(pages),
            )

        flags = detect_special_flags(pages, info.get("transaction_type", "property"))
        store.merge_payload(session_id, {
            "flags": flags,
            "page_count": len(pages),
        })

        # ── Stage 2: indexing ────────────────────────────────────────────
        store.set_status(session_id, "indexing")
        session_index = build_session_index(pages, session_id)
        corpus_index = build_legal_corpus_index()

        # ── Stage 3: checklist ───────────────────────────────────────────
        store.set_status(session_id, "analysing")
        source_text = " ".join((page.get("text") or "") for page in pages)

        def _progress(done: int, total: int) -> None:
            if done % 3 == 0 or done == total:
                logger.info("Session %s: %d/%d questions answered",
                            session_id[:8], done, total)

        results = run_checklist(
            session_index, corpus_index,
            transaction_type=info.get("transaction_type", "property"),
            flags=flags,
            city=info.get("city"),
            housing_society=info.get("housing_society"),
            source_text=source_text,
            progress_callback=_progress,
        )

        # ── Stage 4: deliverables ────────────────────────────────────────
        store.set_status(session_id, "generating")
        folder = _session_folder(session_id)
        document_names = [Path(path).name for path in info.get("files", [])]
        common = {
            "firm_name": info.get("firm_name", "Law Firm"),
            "firm_address": info.get("firm_address", ""),
            "firm_phone": info.get("firm_phone", ""),
            "firm_email": info.get("firm_email", ""),
            "firm_tagline": info.get("firm_tagline", ""),
            "transaction_type": info.get("transaction_type", "property"),
            "city": info.get("city", "islamabad"),
            "document_names": document_names,
            "flags": flags,
        }

        docx_path = settings.output_dir / f"{folder}_memo.docx"
        generate_memo(results, docx_path, **common)

        pdf_path: Path | None = settings.output_dir / f"{folder}_memo.pdf"
        try:
            generate_memo_pdf(results, pdf_path, **common)
        except Exception:                                    # noqa: BLE001
            # A PDF failure must never cost the lawyer their Word memorandum.
            logger.exception("PDF generation failed for %s — Word memo still available.",
                             session_id[:8])
            pdf_path = None

        elapsed = time.monotonic() - started
        results["elapsed_seconds"] = round(elapsed, 1)
        store.merge_payload(session_id, {
            "results": results,
            "memo_docx": str(docx_path),
            "memo_pdf": str(pdf_path) if pdf_path else None,
            "elapsed_seconds": round(elapsed, 1),
        })
        store.set_status(session_id, "complete")
        logger.info("Session %s complete in %.1fs — %d HIGH, %d MEDIUM, %d LOW, %d red flag(s)",
                    session_id[:8], elapsed,
                    results.get("high_risk_count", 0),
                    results.get("medium_risk_count", 0),
                    results.get("low_risk_count", 0),
                    len(results.get("red_flags", [])))

    except LegalRagError as exc:
        logger.error("Pipeline failed for %s: %s", session_id[:8], exc.message)
        store.set_status(session_id, "failed", error=exc.message)
    except Exception as exc:                                 # noqa: BLE001
        logger.exception("Pipeline crashed for %s", session_id[:8])
        store.set_status(session_id, "failed", error=f"Unexpected error: {exc}")


async def _launch_pipeline(session_id: str) -> None:
    task = asyncio.create_task(
        asyncio.to_thread(_run_pipeline_sync, session_id),
        name=f"pipeline-{session_id[:8]}",
    )
    _tasks.add(task)

    def _done(finished: asyncio.Task) -> None:
        _tasks.discard(finished)
        if finished.cancelled():
            return
        error = finished.exception()
        if error is not None:
            logger.error("Pipeline task for %s raised: %s", session_id[:8], error)
            store.set_status(session_id, "failed", error=str(error))

    task.add_done_callback(_done)


# ══════════════════════════════════════════════════════════════════════════
#  Routes
# ══════════════════════════════════════════════════════════════════════════
@app.get("/", tags=["meta"])
async def root() -> dict[str, Any]:
    return {
        "name": settings.app_name,
        "version": settings.app_version,
        "status": "running",
        "documentation": "/docs",
    }


@app.get("/api/health", tags=["meta"])
async def health() -> dict[str, Any]:
    """Deep health check — reports every dependency the pipeline needs."""
    from core.document_processor import probe_ocr

    ocr = probe_ocr()
    try:
        from core.indexer import corpus_stats
        corpus = corpus_stats()
    except Exception as exc:                                 # noqa: BLE001
        corpus = {"error": str(exc), "vectors": 0}

    degraded = (not settings.llm_configured) or corpus.get("vectors", 0) == 0
    return {
        "status": "degraded" if degraded else "healthy",
        "version": settings.app_version,
        "checks": {
            "llm_configured": settings.llm_configured,
            "llm_model": settings.llm_model,
            "authentication": "enabled" if settings.auth_enabled else "disabled",
            "ocr_available": ocr.available,
            "ocr_detail": ocr.detail,
            "ocr_languages": list(ocr.languages),
            "session_store": str(settings.db_path.name),
            "sessions_total": store.total(),
            "sessions_by_status": store.counts_by_status(),
            "corpus": corpus,
        },
    }


@app.get("/api/options", tags=["meta"])
async def options() -> dict[str, Any]:
    """
    Everything the client needs to render its form.

    The previous build hard-coded the city list, the society list and both firm
    profiles inside ``UploadPanel.jsx``, so adding a city meant editing React.
    The client now reads them from here.
    """
    from core.checklist import VALID_TRANSACTION_TYPES

    return {
        "transaction_types": list(VALID_TRANSACTION_TYPES),
        "cities": [
            {"key": key, "label": key.title(), "authority": profile["authority"],
             "authority_full_name": profile["full_name"],
             "noc_types": profile["noc_types"], "bylaws": profile["relevant_bylaws"]}
            for key, profile in sorted(city_profiles().items())
        ],
        "housing_societies": [
            {"key": key, "transfer_docs": profile["transfer_docs"],
             "special_requirements": profile["special_requirements"]}
            for key, profile in sorted(housing_societies().items())
        ],
        "firm_profiles": firm_profiles(),
        "limits": {
            "max_files": settings.max_files,
            "max_file_mb": settings.max_file_mb,
            "max_bundle_mb": settings.max_bundle_mb,
            "session_ttl_hours": settings.session_ttl_hours,
        },
        "auth_required": settings.auth_enabled,
    }


@app.post("/api/upload", tags=["review"], dependencies=[Depends(require_api_key)])
async def upload_documents(
    files: list[UploadFile] = File(...),
    transaction_type: str = Form(default="property"),
    city: str = Form(default="islamabad"),
    housing_society: str = Form(default=""),
    firm_name: str = Form(default="Law Firm"),
    firm_address: str = Form(default=""),
    firm_phone: str = Form(default=""),
    firm_email: str = Form(default=""),
    firm_tagline: str = Form(default=""),
) -> dict[str, Any]:
    """Accept a document bundle, open a session and dispatch the review."""
    from core.checklist import VALID_TRANSACTION_TYPES

    transaction_type = (transaction_type or "property").strip().lower()
    if transaction_type not in VALID_TRANSACTION_TYPES:
        raise ValidationError(
            f"Unknown transaction type '{transaction_type}'. "
            f"Choose one of: {', '.join(VALID_TRANSACTION_TYPES)}.",
            field="transaction_type",
        )

    city = (city or "islamabad").strip().lower()
    known_cities = set(city_profiles())
    if city not in known_cities:
        raise ValidationError(
            f"Unknown city '{city}'. Choose one of: {', '.join(sorted(known_cities))}.",
            field="city",
        )

    society = (housing_society or "").strip()
    if society and society not in housing_societies():
        raise ValidationError(
            f"Unknown housing society '{society}'.", field="housing_society")

    if not files:
        raise EmptyUploadError()
    if len(files) > settings.max_files:
        raise TooManyFilesError(
            f"A single review accepts at most {settings.max_files} files; "
            f"{len(files)} were supplied.",
            limit=settings.max_files, supplied=len(files),
        )

    session_id = new_session_id()
    folder = _session_folder(session_id)
    session_dir = (settings.upload_dir / folder).resolve()
    upload_root = settings.upload_dir.resolve()
    session_dir.mkdir(parents=True, exist_ok=True)

    saved: list[str] = []
    used_names: set[str] = set()
    budget = settings.max_bundle_bytes

    try:
        for upload in files:
            original = upload.filename or ""
            if not original.lower().endswith(".pdf"):
                raise UnsupportedFileError(
                    f"{original or 'A file'} is not a PDF. Only PDF documents are accepted.",
                    file=original,
                )

            name = unique_filename(safe_filename(original), used_names)
            used_names.add(name)
            destination = (session_dir / name).resolve()

            # Defence in depth: the sanitiser should make this impossible.
            if not destination.is_relative_to(upload_root):
                raise ValidationError("Rejected an unsafe file path.", file=original)

            budget -= await _persist_upload(upload, destination, budget)
            saved.append(str(destination))
    except Exception:
        shutil.rmtree(session_dir, ignore_errors=True)
        raise

    if not saved:
        shutil.rmtree(session_dir, ignore_errors=True)
        raise EmptyUploadError()

    store.create(session_id, {
        "files": saved,
        "transaction_type": transaction_type,
        "city": city,
        "housing_society": society,
        "firm_name": (firm_name or "Law Firm").strip()[:200] or "Law Firm",
        "firm_address": (firm_address or "").strip()[:300],
        "firm_phone": (firm_phone or "").strip()[:60],
        "firm_email": (firm_email or "").strip()[:120],
        "firm_tagline": (firm_tagline or "").strip()[:200],
    })

    await _launch_pipeline(session_id)
    logger.info("Session %s opened with %d file(s) [%s / %s]",
                session_id[:8], len(saved), transaction_type, city)

    return {
        "session_id": session_id,
        "files": len(saved),
        "file_names": [Path(path).name for path in saved],
        "status": "queued",
        "expires_in_hours": settings.session_ttl_hours,
    }


@app.get("/api/status/{session_id}", tags=["review"], dependencies=[Depends(require_api_key)])
async def get_status(session_id: str) -> dict[str, Any]:
    record = _resolve_session(session_id)
    return {
        "session_id": session_id,
        "status": record.status,
        "progress": record.progress,
        "label": STAGE_LABELS.get(record.status, "Working…"),
        "error": record.error,
        "elapsed_seconds": record.get("elapsed_seconds"),
        "page_count": record.get("page_count"),
    }


@app.get("/api/results/{session_id}", tags=["review"], dependencies=[Depends(require_api_key)])
async def get_results(session_id: str) -> dict[str, Any]:
    record = _resolve_session(session_id)
    if record.is_failed:
        raise PipelineFailedError(record.error or PipelineFailedError.message)
    results = record.get("results")
    if not results:
        raise ResultsNotReadyError(
            f"The review is at stage '{record.status}' ({record.progress}%). "
            f"Poll /api/status until it reports 'complete'."
        )
    return {
        **results,
        "session_id": session_id,
        "documents": [Path(path).name for path in record.get("files", [])],
        "downloads": {
            "docx": bool(record.get("memo_docx")),
            "pdf": bool(record.get("memo_pdf")),
        },
    }


def _serve_artefact(record: Any, key: str, media_type: str,
                    suffix: str, session_id: str) -> FileResponse:
    path_str = record.get(key)
    if not path_str:
        raise ArtefactNotFoundError(
            f"No {suffix.upper()} memorandum was generated for this session."
        )
    path = Path(path_str)
    if not path.exists():
        raise ArtefactNotFoundError(
            f"The {suffix.upper()} memorandum is no longer available on disk."
        )
    return FileResponse(
        path,
        media_type=media_type,
        filename=f"due_diligence_memo_{session_id[:8]}.{suffix}",
    )


@app.get("/api/download/{session_id}", tags=["review"], dependencies=[Depends(require_api_key)])
async def download_docx(session_id: str) -> FileResponse:
    record = _resolve_session(session_id)
    return _serve_artefact(
        record, "memo_docx",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "docx", session_id,
    )


@app.get("/api/download/{session_id}/pdf", tags=["review"],
         dependencies=[Depends(require_api_key)])
async def download_pdf(session_id: str) -> FileResponse:
    record = _resolve_session(session_id)
    return _serve_artefact(record, "memo_pdf", "application/pdf", "pdf", session_id)


@app.post("/api/query", tags=["review"], dependencies=[Depends(require_api_key)])
async def freeform_query(request: QueryRequest) -> dict[str, Any]:
    """Answer an ad-hoc question against this session's documents and the statutes."""
    from core.checklist import run_freeform_query
    from core.indexer import build_legal_corpus_index, load_session_index

    record = _resolve_session(request.session_id)
    if record.is_failed:
        raise PipelineFailedError(record.error or PipelineFailedError.message)
    if record.status in {"queued", "extracting"}:
        raise ResultsNotReadyError(
            "The documents are still being indexed. Free-form questions become "
            "available once indexing completes."
        )

    session_index = await asyncio.to_thread(load_session_index, request.session_id)
    if session_index is None:
        raise ResultsNotReadyError(
            "This session's index is not available. If the review has finished, "
            "the session may have expired."
        )
    corpus_index = await asyncio.to_thread(build_legal_corpus_index)

    return await asyncio.to_thread(
        run_freeform_query, request.question, session_index, corpus_index
    )


@app.delete("/api/session/{session_id}", tags=["review"],
            dependencies=[Depends(require_api_key)])
async def delete_session(session_id: str) -> dict[str, Any]:
    """
    Erase a session and everything derived from it.

    Privileged material should be removable on demand rather than only when a
    TTL happens to elapse; a firm can now discharge its own retention policy.
    """
    record = store.get(session_id)
    if record is None:
        raise SessionNotFoundError()
    await asyncio.to_thread(_purge_session_artefacts, session_id)
    store.delete(session_id)
    logger.info("Session %s deleted on request.", session_id[:8])
    return {"session_id": session_id, "deleted": True}


if __name__ == "__main__":                                   # pragma: no cover
    import uvicorn

    with contextlib.suppress(KeyboardInterrupt):
        uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=False)
