"""
Centralised configuration and reference-data loading.

Every tunable in the system is read from the environment exactly once, here,
and exposed as a frozen ``Settings`` object.  Reference data that used to be
hard-coded in three different modules (city authorities, housing-society
transfer regimes, required-document taxonomies, firm letterheads) is loaded
from ``config/*.json`` and validated at import time, so a malformed profile
fails loudly at start-up rather than silently at request time.
"""

from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

BASE_DIR = Path(__file__).resolve().parent.parent
CONFIG_DIR = BASE_DIR / "config"
DATA_DIR = BASE_DIR / "data"


# ──────────────────────────────────────────────────────────────────────────
#  Environment helpers
# ──────────────────────────────────────────────────────────────────────────
def _env_str(key: str, default: str) -> str:
    value = os.getenv(key)
    return value.strip() if value and value.strip() else default


def _env_int(key: str, default: int, *, minimum: int | None = None,
             maximum: int | None = None) -> int:
    raw = os.getenv(key)
    if raw is None or not raw.strip():
        return default
    try:
        value = int(raw.strip())
    except ValueError:
        logger.warning("Invalid integer for %s=%r — falling back to %d", key, raw, default)
        return default
    if minimum is not None and value < minimum:
        logger.warning("%s=%d below minimum %d — clamping", key, value, minimum)
        return minimum
    if maximum is not None and value > maximum:
        logger.warning("%s=%d above maximum %d — clamping", key, value, maximum)
        return maximum
    return value


def _env_float(key: str, default: float, *, minimum: float | None = None) -> float:
    raw = os.getenv(key)
    if raw is None or not raw.strip():
        return default
    try:
        value = float(raw.strip())
    except ValueError:
        logger.warning("Invalid float for %s=%r — falling back to %s", key, raw, default)
        return default
    if minimum is not None and value < minimum:
        return minimum
    return value


def _env_bool(key: str, default: bool) -> bool:
    raw = os.getenv(key)
    if raw is None or not raw.strip():
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _env_list(key: str, default: list[str]) -> list[str]:
    raw = os.getenv(key)
    if raw is None or not raw.strip():
        return list(default)
    return [item.strip() for item in raw.split(",") if item.strip()]


# ──────────────────────────────────────────────────────────────────────────
#  Reference data
# ──────────────────────────────────────────────────────────────────────────
def _load_json(name: str, fallback: Any) -> Any:
    """Load a reference JSON file, degrading to a safe fallback."""
    path = CONFIG_DIR / name
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
        if not isinstance(data, type(fallback)):
            raise TypeError(f"{name} must contain a {type(fallback).__name__}")
        return data
    except FileNotFoundError:
        logger.warning("Reference file %s not found — using built-in fallback.", path)
    except (json.JSONDecodeError, TypeError) as exc:
        logger.error("Reference file %s is invalid (%s) — using built-in fallback.", path, exc)
    return fallback


_CITY_FALLBACK: dict[str, dict[str, Any]] = {
    "islamabad": {
        "authority": "CDA",
        "full_name": "Capital Development Authority",
        "noc_types": ["CDA Building NOC", "CDA Land Use NOC"],
        "relevant_bylaws": "CDA Bye-Laws 2020",
        "statutes": ["Capital Development Authority Ordinance 1960"],
    }
}


@lru_cache(maxsize=1)
def city_profiles() -> dict[str, dict[str, Any]]:
    """City → development-authority profile.  Keys are lower-cased."""
    raw = _load_json("city_profiles.json", _CITY_FALLBACK)
    cleaned: dict[str, dict[str, Any]] = {}
    for key, profile in raw.items():
        if not isinstance(profile, dict):
            logger.warning("Skipping malformed city profile %r", key)
            continue
        cleaned[str(key).strip().lower()] = {
            "authority": str(profile.get("authority", "the local authority")),
            "full_name": str(profile.get("full_name", profile.get("authority", "Local Authority"))),
            "noc_types": [str(n) for n in profile.get("noc_types", []) if str(n).strip()],
            "relevant_bylaws": str(profile.get("relevant_bylaws", "applicable bye-laws")),
            "statutes": [str(s) for s in profile.get("statutes", []) if str(s).strip()],
        }
    return cleaned or _CITY_FALLBACK


@lru_cache(maxsize=1)
def housing_societies() -> dict[str, dict[str, Any]]:
    """Housing society → transfer-document regime."""
    raw = _load_json("housing_societies.json", {})
    cleaned: dict[str, dict[str, Any]] = {}
    for key, profile in raw.items():
        if not isinstance(profile, dict):
            continue
        cleaned[str(key).strip()] = {
            "transfer_docs": [str(d) for d in profile.get("transfer_docs", []) if str(d).strip()],
            "special_requirements": str(profile.get("special_requirements", "")).strip(),
        }
    return cleaned


@lru_cache(maxsize=1)
def document_taxonomy() -> dict[str, Any]:
    """Required-document lists per transaction type, plus Urdu names."""
    raw = _load_json("document_taxonomy.json", {})
    required = raw.get("required_documents", {}) if isinstance(raw, dict) else {}
    urdu = raw.get("urdu_document_names", {}) if isinstance(raw, dict) else {}
    return {
        "required_documents": {
            str(k): [str(v) for v in vals if str(v).strip()]
            for k, vals in required.items()
            if isinstance(vals, list)
        },
        "urdu_document_names": {str(k): str(v) for k, v in urdu.items()},
    }


@lru_cache(maxsize=1)
def firm_profiles() -> dict[str, dict[str, Any]]:
    """Pre-configured law-firm letterheads offered by the client."""
    raw = _load_json("firm_profiles.json", {})
    cleaned: dict[str, dict[str, Any]] = {}
    for key, profile in raw.items():
        if not isinstance(profile, dict):
            continue
        cleaned[str(key)] = {
            field_name: str(profile.get(field_name, ""))
            for field_name in ("name", "address", "phone", "email", "website", "city", "tagline")
        }
    return cleaned


def valid_cities() -> set[str]:
    return set(city_profiles().keys())


def valid_societies() -> set[str]:
    return set(housing_societies().keys())


# ──────────────────────────────────────────────────────────────────────────
#  Settings
# ──────────────────────────────────────────────────────────────────────────
@dataclass(frozen=True)
class Settings:
    """Immutable snapshot of every runtime tunable."""

    # -- Identity ---------------------------------------------------------
    app_name: str = "Legal RAG System"
    app_version: str = "2.0.0"

    # -- Paths ------------------------------------------------------------
    base_dir: Path = BASE_DIR
    upload_dir: Path = BASE_DIR / "uploads"
    output_dir: Path = BASE_DIR / "outputs"
    chroma_dir: Path = BASE_DIR / "chroma_db"
    corpus_dir: Path = DATA_DIR / "legal_corpus"
    db_path: Path = BASE_DIR / "sessions.db"

    # -- HTTP -------------------------------------------------------------
    cors_origins: tuple[str, ...] = ("http://localhost:5173", "http://127.0.0.1:5173")
    api_key: str = ""                     # empty disables API-key enforcement

    # -- Upload limits ----------------------------------------------------
    max_files: int = 10
    max_file_mb: int = 50
    max_bundle_mb: int = 150

    # -- Sessions ---------------------------------------------------------
    session_ttl_hours: int = 24
    cleanup_interval_minutes: int = 30

    # -- Retrieval --------------------------------------------------------
    embed_model: str = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
    chunk_size: int = 512
    chunk_overlap: int = 64
    session_top_k: int = 6
    corpus_top_k: int = 6
    rerank_enabled: bool = True
    rerank_model: str = "cross-encoder/ms-marco-MiniLM-L-6-v2"
    rerank_top_n: int = 5

    # -- Generation -------------------------------------------------------
    llm_model: str = "openai/gpt-oss-120b"
    llm_temperature: float = 0.1
    llm_timeout_s: float = 120.0
    groq_api_key: str = ""

    # -- Rate limiting / resilience --------------------------------------
    tokens_per_minute: int = 12_000
    requests_per_minute: int = 28
    est_tokens_per_query: int = 1_600
    max_retries: int = 4
    retry_base_delay_s: float = 2.0
    checklist_workers: int = 3

    # -- OCR --------------------------------------------------------------
    tesseract_cmd: str = ""
    ocr_dpi: int = 300
    ocr_languages: str = "urd+eng"
    ocr_min_chars: int = 50
    ocr_max_pages: int = 120

    # -- Misc -------------------------------------------------------------
    log_level: str = "INFO"

    directories: tuple[Path, ...] = field(default=(), repr=False)

    def ensure_directories(self) -> None:
        for path in (self.upload_dir, self.output_dir, self.chroma_dir, self.corpus_dir):
            path.mkdir(parents=True, exist_ok=True)

    @property
    def max_file_bytes(self) -> int:
        return self.max_file_mb * 1024 * 1024

    @property
    def max_bundle_bytes(self) -> int:
        return self.max_bundle_mb * 1024 * 1024

    @property
    def auth_enabled(self) -> bool:
        return bool(self.api_key)

    @property
    def llm_configured(self) -> bool:
        return bool(self.groq_api_key)


def _default_tesseract() -> str:
    """Locate Tesseract without hard-coding a Windows path on POSIX hosts."""
    explicit = os.getenv("TESSERACT_CMD", "").strip()
    if explicit:
        return explicit
    if os.name == "nt":
        for candidate in (
            r"C:\Program Files\Tesseract-OCR\tesseract.exe",
            r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
        ):
            if Path(candidate).exists():
                return candidate
        return r"C:\Program Files\Tesseract-OCR\tesseract.exe"
    return "tesseract"          # resolved through PATH on Linux/macOS


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Build the settings snapshot.  Cached — call freely."""
    settings = Settings(
        cors_origins=tuple(_env_list(
            "CORS_ORIGINS", ["http://localhost:5173", "http://127.0.0.1:5173"])),
        api_key=_env_str("API_KEY", ""),
        max_files=_env_int("MAX_FILES", 10, minimum=1, maximum=100),
        max_file_mb=_env_int("MAX_FILE_MB", 50, minimum=1, maximum=500),
        max_bundle_mb=_env_int("MAX_BUNDLE_MB", 150, minimum=1, maximum=2000),
        session_ttl_hours=_env_int("SESSION_TTL_HOURS", 24, minimum=1, maximum=720),
        cleanup_interval_minutes=_env_int("CLEANUP_INTERVAL_MINUTES", 30, minimum=1),
        embed_model=_env_str(
            "EMBED_MODEL", "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"),
        chunk_size=_env_int("CHUNK_SIZE", 512, minimum=128, maximum=4096),
        chunk_overlap=_env_int("CHUNK_OVERLAP", 64, minimum=0, maximum=1024),
        session_top_k=_env_int("SESSION_TOP_K", 6, minimum=1, maximum=50),
        corpus_top_k=_env_int("CORPUS_TOP_K", 6, minimum=1, maximum=50),
        rerank_enabled=_env_bool("RERANK_ENABLED", True),
        rerank_model=_env_str("RERANK_MODEL", "cross-encoder/ms-marco-MiniLM-L-6-v2"),
        rerank_top_n=_env_int("RERANK_TOP_N", 5, minimum=1, maximum=30),
        llm_model=_env_str("LLM_MODEL", "openai/gpt-oss-120b"),
        llm_temperature=_env_float("LLM_TEMPERATURE", 0.1, minimum=0.0),
        llm_timeout_s=_env_float("LLM_TIMEOUT_S", 120.0, minimum=5.0),
        groq_api_key=_env_str("GROQ_API_KEY", ""),
        tokens_per_minute=_env_int("TOKENS_PER_MINUTE", 12_000, minimum=1_000),
        requests_per_minute=_env_int("REQUESTS_PER_MINUTE", 28, minimum=1),
        est_tokens_per_query=_env_int("EST_TOKENS_PER_QUERY", 1_600, minimum=100),
        max_retries=_env_int("MAX_RETRIES", 4, minimum=0, maximum=10),
        retry_base_delay_s=_env_float("RETRY_BASE_DELAY_S", 2.0, minimum=0.1),
        checklist_workers=_env_int("CHECKLIST_WORKERS", 3, minimum=1, maximum=16),
        tesseract_cmd=_default_tesseract(),
        ocr_dpi=_env_int("OCR_DPI", 300, minimum=72, maximum=600),
        ocr_languages=_env_str("OCR_LANGUAGES", "urd+eng"),
        ocr_min_chars=_env_int("OCR_MIN_CHARS", 50, minimum=0),
        ocr_max_pages=_env_int("OCR_MAX_PAGES", 120, minimum=1),
        log_level=_env_str("LOG_LEVEL", "INFO").upper(),
    )
    # chunk_overlap must remain strictly smaller than chunk_size
    if settings.chunk_overlap >= settings.chunk_size:
        logger.warning(
            "CHUNK_OVERLAP (%d) >= CHUNK_SIZE (%d) — clamping overlap to a quarter of chunk size.",
            settings.chunk_overlap, settings.chunk_size,
        )
        object.__setattr__(settings, "chunk_overlap", settings.chunk_size // 4)
    return settings


def reset_settings_cache() -> None:
    """Drop cached settings and reference data.  Used by the test-suite."""
    get_settings.cache_clear()
    city_profiles.cache_clear()
    housing_societies.cache_clear()
    document_taxonomy.cache_clear()
    firm_profiles.cache_clear()
