"""
Security regressions.

The path-traversal cases here are the ones that mattered: the previous build
wrote uploads to ``session_dir / file.filename`` with the client-supplied name
used verbatim, so every payload in ``TRAVERSAL_PAYLOADS`` escaped the session
directory.
"""

from __future__ import annotations

import pytest

from core.config import get_settings, reset_settings_cache
from core.exceptions import AuthenticationError
from core.security import (
    MAX_FILENAME_LENGTH,
    new_session_id,
    safe_filename,
    unique_filename,
    verify_api_key,
)

TRAVERSAL_PAYLOADS = [
    "../../etc/passwd",
    "../../../core/main.py",
    "..\\..\\Windows\\System32\\drivers\\etc\\hosts",
    "/etc/shadow",
    "C:\\Windows\\win.ini",
    "....//....//secret.pdf",
    "deed/../../../escape.pdf",
    "\\\\server\\share\\file.pdf",
]


class TestFilenameSanitisation:
    @pytest.mark.parametrize("payload", TRAVERSAL_PAYLOADS)
    def test_traversal_payloads_are_reduced_to_a_single_component(self, payload):
        result = safe_filename(payload)
        assert "/" not in result
        assert "\\" not in result
        assert not result.startswith(".")
        assert ".." not in result

    def test_ordinary_names_survive_intact(self):
        assert safe_filename("Sale Deed 2024.pdf") == "Sale Deed 2024.pdf"
        assert safe_filename("fard-e-malkiat.pdf") == "fard-e-malkiat.pdf"

    def test_control_characters_are_stripped(self):
        assert "\x00" not in safe_filename("deed\x00.pdf")
        assert "\n" not in safe_filename("deed\n\r.pdf")

    def test_windows_reserved_names_are_escaped(self):
        assert safe_filename("CON.pdf").upper() != "CON.PDF"
        assert safe_filename("aux.pdf").lower().startswith("_aux")

    def test_empty_and_none_fall_back(self):
        assert safe_filename("") == "document.pdf"
        assert safe_filename(None) == "document.pdf"
        assert safe_filename("   ") == "document.pdf"
        assert safe_filename("...") == "document.pdf"

    def test_long_names_are_bounded_but_keep_their_extension(self):
        result = safe_filename("x" * 400 + ".pdf")
        assert len(result) <= MAX_FILENAME_LENGTH
        assert result.endswith(".pdf")

    def test_unicode_names_are_preserved(self):
        result = safe_filename("فرد_مالکیت.pdf")
        assert result.endswith(".pdf")
        assert len(result) > 4

    def test_result_is_always_non_empty(self):
        for payload in [*TRAVERSAL_PAYLOADS, "", ".", "..", "/", "\\", "   "]:
            assert safe_filename(payload).strip()


class TestUniqueFilename:
    def test_first_use_is_unchanged(self):
        assert unique_filename("deed.pdf", set()) == "deed.pdf"

    def test_collisions_are_disambiguated(self):
        taken = {"deed.pdf"}
        second = unique_filename("deed.pdf", taken)
        assert second != "deed.pdf"
        assert second.endswith(".pdf")

    def test_repeated_collisions_keep_producing_new_names(self):
        taken: set[str] = set()
        produced = []
        for _ in range(5):
            name = unique_filename("deed.pdf", taken)
            taken.add(name)
            produced.append(name)
        assert len(set(produced)) == 5


class TestSessionTokens:
    def test_tokens_carry_far_more_entropy_than_the_old_8_char_uuid_slice(self):
        token = new_session_id()
        assert len(token) >= 40

    def test_tokens_are_unique_across_many_draws(self):
        assert len({new_session_id() for _ in range(2000)}) == 2000

    def test_tokens_are_url_safe(self):
        allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        assert set(new_session_id()) <= allowed


class TestApiKeyEnforcement:
    def test_disabled_by_default_so_demos_need_no_credentials(self):
        verify_api_key(None)          # must not raise
        verify_api_key("anything")

    def test_enforced_when_configured(self, monkeypatch):
        monkeypatch.setenv("API_KEY", "s3cret-key")
        reset_settings_cache()
        assert get_settings().auth_enabled is True

        verify_api_key("s3cret-key")
        for bad in (None, "", "wrong", "s3cret-ke", "S3CRET-KEY"):
            with pytest.raises(AuthenticationError):
                verify_api_key(bad)
