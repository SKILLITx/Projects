"""
Shared token-bucket rate limiter and retry-with-backoff helper.

The previous build paced the checklist with a hard-coded ``time.sleep(4)``
between questions.  That had three problems: it was not adaptive, it did not
react to an actual HTTP 429, and — because it was per-loop rather than shared —
two concurrent reviews could breach the provider ceiling while both dutifully
slept.

This module replaces it with two cooperating primitives:

``TokenBucket``
    A classic continuous-refill bucket, shared process-wide, guarding both the
    tokens-per-minute and requests-per-minute ceilings.  Because capacity is
    reserved before a call rather than slept after one, concurrent workers
    coordinate correctly and the pipeline runs as fast as the ceiling allows
    instead of as slow as the worst case.

``retry_with_backoff``
    Exponential backoff with full jitter, honouring a ``Retry-After`` header
    when the provider supplies one, and retrying only on genuinely transient
    conditions.
"""

from __future__ import annotations

import logging
import random
import re
import threading
import time
from dataclasses import dataclass
from typing import Callable, TypeVar

logger = logging.getLogger(__name__)

T = TypeVar("T")

# Substrings that identify a transient upstream condition worth retrying.
_TRANSIENT_MARKERS = (
    "rate limit", "rate_limit", "ratelimit", "429",
    "timeout", "timed out", "temporarily unavailable",
    "503", "502", "504", "overloaded", "capacity",
    "connection reset", "connection aborted", "connection error",
    "read timeout", "service unavailable", "internal server error", "500",
)

_RETRY_AFTER_PATTERN = re.compile(
    r"(?:retry[-_ ]?after|try again in)\D{0,12}(\d+(?:\.\d+)?)\s*(m?s|s|sec|seconds|m|min)?",
    re.IGNORECASE,
)


class RateLimitExceeded(RuntimeError):
    """Raised when capacity could not be reserved inside the allowed wait."""


@dataclass
class BucketState:
    capacity: float
    tokens: float
    refill_per_second: float
    updated_at: float


class TokenBucket:
    """Thread-safe continuous-refill token bucket."""

    def __init__(self, capacity: float, refill_per_second: float, *, name: str = "bucket") -> None:
        if capacity <= 0:
            raise ValueError("capacity must be positive")
        if refill_per_second <= 0:
            raise ValueError("refill_per_second must be positive")
        self.name = name
        self._lock = threading.Condition()
        self._state = BucketState(
            capacity=float(capacity),
            tokens=float(capacity),
            refill_per_second=float(refill_per_second),
            updated_at=time.monotonic(),
        )

    def _refill_locked(self, now: float) -> None:
        elapsed = max(0.0, now - self._state.updated_at)
        if elapsed:
            self._state.tokens = min(
                self._state.capacity,
                self._state.tokens + elapsed * self._state.refill_per_second,
            )
            self._state.updated_at = now

    @property
    def available(self) -> float:
        with self._lock:
            self._refill_locked(time.monotonic())
            return self._state.tokens

    def try_acquire(self, amount: float = 1.0) -> bool:
        """Reserve capacity without blocking.  Returns False if unavailable."""
        amount = min(float(amount), self._state.capacity)
        with self._lock:
            self._refill_locked(time.monotonic())
            if self._state.tokens >= amount:
                self._state.tokens -= amount
                return True
            return False

    def acquire(self, amount: float = 1.0, *, timeout: float | None = None) -> float:
        """
        Block until ``amount`` capacity is reserved.

        Returns the number of seconds spent waiting.  A request larger than the
        bucket is clamped to the bucket size rather than deadlocking forever.
        """
        amount = min(float(amount), self._state.capacity)
        deadline = None if timeout is None else time.monotonic() + timeout
        waited = 0.0
        with self._lock:
            while True:
                now = time.monotonic()
                self._refill_locked(now)
                if self._state.tokens >= amount:
                    self._state.tokens -= amount
                    if waited > 0.05:
                        logger.debug("%s: waited %.2fs for %.0f units", self.name, waited, amount)
                    return waited
                deficit = amount - self._state.tokens
                sleep_for = deficit / self._state.refill_per_second
                if deadline is not None:
                    remaining = deadline - now
                    if remaining <= 0:
                        raise RateLimitExceeded(
                            f"{self.name}: could not reserve {amount:.0f} units within timeout"
                        )
                    sleep_for = min(sleep_for, remaining)
                sleep_for = max(0.01, min(sleep_for, 5.0))
                self._lock.wait(sleep_for)
                waited += sleep_for


class CompositeLimiter:
    """Guards several ceilings at once — e.g. tokens/min *and* requests/min."""

    def __init__(self, *buckets_with_costs: tuple[TokenBucket, float]) -> None:
        self._pairs = list(buckets_with_costs)

    def acquire(self, *, token_cost: float | None = None, timeout: float | None = None) -> float:
        waited = 0.0
        for bucket, default_cost in self._pairs:
            cost = default_cost if token_cost is None or default_cost <= 1.0 else token_cost
            waited += bucket.acquire(cost, timeout=timeout)
        return waited

    @property
    def snapshot(self) -> dict[str, float]:
        return {bucket.name: round(bucket.available, 1) for bucket, _ in self._pairs}


def build_llm_limiter(
    *, tokens_per_minute: int, requests_per_minute: int, est_tokens_per_query: int
) -> CompositeLimiter:
    """Construct the process-wide limiter used by every LLM call."""
    token_bucket = TokenBucket(
        capacity=max(float(tokens_per_minute), float(est_tokens_per_query)),
        refill_per_second=tokens_per_minute / 60.0,
        name="tokens_per_minute",
    )
    request_bucket = TokenBucket(
        capacity=float(requests_per_minute),
        refill_per_second=requests_per_minute / 60.0,
        name="requests_per_minute",
    )
    return CompositeLimiter(
        (token_bucket, float(est_tokens_per_query)),
        (request_bucket, 1.0),
    )


# ──────────────────────────────────────────────────────────────────────────
#  Retry
# ──────────────────────────────────────────────────────────────────────────
def is_transient(exc: BaseException) -> bool:
    """Whether an exception represents a condition worth retrying."""
    if isinstance(exc, (TimeoutError, ConnectionError, RateLimitExceeded)):
        return True
    status = getattr(exc, "status_code", None) or getattr(exc, "status", None)
    if isinstance(status, int) and (status == 429 or 500 <= status < 600):
        return True
    text = f"{type(exc).__name__}: {exc}".lower()
    return any(marker in text for marker in _TRANSIENT_MARKERS)


def suggested_delay(exc: BaseException) -> float | None:
    """Extract a provider-supplied retry delay, in seconds, when present."""
    for attr in ("retry_after", "retry_after_seconds"):
        value = getattr(exc, attr, None)
        if isinstance(value, (int, float)) and value > 0:
            return float(value)
    headers = getattr(exc, "headers", None)
    if isinstance(headers, dict):
        raw = headers.get("retry-after") or headers.get("Retry-After")
        try:
            if raw is not None:
                return float(raw)
        except (TypeError, ValueError):
            pass
    match = _RETRY_AFTER_PATTERN.search(str(exc))
    if match:
        try:
            value = float(match.group(1))
        except ValueError:
            return None
        unit = (match.group(2) or "s").lower()
        if unit == "ms":
            return value / 1000.0
        if unit in {"m", "min"}:
            return value * 60.0
        return value
    return None


def backoff_delay(attempt: int, *, base: float, cap: float = 60.0,
                  jitter: bool = True, rng: random.Random | None = None) -> float:
    """Exponential backoff with full jitter.  ``attempt`` is zero-based."""
    raw = min(cap, base * (2 ** max(0, attempt)))
    if not jitter:
        return raw
    generator = rng or random
    return generator.uniform(0.0, raw)


def retry_with_backoff(
    operation: Callable[[], T],
    *,
    max_retries: int,
    base_delay: float,
    description: str = "operation",
    sleep: Callable[[float], None] = time.sleep,
    on_retry: Callable[[int, float, BaseException], None] | None = None,
    rng: random.Random | None = None,
) -> T:
    """
    Run ``operation``, retrying transient failures with jittered backoff.

    Non-transient exceptions propagate immediately — retrying a malformed
    prompt or a missing credential simply wastes the provider ceiling.
    """
    attempt = 0
    while True:
        try:
            return operation()
        except Exception as exc:                       # noqa: BLE001 — deliberate boundary
            if attempt >= max_retries or not is_transient(exc):
                raise
            delay = suggested_delay(exc)
            if delay is None:
                delay = backoff_delay(attempt, base=base_delay, rng=rng)
            delay = max(0.0, min(delay, 60.0))
            logger.warning(
                "%s failed (attempt %d/%d): %s — retrying in %.1fs",
                description, attempt + 1, max_retries + 1, exc, delay,
            )
            if on_retry is not None:
                on_retry(attempt, delay, exc)
            sleep(delay)
            attempt += 1
