"""
Rate limiting and retry.

These replace the previous build's ``time.sleep(4)``, which was not adaptive,
did not react to an actual 429, and — being per-loop rather than shared — let
two concurrent reviews breach the provider ceiling while both dutifully slept.
"""

from __future__ import annotations

import random
import threading
import time

import pytest

from core.ratelimit import (
    RateLimitExceeded,
    TokenBucket,
    backoff_delay,
    build_llm_limiter,
    is_transient,
    retry_with_backoff,
    suggested_delay,
)


class TestTokenBucket:
    def test_starts_full(self):
        assert TokenBucket(100, 10).available == pytest.approx(100, abs=1)

    def test_try_acquire_consumes_capacity(self):
        bucket = TokenBucket(10, 1)
        assert bucket.try_acquire(4) is True
        assert bucket.available == pytest.approx(6, abs=0.5)

    def test_try_acquire_fails_when_empty_rather_than_blocking(self):
        bucket = TokenBucket(5, 1)
        assert bucket.try_acquire(5) is True
        assert bucket.try_acquire(1) is False

    def test_refills_over_time(self):
        bucket = TokenBucket(10, refill_per_second=100)
        bucket.try_acquire(10)
        time.sleep(0.05)
        assert bucket.available > 0

    def test_acquire_blocks_until_capacity_is_available(self):
        bucket = TokenBucket(2, refill_per_second=50)
        bucket.acquire(2)
        started = time.monotonic()
        bucket.acquire(1)
        assert time.monotonic() - started >= 0.01

    def test_never_exceeds_capacity_on_refill(self):
        bucket = TokenBucket(10, refill_per_second=1000)
        time.sleep(0.05)
        assert bucket.available <= 10.001

    def test_oversized_request_is_clamped_not_deadlocked(self):
        bucket = TokenBucket(5, refill_per_second=1000)
        bucket.acquire(500)                    # clamped to capacity
        assert bucket.available <= 5

    def test_timeout_raises_rather_than_hanging(self):
        bucket = TokenBucket(1, refill_per_second=0.01)
        bucket.acquire(1)
        with pytest.raises(RateLimitExceeded):
            bucket.acquire(1, timeout=0.05)

    def test_invalid_construction_is_rejected(self):
        with pytest.raises(ValueError):
            TokenBucket(0, 1)
        with pytest.raises(ValueError):
            TokenBucket(1, 0)

    def test_concurrent_consumers_never_overdraw(self):
        """The property the fixed sleep could not provide."""
        bucket = TokenBucket(20, refill_per_second=0.0001)
        granted: list[bool] = []
        lock = threading.Lock()

        def worker() -> None:
            ok = bucket.try_acquire(1)
            with lock:
                granted.append(ok)

        threads = [threading.Thread(target=worker) for _ in range(50)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        assert sum(granted) == 20          # exactly the capacity, never more


class TestCompositeLimiter:
    def test_guards_both_ceilings(self):
        limiter = build_llm_limiter(
            tokens_per_minute=12_000, requests_per_minute=30, est_tokens_per_query=1_600)
        snapshot = limiter.snapshot
        assert "tokens_per_minute" in snapshot
        assert "requests_per_minute" in snapshot

    def test_acquiring_draws_from_both_buckets(self):
        limiter = build_llm_limiter(
            tokens_per_minute=12_000, requests_per_minute=30, est_tokens_per_query=1_600)
        before = limiter.snapshot
        limiter.acquire(token_cost=1_600)
        after = limiter.snapshot
        assert after["tokens_per_minute"] < before["tokens_per_minute"]
        assert after["requests_per_minute"] < before["requests_per_minute"]


class TestTransientDetection:
    @pytest.mark.parametrize("message", [
        "Rate limit reached for model",
        "429 Too Many Requests",
        "Request timed out",
        "503 Service Unavailable",
        "upstream connection reset",
        "The service is temporarily unavailable",
    ])
    def test_transient_conditions_are_recognised(self, message):
        assert is_transient(RuntimeError(message))

    @pytest.mark.parametrize("message", [
        "Invalid API key provided",
        "The model does not exist",
        "Malformed JSON in request body",
        "401 Unauthorized",
    ])
    def test_permanent_failures_are_not_retried(self, message):
        assert not is_transient(RuntimeError(message))

    def test_builtin_transport_errors_are_transient(self):
        assert is_transient(TimeoutError())
        assert is_transient(ConnectionError())

    def test_status_code_attribute_is_honoured(self):
        error = RuntimeError("nope")
        error.status_code = 429
        assert is_transient(error)
        error.status_code = 400
        assert not is_transient(error)


class TestSuggestedDelay:
    def test_reads_a_retry_after_attribute(self):
        error = RuntimeError("slow down")
        error.retry_after = 7.5
        assert suggested_delay(error) == 7.5

    def test_reads_a_retry_after_header(self):
        error = RuntimeError("slow down")
        error.headers = {"retry-after": "12"}
        assert suggested_delay(error) == 12.0

    def test_parses_the_provider_message(self):
        assert suggested_delay(RuntimeError("Please try again in 8.5s")) == 8.5
        assert suggested_delay(RuntimeError("retry after 2 minutes")) == 120.0

    def test_absent_hint_returns_none(self):
        assert suggested_delay(RuntimeError("something else")) is None


class TestBackoff:
    def test_grows_exponentially_without_jitter(self):
        delays = [backoff_delay(i, base=2.0, jitter=False) for i in range(4)]
        assert delays == [2.0, 4.0, 8.0, 16.0]

    def test_is_capped(self):
        assert backoff_delay(20, base=2.0, cap=60.0, jitter=False) == 60.0

    def test_jitter_stays_within_bounds(self):
        rng = random.Random(1234)
        for attempt in range(5):
            ceiling = min(60.0, 2.0 * (2 ** attempt))
            assert 0.0 <= backoff_delay(attempt, base=2.0, rng=rng) <= ceiling


class TestRetryWithBackoff:
    def test_returns_immediately_on_success(self):
        assert retry_with_backoff(lambda: "ok", max_retries=3, base_delay=0.01) == "ok"

    def test_retries_transient_failures_then_succeeds(self):
        attempts = {"count": 0}

        def flaky() -> str:
            attempts["count"] += 1
            if attempts["count"] < 3:
                raise RuntimeError("Rate limit reached")
            return "recovered"

        result = retry_with_backoff(
            flaky, max_retries=5, base_delay=0.001, sleep=lambda _: None)
        assert result == "recovered"
        assert attempts["count"] == 3

    def test_permanent_failure_is_raised_without_retrying(self):
        attempts = {"count": 0}

        def broken() -> None:
            attempts["count"] += 1
            raise ValueError("Invalid API key provided")

        with pytest.raises(ValueError):
            retry_with_backoff(broken, max_retries=5, base_delay=0.001,
                               sleep=lambda _: None)
        assert attempts["count"] == 1          # not retried

    def test_gives_up_after_max_retries(self):
        attempts = {"count": 0}

        def always_fails() -> None:
            attempts["count"] += 1
            raise RuntimeError("429 rate limit")

        with pytest.raises(RuntimeError):
            retry_with_backoff(always_fails, max_retries=2, base_delay=0.001,
                               sleep=lambda _: None)
        assert attempts["count"] == 3          # initial attempt plus two retries

    def test_on_retry_hook_observes_each_attempt(self):
        seen: list[int] = []

        def flaky() -> str:
            if len(seen) < 2:
                raise RuntimeError("timeout")
            return "ok"

        retry_with_backoff(
            flaky, max_retries=4, base_delay=0.001, sleep=lambda _: None,
            on_retry=lambda attempt, delay, exc: seen.append(attempt),
        )
        assert seen == [0, 1]

    def test_provider_supplied_delay_is_honoured(self):
        slept: list[float] = []
        state = {"first": True}

        def flaky() -> str:
            if state["first"]:
                state["first"] = False
                error = RuntimeError("rate limit")
                error.retry_after = 3.0
                raise error
            return "ok"

        retry_with_backoff(flaky, max_retries=2, base_delay=99.0,
                           sleep=slept.append)
        assert slept == [3.0]        # the hint, not the exponential default
