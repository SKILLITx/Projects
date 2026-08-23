"""
Session-token minting, filename sanitisation and optional API-key auth.

Three concrete defects in the previous build are closed here:

1. **Enumerable session identifiers.**  Sessions were the first eight
   characters of a UUID4 — roughly 32 bits of entropy, and possession of an
   identifier was sufficient to download another firm's privileged memorandum.
   Tokens are now 32 URL-safe bytes from :mod:`secrets` (~192 bits).

2. **Path traversal on upload.**  Uploaded files were written to
   ``session_dir / file.filename`` with the client-supplied name used verbatim,
   so a bundle containing ``../../evil.pdf`` escaped the session directory.
   :func:`safe_filename` strips directory components, control characters,
   reserved Windows device names and leading dots, and guarantees a
   non-empty result that stays inside the session folder.

3. **No authentication surface at all.**  :func:`require_api_key` is a FastAPI
   dependency that enforces a constant-time comparison against ``API_KEY``
   when one is configured, and is a no-op when it is not — so a demo run needs
   no credentials while a deployed instance can be locked down by setting a
   single environment variable.
"""

from __future__ import annotations

import hmac
import re
import secrets
import unicodedata
from pathlib import PurePosixPath, PureWindowsPath

from fastapi import Header

from core.config import get_settings
from core.exceptions import AuthenticationError

# Windows reserved device names — creating any of these breaks on NTFS.
_RESERVED_NAMES = {
    "CON", "PRN", "AUX", "NUL",
    *{f"COM{i}" for i in range(1, 10)},
    *{f"LPT{i}" for i in range(1, 10)},
}

_UNSAFE_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
_COLLAPSE_DOTS = re.compile(r"\.{2,}")
_COLLAPSE_SPACE = re.compile(r"\s+")

MAX_FILENAME_LENGTH = 120


def new_session_id() -> str:
    """Return a cryptographically random, URL-safe session identifier."""
    return secrets.token_urlsafe(32)


def new_correlation_id() -> str:
    """Short identifier used to tie log lines to a single request."""
    return secrets.token_hex(6)


def safe_filename(raw: str | None, *, fallback: str = "document.pdf") -> str:
    """
    Reduce a client-supplied filename to a single safe path component.

    Handles POSIX and Windows separators, Unicode normalisation, control
    characters, reserved device names, leading dots and over-long names.
    The result never contains a path separator and is never empty.
    """
    if not raw or not str(raw).strip():
        return fallback

    candidate = unicodedata.normalize("NFKC", str(raw)).strip()

    # Strip any directory component under either path flavour.
    candidate = PureWindowsPath(PurePosixPath(candidate).name).name

    candidate = _UNSAFE_CHARS.sub("_", candidate)
    candidate = _COLLAPSE_DOTS.sub(".", candidate)
    candidate = _COLLAPSE_SPACE.sub(" ", candidate).strip(" .")

    if not candidate:
        return fallback

    stem, dot, suffix = candidate.rpartition(".")
    if not dot:                       # no extension at all
        stem, suffix = candidate, ""
    if stem.upper() in _RESERVED_NAMES:
        stem = f"_{stem}"
    if not stem:
        stem = "document"

    # Preserve the extension while bounding the overall length.
    suffix = suffix[:16]
    budget = MAX_FILENAME_LENGTH - (len(suffix) + 1 if suffix else 0)
    stem = stem[:max(1, budget)]

    return f"{stem}.{suffix}" if suffix else stem


def unique_filename(name: str, taken: set[str]) -> str:
    """Disambiguate a filename against names already used in this bundle."""
    if name not in taken:
        return name
    stem, dot, suffix = name.rpartition(".")
    if not dot:
        stem, suffix = name, ""
    for index in range(2, 1000):
        candidate = f"{stem} ({index}).{suffix}" if suffix else f"{stem} ({index})"
        if candidate not in taken:
            return candidate
    return f"{secrets.token_hex(4)}-{name}"


def verify_api_key(supplied: str | None) -> None:
    """Raise :class:`AuthenticationError` unless the key matches (or auth is off)."""
    settings = get_settings()
    if not settings.auth_enabled:
        return
    if not supplied or not hmac.compare_digest(supplied, settings.api_key):
        raise AuthenticationError()


async def require_api_key(x_api_key: str | None = Header(default=None)) -> None:
    """FastAPI dependency enforcing the optional ``X-API-Key`` header."""
    verify_api_key(x_api_key)
