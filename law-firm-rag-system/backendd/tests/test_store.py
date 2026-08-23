"""
Session persistence.

These tests pin the durability property the previous build did not have: state
lived in two module-level dictionaries, so a restart or a second worker lost
every in-flight review.
"""

from __future__ import annotations

import threading
import time

from core.store import STAGE_PROGRESS, SessionStore


class TestLifecycle:
    def test_create_and_read_back(self, store):
        store.create("abc123", {"files": ["a.pdf"], "city": "lahore"})
        record = store.get("abc123")
        assert record is not None
        assert record.status == "queued"
        assert record.get("city") == "lahore"

    def test_unknown_session_returns_none(self, store):
        assert store.get("nope") is None
        assert store.get("") is None

    def test_status_transitions_update_progress(self, store):
        store.create("s1", {})
        for stage in ("extracting", "indexing", "analysing", "generating", "complete"):
            store.set_status("s1", stage)
            record = store.get("s1")
            assert record.status == stage
            assert record.progress == STAGE_PROGRESS[stage]

    def test_failure_records_its_reason(self, store):
        store.create("s2", {})
        store.set_status("s2", "failed", error="Groq unreachable")
        record = store.get("s2")
        assert record.is_failed
        assert record.error == "Groq unreachable"
        assert record.progress == 0

    def test_payload_merge_preserves_existing_keys(self, store):
        store.create("s3", {"city": "karachi", "files": ["x.pdf"]})
        store.merge_payload("s3", {"results": {"total_questions": 15}})
        record = store.get("s3")
        assert record.get("city") == "karachi"
        assert record.get("results")["total_questions"] == 15

    def test_merge_on_missing_session_is_a_no_op(self, store):
        store.merge_payload("ghost", {"a": 1})          # must not raise

    def test_delete_removes_the_session(self, store):
        store.create("s4", {})
        assert store.delete("s4") is True
        assert store.get("s4") is None
        assert store.delete("s4") is False


class TestDurability:
    def test_state_survives_a_new_store_instance(self, tmp_path):
        """This is the whole point: a restart must not lose the review."""
        path = tmp_path / "sessions.db"
        first = SessionStore(path)
        first.create("persist-me", {"city": "islamabad"})
        first.set_status("persist-me", "analysing")

        second = SessionStore(path)          # simulates a process restart
        record = second.get("persist-me")
        assert record is not None
        assert record.status == "analysing"
        assert record.get("city") == "islamabad"

    def test_concurrent_writers_do_not_corrupt_state(self, store):
        store.create("hot", {"counter": 0})
        errors: list[Exception] = []

        def worker(index: int) -> None:
            try:
                for _ in range(10):
                    store.merge_payload("hot", {f"key_{index}": index})
                    store.set_status("hot", "analysing")
            except Exception as exc:                 # noqa: BLE001
                errors.append(exc)

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(6)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        assert not errors
        record = store.get("hot")
        assert record is not None
        assert record.status == "analysing"


class TestExpiry:
    def test_expired_sessions_are_hidden_from_reads(self, tmp_path):
        store = SessionStore(tmp_path / "s.db", ttl_hours=1)
        store.create("old", {})
        # Reach past the TTL rather than sleeping for an hour.
        assert store.get("old") is not None
        assert store.expired_ids(now=time.time() + 7200) == ["old"]

    def test_expired_ids_is_empty_when_nothing_has_aged_out(self, store):
        store.create("fresh", {})
        assert store.expired_ids() == []

    def test_stale_running_sessions_are_identified(self, store):
        store.create("stuck", {})
        store.set_status("stuck", "analysing")
        assert "stuck" in store.stale_running_ids(older_than_seconds=-1)

    def test_completed_sessions_are_never_reported_as_stale(self, store):
        store.create("done", {})
        store.set_status("done", "complete")
        assert "done" not in store.stale_running_ids(older_than_seconds=-1)


class TestDiagnostics:
    def test_counts_by_status(self, store):
        store.create("a", {})
        store.create("b", {})
        store.set_status("b", "complete")
        counts = store.counts_by_status()
        assert counts.get("queued") == 1
        assert counts.get("complete") == 1

    def test_total(self, store):
        for index in range(4):
            store.create(f"s{index}", {})
        assert store.total() == 4

    def test_corrupt_payload_degrades_to_empty_dict(self, tmp_path):
        import sqlite3

        path = tmp_path / "s.db"
        store = SessionStore(path)
        store.create("bad", {"a": 1})
        conn = sqlite3.connect(path)
        conn.execute("UPDATE sessions SET payload = 'not json' WHERE id = 'bad';")
        conn.commit()
        conn.close()

        record = store.get("bad")
        assert record is not None
        assert record.payload == {}
