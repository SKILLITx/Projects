"""
HTTP surface tests.

The pipeline is stubbed out so these run without a Groq key, a GPU or a
network: what is under test is the contract — validation, error taxonomy,
authentication and the upload path — not the model.
"""

from __future__ import annotations

import io

import pytest

pytest.importorskip("fastapi")
pytest.importorskip("httpx")

from fastapi.testclient import TestClient          # noqa: E402

MINIMAL_PDF = (
    b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
    b"2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
    b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>endobj\n"
    b"trailer<</Root 1 0 R>>\n%%EOF\n"
)


@pytest.fixture
def client(monkeypatch, tmp_path):
    """A TestClient whose pipeline is replaced by a no-op."""
    monkeypatch.setenv("MAX_FILES", "3")
    monkeypatch.setenv("MAX_FILE_MB", "1")

    from core.config import get_settings, reset_settings_cache

    reset_settings_cache()
    settings = get_settings()
    object.__setattr__(settings, "upload_dir", tmp_path / "uploads")
    object.__setattr__(settings, "output_dir", tmp_path / "outputs")
    object.__setattr__(settings, "db_path", tmp_path / "sessions.db")
    settings.ensure_directories()

    import importlib

    import main as main_module

    importlib.reload(main_module)

    async def _no_pipeline(session_id: str) -> None:
        return None

    monkeypatch.setattr(main_module, "_launch_pipeline", _no_pipeline)

    with TestClient(main_module.app) as test_client:
        test_client.store = main_module.store          # type: ignore[attr-defined]
        yield test_client


def _upload(client, *, files=None, **form):
    payload = files or [("files", ("deed.pdf", io.BytesIO(MINIMAL_PDF), "application/pdf"))]
    data = {"transaction_type": "property", "city": "islamabad", **form}
    return client.post("/api/upload", files=payload, data=data)


class TestMetaEndpoints:
    def test_root(self, client):
        response = client.get("/")
        assert response.status_code == 200
        assert response.json()["status"] == "running"

    def test_health_reports_every_dependency(self, client):
        body = client.get("/api/health").json()
        assert body["status"] in {"healthy", "degraded"}
        for key in ("llm_configured", "ocr_available", "authentication",
                    "sessions_total", "corpus"):
            assert key in body["checks"]

    def test_options_exposes_the_configuration_the_client_needs(self, client):
        body = client.get("/api/options").json()
        assert set(body["transaction_types"]) == {"property", "loan", "acquisition"}
        assert any(city["key"] == "karachi" for city in body["cities"])
        assert any(city["authority"] == "SBCA" for city in body["cities"])
        assert body["housing_societies"]
        assert body["limits"]["max_files"] == 3

    def test_openapi_schema_is_served(self, client):
        assert client.get("/openapi.json").status_code == 200


class TestUploadValidation:
    def test_valid_upload_opens_a_session(self, client):
        response = _upload(client)
        assert response.status_code == 200
        body = response.json()
        assert len(body["session_id"]) >= 40          # not an 8-char UUID slice
        assert body["files"] == 1

    def test_non_pdf_extension_is_rejected(self, client):
        response = _upload(client, files=[
            ("files", ("notes.txt", io.BytesIO(b"hello"), "text/plain"))])
        assert response.status_code == 400
        assert response.json()["error"]["code"] == "unsupported_file"

    def test_pdf_extension_with_wrong_content_is_rejected(self, client):
        """Extension checking alone was never sufficient."""
        response = _upload(client, files=[
            ("files", ("fake.pdf", io.BytesIO(b"PK\x03\x04 not a pdf"),
                       "application/pdf"))])
        assert response.status_code == 400
        assert response.json()["error"]["code"] == "unsupported_file"

    def test_empty_file_is_rejected(self, client):
        response = _upload(client, files=[
            ("files", ("empty.pdf", io.BytesIO(b""), "application/pdf"))])
        assert response.status_code == 400

    def test_too_many_files_is_rejected(self, client):
        payload = [("files", (f"deed{i}.pdf", io.BytesIO(MINIMAL_PDF), "application/pdf"))
                   for i in range(5)]
        response = _upload(client, files=payload)
        assert response.status_code == 400
        assert response.json()["error"]["code"] == "too_many_files"

    def test_oversized_file_is_rejected(self, client):
        big = MINIMAL_PDF + b"0" * (2 * 1024 * 1024)
        response = _upload(client, files=[
            ("files", ("big.pdf", io.BytesIO(big), "application/pdf"))])
        assert response.status_code == 400
        assert response.json()["error"]["code"] in {"file_too_large", "bundle_too_large"}

    def test_unknown_transaction_type_is_rejected(self, client):
        response = _upload(client, transaction_type="spaceship")
        assert response.status_code == 400
        assert "spaceship" in response.json()["error"]["message"]

    def test_unknown_city_is_rejected(self, client):
        response = _upload(client, city="atlantis")
        assert response.status_code == 400

    def test_unknown_housing_society_is_rejected(self, client):
        response = _upload(client, housing_society="Nowhere Gardens")
        assert response.status_code == 400


class TestPathTraversal:
    """The vulnerability that shipped: filenames were used verbatim."""

    @pytest.mark.parametrize("malicious", [
        "../../../escaped.pdf",
        "..\\..\\..\\escaped.pdf",
        "/etc/passwd.pdf",
        "....//....//escaped.pdf",
    ])
    def test_malicious_names_stay_inside_the_session_directory(self, client, malicious):
        response = _upload(client, files=[
            ("files", (malicious, io.BytesIO(MINIMAL_PDF), "application/pdf"))])
        assert response.status_code == 200

        from core.config import get_settings

        upload_root = get_settings().upload_dir.resolve()
        written = list(upload_root.rglob("*.pdf"))
        assert written, "the file should have been saved somewhere"
        for path in written:
            assert path.resolve().is_relative_to(upload_root)

    def test_sanitised_name_is_reported_back(self, client):
        response = _upload(client, files=[
            ("files", ("../../evil.pdf", io.BytesIO(MINIMAL_PDF), "application/pdf"))])
        name = response.json()["file_names"][0]
        assert "/" not in name and "\\" not in name and ".." not in name


class TestSessionScopedRoutes:
    def test_status_of_a_fresh_session(self, client):
        session_id = _upload(client).json()["session_id"]
        body = client.get(f"/api/status/{session_id}").json()
        assert body["status"] == "queued"
        assert body["progress"] == 5
        assert body["label"]

    def test_unknown_session_returns_a_structured_404(self, client):
        response = client.get("/api/status/does-not-exist")
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "session_not_found"

    def test_results_before_completion_return_409_not_400(self, client):
        session_id = _upload(client).json()["session_id"]
        response = client.get(f"/api/results/{session_id}")
        assert response.status_code == 409
        assert response.json()["error"]["code"] == "results_not_ready"

    def test_download_before_generation_returns_404(self, client):
        session_id = _upload(client).json()["session_id"]
        assert client.get(f"/api/download/{session_id}").status_code == 404

    def test_failed_pipeline_surfaces_its_reason(self, client):
        session_id = _upload(client).json()["session_id"]
        client.store.set_status(session_id, "failed", error="Groq unreachable")
        response = client.get(f"/api/results/{session_id}")
        assert response.status_code == 422
        assert "Groq unreachable" in response.json()["error"]["message"]

    def test_session_can_be_deleted_on_request(self, client):
        session_id = _upload(client).json()["session_id"]
        assert client.delete(f"/api/session/{session_id}").status_code == 200
        assert client.get(f"/api/status/{session_id}").status_code == 404

    def test_deleting_an_unknown_session_returns_404(self, client):
        assert client.delete("/api/session/ghost").status_code == 404


class TestQueryValidation:
    def test_unknown_session_is_rejected(self, client):
        response = client.post("/api/query", json={
            "session_id": "does-not-exist-but-long-enough", "question": "Is title clear?"})
        assert response.status_code == 404

    def test_short_question_fails_schema_validation(self, client):
        session_id = _upload(client).json()["session_id"]
        response = client.post("/api/query", json={"session_id": session_id, "question": "a"})
        assert response.status_code == 422

    def test_overlong_question_fails_schema_validation(self, client):
        session_id = _upload(client).json()["session_id"]
        response = client.post("/api/query",
                               json={"session_id": session_id, "question": "x" * 2000})
        assert response.status_code == 422

    def test_query_before_indexing_reports_not_ready(self, client):
        session_id = _upload(client).json()["session_id"]
        response = client.post("/api/query", json={
            "session_id": session_id, "question": "Is the title clear and marketable?"})
        assert response.status_code == 409


class TestAuthentication:
    @pytest.fixture
    def secured_client(self, monkeypatch, tmp_path):
        monkeypatch.setenv("API_KEY", "test-key-123")

        from core.config import get_settings, reset_settings_cache

        reset_settings_cache()
        settings = get_settings()
        object.__setattr__(settings, "upload_dir", tmp_path / "uploads")
        object.__setattr__(settings, "output_dir", tmp_path / "outputs")
        object.__setattr__(settings, "db_path", tmp_path / "sessions.db")
        settings.ensure_directories()

        import importlib

        import main as main_module

        importlib.reload(main_module)
        with TestClient(main_module.app) as test_client:
            yield test_client

    def test_protected_route_rejects_a_missing_key(self, secured_client):
        response = secured_client.get("/api/status/anything")
        assert response.status_code == 401
        assert response.json()["error"]["code"] == "unauthenticated"

    def test_protected_route_rejects_a_wrong_key(self, secured_client):
        response = secured_client.get("/api/status/anything",
                                      headers={"X-API-Key": "wrong"})
        assert response.status_code == 401

    def test_correct_key_reaches_the_handler(self, secured_client):
        response = secured_client.get("/api/status/anything",
                                      headers={"X-API-Key": "test-key-123"})
        assert response.status_code == 404          # past auth, session simply absent

    def test_public_routes_stay_open(self, secured_client):
        assert secured_client.get("/").status_code == 200
        assert secured_client.get("/api/health").status_code == 200

    def test_options_advertises_that_a_key_is_required(self, secured_client):
        assert secured_client.get("/api/options").json()["auth_required"] is True


class TestErrorContract:
    def test_every_error_uses_the_same_envelope(self, client):
        for response in (
            client.get("/api/status/nope"),
            client.get("/api/results/nope"),
            client.get("/api/download/nope"),
            _upload(client, transaction_type="invalid"),
        ):
            body = response.json()
            assert "error" in body
            assert "code" in body["error"]
            assert "message" in body["error"]
            assert body["error"]["message"].strip()
