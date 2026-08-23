"""
Durable session store backed by SQLite.

The previous build kept sessions in two module-level dictionaries.  A restart,
a crash or a second uvicorn worker destroyed every in-flight review, and the
built ``VectorStoreIndex`` objects held in those dictionaries were unreachable
from any other process — which also foreclosed horizontal scaling.

This module replaces both dictionaries with a WAL-mode SQLite database.  It
ships with Python, needs no daemon, and gives the properties that actually
matter here: durability across restarts, safe concurrent access from multiple
workers, and a queryable expiry index for the cleanup worker.  Vector indexes
are *not* stored — they are rebuilt on demand from the ChromaDB collection that
already persists alongside them.
"""

from __future__ import annotations

import json
import logging
import sqlite3
import threading
import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterator

logger = logging.getLogger(__name__)

SCHEMA_VERSION = 1

_SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
    id            TEXT PRIMARY KEY,
    created_at    REAL    NOT NULL,
    updated_at    REAL    NOT NULL,
    expires_at    REAL    NOT NULL,
    status        TEXT    NOT NULL,
    progress      INTEGER NOT NULL DEFAULT 0,
    error         TEXT,
    payload       TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_expiry ON sessions (expires_at);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions (status);

CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""

# Ordered pipeline stages; progress percentages are derived from this list so
# the client's step indicator and the server can never disagree.
STAGE_SEQUENCE: tuple[str, ...] = (
    "queued", "extracting", "indexing", "analysing", "generating", "complete",
)

STAGE_PROGRESS: dict[str, int] = {
    "queued": 5,
    "extracting": 25,
    "indexing": 45,
    "analysing": 70,
    "generating": 90,
    "complete": 100,
    "failed": 0,
}

STAGE_LABELS: dict[str, str] = {
    "queued": "Documents received and queued for review",
    "extracting": "Extracting text, running OCR on scanned pages, detecting Urdu content",
    "indexing": "Building the multilingual vector index",
    "analysing": "Running the due diligence checklist against your documents and Pakistani statutes",
    "generating": "Assembling the review memorandum",
    "complete": "Review complete",
    "failed": "The review could not be completed",
}

TERMINAL_STAGES = frozenset({"complete", "failed"})


@dataclass
class SessionRecord:
    """A single review session as persisted."""

    id: str
    created_at: float
    updated_at: float
    expires_at: float
    status: str
    progress: int
    error: str | None
    payload: dict[str, Any] = field(default_factory=dict)

    @property
    def is_complete(self) -> bool:
        return self.status == "complete"

    @property
    def is_failed(self) -> bool:
        return self.status == "failed"

    @property
    def stage_label(self) -> str:
        return STAGE_LABELS.get(self.status, "Working…")

    def get(self, key: str, default: Any = None) -> Any:
        return self.payload.get(key, default)


class SessionStore:
    """Thread-safe SQLite-backed session repository."""

    def __init__(self, db_path: Path | str, *, ttl_hours: int = 24) -> None:
        self._path = Path(db_path)
        self._ttl_seconds = max(1, int(ttl_hours)) * 3600
        self._lock = threading.RLock()
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._initialise()

    # ── plumbing ─────────────────────────────────────────────────────────
    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self._path, timeout=30.0, isolation_level=None)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL;")
        conn.execute("PRAGMA synchronous=NORMAL;")
        conn.execute("PRAGMA busy_timeout=30000;")
        conn.execute("PRAGMA foreign_keys=ON;")
        return conn

    @contextmanager
    def _cursor(self) -> Iterator[sqlite3.Cursor]:
        with self._lock:
            conn = self._connect()
            try:
                cur = conn.cursor()
                cur.execute("BEGIN IMMEDIATE;")
                try:
                    yield cur
                    cur.execute("COMMIT;")
                except Exception:
                    cur.execute("ROLLBACK;")
                    raise
            finally:
                conn.close()

    def _initialise(self) -> None:
        with self._lock:
            conn = self._connect()
            try:
                conn.executescript(_SCHEMA)
                conn.execute(
                    "INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', ?);",
                    (str(SCHEMA_VERSION),),
                )
            finally:
                conn.close()
        logger.info("Session store ready at %s (schema v%d)", self._path, SCHEMA_VERSION)

    @staticmethod
    def _row_to_record(row: sqlite3.Row) -> SessionRecord:
        try:
            payload = json.loads(row["payload"])
        except (json.JSONDecodeError, TypeError):
            payload = {}
        return SessionRecord(
            id=row["id"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            expires_at=row["expires_at"],
            status=row["status"],
            progress=row["progress"],
            error=row["error"],
            payload=payload if isinstance(payload, dict) else {},
        )

    # ── public API ───────────────────────────────────────────────────────
    def create(self, session_id: str, payload: dict[str, Any]) -> SessionRecord:
        now = time.time()
        expires = now + self._ttl_seconds
        with self._cursor() as cur:
            cur.execute(
                """INSERT INTO sessions
                   (id, created_at, updated_at, expires_at, status, progress, error, payload)
                   VALUES (?, ?, ?, ?, 'queued', ?, NULL, ?);""",
                (session_id, now, now, expires, STAGE_PROGRESS["queued"],
                 json.dumps(payload, default=str)),
            )
        return SessionRecord(
            id=session_id, created_at=now, updated_at=now, expires_at=expires,
            status="queued", progress=STAGE_PROGRESS["queued"], error=None, payload=payload,
        )

    def get(self, session_id: str) -> SessionRecord | None:
        if not session_id:
            return None
        with self._lock:
            conn = self._connect()
            try:
                row = conn.execute(
                    "SELECT * FROM sessions WHERE id = ?;", (session_id,)
                ).fetchone()
            finally:
                conn.close()
        if row is None:
            return None
        record = self._row_to_record(row)
        if record.expires_at <= time.time():
            logger.info("Session %s requested after expiry — treating as absent.",
                        session_id[:8])
            return None
        return record

    def set_status(self, session_id: str, status: str, *, error: str | None = None) -> None:
        progress = STAGE_PROGRESS.get(status, 0)
        with self._cursor() as cur:
            cur.execute(
                """UPDATE sessions
                      SET status = ?, progress = ?, error = ?, updated_at = ?
                    WHERE id = ?;""",
                (status, progress, error, time.time(), session_id),
            )

    def merge_payload(self, session_id: str, updates: dict[str, Any]) -> None:
        """Read-modify-write the JSON payload inside a single transaction."""
        with self._cursor() as cur:
            row = cur.execute(
                "SELECT payload FROM sessions WHERE id = ?;", (session_id,)
            ).fetchone()
            if row is None:
                return
            try:
                payload = json.loads(row["payload"])
                if not isinstance(payload, dict):
                    payload = {}
            except (json.JSONDecodeError, TypeError):
                payload = {}
            payload.update(updates)
            cur.execute(
                "UPDATE sessions SET payload = ?, updated_at = ? WHERE id = ?;",
                (json.dumps(payload, default=str), time.time(), session_id),
            )

    def delete(self, session_id: str) -> bool:
        with self._cursor() as cur:
            cur.execute("DELETE FROM sessions WHERE id = ?;", (session_id,))
            return cur.rowcount > 0

    def expired_ids(self, *, now: float | None = None) -> list[str]:
        cutoff = now if now is not None else time.time()
        with self._lock:
            conn = self._connect()
            try:
                rows = conn.execute(
                    "SELECT id FROM sessions WHERE expires_at <= ?;", (cutoff,)
                ).fetchall()
            finally:
                conn.close()
        return [row["id"] for row in rows]

    def stale_running_ids(self, *, older_than_seconds: float) -> list[str]:
        """Sessions left mid-pipeline by a crash, so they can be marked failed."""
        cutoff = time.time() - float(older_than_seconds)
        placeholders = ",".join("?" for _ in TERMINAL_STAGES)
        with self._lock:
            conn = self._connect()
            try:
                rows = conn.execute(
                    f"SELECT id FROM sessions "
                    f"WHERE updated_at < ? AND status NOT IN ({placeholders});",
                    (cutoff, *sorted(TERMINAL_STAGES)),
                ).fetchall()
            finally:
                conn.close()
        return [row["id"] for row in rows]

    def counts_by_status(self) -> dict[str, int]:
        with self._lock:
            conn = self._connect()
            try:
                rows = conn.execute(
                    "SELECT status, COUNT(*) AS n FROM sessions GROUP BY status;"
                ).fetchall()
            finally:
                conn.close()
        return {row["status"]: row["n"] for row in rows}

    def total(self) -> int:
        with self._lock:
            conn = self._connect()
            try:
                row = conn.execute("SELECT COUNT(*) AS n FROM sessions;").fetchone()
            finally:
                conn.close()
        return int(row["n"]) if row else 0
