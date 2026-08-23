"""
Configuration loading, validation and clamping.

The chunking test pins the documentation drift the previous build carried: the
architecture note promised ``chunk_size=512, chunk_overlap=50`` while the code
configured neither, so LlamaIndex library defaults silently applied.
"""

from __future__ import annotations

import pytest

from core.config import (
    city_profiles,
    document_taxonomy,
    firm_profiles,
    get_settings,
    housing_societies,
    reset_settings_cache,
    valid_cities,
    valid_societies,
)


class TestDefaults:
    def test_sensible_defaults_without_any_environment(self):
        settings = get_settings()
        assert settings.max_files == 10
        assert settings.session_ttl_hours == 24
        assert settings.chunk_size == 512
        assert settings.auth_enabled is False

    def test_chunking_is_explicitly_configured(self):
        """No longer left to library defaults."""
        settings = get_settings()
        assert settings.chunk_size > 0
        assert 0 <= settings.chunk_overlap < settings.chunk_size

    def test_embed_model_is_the_multilingual_variant(self):
        assert "multilingual" in get_settings().embed_model

    def test_derived_byte_limits(self):
        settings = get_settings()
        assert settings.max_file_bytes == settings.max_file_mb * 1024 * 1024
        assert settings.max_bundle_bytes == settings.max_bundle_mb * 1024 * 1024


class TestEnvironmentOverrides:
    def test_integers_are_read(self, monkeypatch):
        monkeypatch.setenv("MAX_FILES", "25")
        reset_settings_cache()
        assert get_settings().max_files == 25

    def test_invalid_integers_fall_back_instead_of_crashing(self, monkeypatch):
        monkeypatch.setenv("MAX_FILES", "not-a-number")
        reset_settings_cache()
        assert get_settings().max_files == 10

    def test_out_of_range_values_are_clamped(self, monkeypatch):
        monkeypatch.setenv("MAX_FILES", "99999")
        reset_settings_cache()
        assert get_settings().max_files <= 100

        monkeypatch.setenv("MAX_FILES", "-5")
        reset_settings_cache()
        assert get_settings().max_files >= 1

    def test_booleans_accept_common_spellings(self, monkeypatch):
        for raw, expected in [("true", True), ("1", True), ("yes", True), ("on", True),
                              ("false", False), ("0", False), ("no", False)]:
            monkeypatch.setenv("RERANK_ENABLED", raw)
            reset_settings_cache()
            assert get_settings().rerank_enabled is expected

    def test_cors_origins_are_split_on_commas(self, monkeypatch):
        monkeypatch.setenv("CORS_ORIGINS", "http://a.test, http://b.test ,http://c.test")
        reset_settings_cache()
        assert get_settings().cors_origins == (
            "http://a.test", "http://b.test", "http://c.test")

    def test_overlap_larger_than_chunk_is_corrected(self, monkeypatch):
        monkeypatch.setenv("CHUNK_SIZE", "512")
        monkeypatch.setenv("CHUNK_OVERLAP", "900")
        reset_settings_cache()
        settings = get_settings()
        assert settings.chunk_overlap < settings.chunk_size

    def test_api_key_enables_authentication(self, monkeypatch):
        monkeypatch.setenv("API_KEY", "abc")
        reset_settings_cache()
        assert get_settings().auth_enabled is True

    def test_groq_key_marks_the_llm_configured(self, monkeypatch):
        assert get_settings().llm_configured is False
        monkeypatch.setenv("GROQ_API_KEY", "gsk_test")
        reset_settings_cache()
        assert get_settings().llm_configured is True


class TestReferenceData:
    def test_all_four_cities_load(self):
        profiles = city_profiles()
        assert {"islamabad", "rawalpindi", "lahore", "karachi"} <= set(profiles)

    def test_each_city_carries_a_complete_profile(self):
        for key, profile in city_profiles().items():
            assert profile["authority"], key
            assert profile["full_name"], key
            assert isinstance(profile["noc_types"], list), key
            assert profile["relevant_bylaws"], key

    def test_authorities_are_the_correct_ones(self):
        profiles = city_profiles()
        assert profiles["islamabad"]["authority"] == "CDA"
        assert profiles["lahore"]["authority"] == "LDA"
        assert profiles["karachi"]["authority"] == "SBCA"
        assert profiles["rawalpindi"]["authority"] == "RDA"

    def test_housing_societies_load_with_transfer_documents(self):
        societies = housing_societies()
        assert "DHA Lahore" in societies
        assert societies["DHA Lahore"]["transfer_docs"]

    def test_document_taxonomy_covers_every_transaction_type(self):
        required = document_taxonomy()["required_documents"]
        assert {"property", "loan", "acquisition"} <= set(required)
        assert "Fard-e-Malkiat" in required["property"]

    def test_firm_profiles_load(self):
        profiles = firm_profiles()
        assert "josh_mak" in profiles
        assert profiles["josh_mak"]["name"]

    def test_convenience_sets(self):
        assert "lahore" in valid_cities()
        assert "DHA Lahore" in valid_societies()

    def test_reference_data_is_cached(self):
        assert city_profiles() is city_profiles()

    @pytest.mark.parametrize("loader", [city_profiles, housing_societies,
                                        document_taxonomy, firm_profiles])
    def test_loaders_never_raise(self, loader):
        assert loader() is not None
