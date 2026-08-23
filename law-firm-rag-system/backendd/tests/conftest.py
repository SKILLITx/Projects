"""Shared fixtures.  Everything here runs without network or model access."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from core.config import reset_settings_cache            # noqa: E402


@pytest.fixture(autouse=True)
def _clean_settings(monkeypatch, tmp_path):
    """Isolate every test from the developer's real .env and data directories."""
    for variable in (
        "API_KEY", "GROQ_API_KEY", "CORS_ORIGINS", "MAX_FILES", "MAX_FILE_MB",
        "MAX_BUNDLE_MB", "SESSION_TTL_HOURS", "CHUNK_SIZE", "CHUNK_OVERLAP",
        "TOKENS_PER_MINUTE", "REQUESTS_PER_MINUTE", "CHECKLIST_WORKERS",
        "RERANK_ENABLED", "LOG_LEVEL",
    ):
        monkeypatch.delenv(variable, raising=False)
    reset_settings_cache()
    yield
    reset_settings_cache()


@pytest.fixture
def store(tmp_path):
    from core.store import SessionStore

    return SessionStore(tmp_path / "sessions.db", ttl_hours=24)


@pytest.fixture
def sample_pages() -> list[dict]:
    """A small, realistic bundle exercising most detection paths."""
    return [
        {
            "page_num": 1,
            "source_file": "sale_deed.pdf",
            "text": (
                "SALE DEED. This deed of sale is executed between Muhammad Aslam "
                "son of the late Abdul Rahim, legal heirs of the deceased owner, "
                "and Fatima Bibi. The total sale consideration is PKR 12,500,000 "
                "(rupees one crore twenty five lakh only). The property is situated "
                "in DHA Lahore. CNIC 35202-1234567-1. A no objection certificate "
                "has not been obtained from the development authority."
            ),
            "is_urdu": False,
            "has_ocr": False,
            "char_count": 380,
            "ocr_failed": False,
        },
        {
            "page_num": 2,
            "source_file": "fard.pdf",
            "text": (
                "فرد مالکیت — انتقال رجسٹری مالک قبضہ تحصیل موضع واقع خسرہ. "
                "Record of rights extract. There is no ongoing litigation "
                "against this property and the title is free from encumbrance."
            ),
            "is_urdu": True,
            "has_ocr": True,
            "char_count": 200,
            "ocr_failed": False,
        },
    ]


@pytest.fixture
def sample_findings() -> list[dict]:
    return [
        {
            "question_id": 1, "topic": "title", "risk_level": "LOW",
            "finding": "The title deed is registered in the vendor's name.",
            "reasoning": "Registry number 4471 dated 12 March 2021 is on record.",
            "recommendation": "No action required.",
            "missing_documents": [],
        },
        {
            "question_id": 3, "topic": "noc", "risk_level": "HIGH",
            "finding": "The NOC is missing from the bundle.",
            "reasoning": "No no objection certificate was produced by the vendor.",
            "recommendation": "Requisition the NOC before completion.",
            "missing_documents": ["CDA Building NOC"],
        },
        {
            "question_id": 5, "topic": "litigation", "risk_level": "LOW",
            "finding": "There is no ongoing litigation against the property.",
            "reasoning": "No suit pending against the vendor was disclosed.",
            "recommendation": "Obtain a fresh court search closer to completion.",
            "missing_documents": [],
        },
    ]


@pytest.fixture
def sample_results(sample_findings) -> dict:
    return {
        "transaction_type": "property",
        "city": "islamabad",
        "authority": "CDA",
        "authority_full_name": "Capital Development Authority",
        "relevant_bylaws": "CDA Bye-Laws 2020",
        "housing_society": None,
        "total_questions": 3,
        "findings": sample_findings,
        "red_flags": [{
            "id": "RF001", "label": "Required NOC absent from the bundle",
            "statute": "LDA / CDA / RDA / SBCA Bye-Laws",
            "article": "Article 24 — Protection of property rights",
            "severity": "HIGH", "description": "Transfer cannot complete without it.",
            "evidence": ["noc is missing"],
        }],
        "high_risk_count": 1,
        "medium_risk_count": 0,
        "low_risk_count": 2,
        "failed_count": 0,
        "missing_documents": ["CDA Building NOC"],
        "flags": {
            "detected_value_pkr": 12_500_000,
            "fbr_applicable": True,
            "aml_threshold": True,
            "aml_indicators": False,
            "benami_risk": False,
            "is_inherited": True,
            "has_urdu": True,
            "urdu_page_count": 1,
            "has_ocr_pages": True,
            "ocr_page_count": 1,
            "ocr_failures": 0,
            "value_evidence": "consideration is PKR 12,500,000",
            "detected_documents": {"Registry": ["sale_deed.pdf"]},
        },
    }
