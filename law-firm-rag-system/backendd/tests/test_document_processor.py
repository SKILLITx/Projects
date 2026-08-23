"""
Ingestion logic: negation handling, monetary extraction, language detection.

Two named regressions are pinned here:

``test_negated_litigation_does_not_trip_the_flag``
    The previous build's rules were bare substring matches, so a finding reading
    "there is no ongoing litigation" contained the RF003 trigger phrase and
    raised a red flag asserting the opposite of what the document said.

``test_cnic_is_not_read_as_a_rupee_amount``
    A thirteen-digit CNIC parsed as a rupee value, silently tripping the
    PKR 10,000,000 anti-money-laundering threshold on transactions nowhere near it.
"""

from __future__ import annotations

import pytest

from core.document_processor import (
    AML_THRESHOLD_PKR,
    FBR_THRESHOLD_PKR,
    LITIGATION_INDICATORS,
    any_phrase,
    classify_documents,
    detect_special_flags,
    detect_transaction_value,
    detect_urdu,
    extract_monetary_values,
    find_phrase,
    get_constitutional_basis,
    is_negated,
    missing_required_documents,
    normalise_text,
    urdu_ratio,
    validate_pdf_bytes,
)


class TestNegationAwareMatching:
    def test_plain_mention_matches(self):
        assert find_phrase("There is ongoing litigation in the district court.",
                           "ongoing litigation")

    def test_negated_litigation_does_not_trip_the_flag(self):
        """The exact false positive that shipped in the previous build."""
        assert not find_phrase("There is no ongoing litigation against the property.",
                               "ongoing litigation")

    @pytest.mark.parametrize("sentence", [
        "The property is free from any encumbrance.",
        "No mortgage subsists over the land.",
        "The title is not subject to any lien.",
        "There are no pending litigation matters.",
        "The vendor confirms the absence of any charge.",
        "The property is unencumbered and clear of all claims.",
    ])
    def test_negated_statements_are_suppressed(self, sentence):
        for phrase in ("encumbrance", "mortgage", "lien", "pending litigation",
                       "charge", "claims"):
            if phrase in sentence.lower():
                assert not find_phrase(sentence, phrase), sentence

    def test_a_clause_boundary_resets_negation_scope(self):
        text = "There is no NOC on record. Ongoing litigation is disclosed at page 4."
        assert find_phrase(text, "ongoing litigation")

    def test_word_boundaries_are_respected(self):
        assert not find_phrase("The subcharge register was inspected.", "charge")
        assert find_phrase("A charge is registered against the property.", "charge")

    def test_whitespace_between_words_is_flexible(self):
        assert find_phrase("ongoing    litigation exists", "ongoing litigation")
        assert find_phrase("ongoing\nlitigation exists", "ongoing litigation")

    def test_is_negated_reports_position_correctly(self):
        text = "there is no ongoing litigation"
        assert is_negated(text, text.index("ongoing"))
        text2 = "there is ongoing litigation"
        assert not is_negated(text2, text2.index("ongoing"))

    def test_any_phrase_over_the_real_indicator_list(self):
        assert any_phrase("A stay order against the vendor subsists.",
                          LITIGATION_INDICATORS)
        assert not any_phrase("No stay order against the vendor subsists.",
                              LITIGATION_INDICATORS)


class TestMonetaryExtraction:
    def test_plain_pkr_amount(self):
        result = detect_transaction_value("The consideration is PKR 12,500,000 only.")
        assert result["detected_value_pkr"] == 12_500_000
        assert result["above_5m"] and result["above_10m"]

    def test_lakh_multiplier(self):
        assert detect_transaction_value("Sale price: Rs. 75 lakh")["detected_value_pkr"] \
            == 7_500_000

    def test_crore_multiplier(self):
        assert detect_transaction_value("Total amount of 2.5 crore rupees")["detected_value_pkr"] \
            == 25_000_000

    def test_million_multiplier(self):
        assert detect_transaction_value("PKR 8 million")["detected_value_pkr"] == 8_000_000

    def test_highest_plausible_value_wins(self):
        text = ("An earnest deposit of PKR 500,000 was paid against a total sale "
                "consideration of PKR 30,000,000.")
        assert detect_transaction_value(text)["detected_value_pkr"] == 30_000_000

    def test_cnic_is_not_read_as_a_rupee_amount(self):
        """The other shipped false positive: a CNIC tripping the AML threshold."""
        text = "The vendor's CNIC is 35202-1234567-1 and his ID number is 3520212345671."
        assert detect_transaction_value(text)["detected_value_pkr"] == 0

    def test_bare_digits_without_a_currency_cue_are_ignored(self):
        text = "Khasra number 1245 and Khata number 87654321 refer to plot 990000."
        assert detect_transaction_value(text)["detected_value_pkr"] == 0

    def test_iban_is_not_read_as_money(self):
        assert detect_transaction_value(
            "Account PK36SCBL0000001123456702 was debited.")["detected_value_pkr"] == 0

    def test_implausibly_small_amounts_are_rejected(self):
        assert detect_transaction_value("A fee of Rs. 500 was paid.")["detected_value_pkr"] == 0

    def test_bare_multiplier_needs_a_consideration_keyword(self):
        assert detect_transaction_value("The plot is 5 crore feet from the road.")[
            "detected_value_pkr"] == 0
        assert detect_transaction_value("The sale consideration is 5 crore.")[
            "detected_value_pkr"] == 50_000_000

    def test_thresholds_are_exact_at_the_boundary(self):
        assert detect_transaction_value("PKR 5,000,000")["above_5m"] is True
        assert detect_transaction_value("PKR 4,999,999")["above_5m"] is False
        assert detect_transaction_value("PKR 10,000,000")["above_10m"] is True
        assert detect_transaction_value("PKR 9,999,999")["above_10m"] is False

    def test_threshold_constants_match_the_statute(self):
        assert FBR_THRESHOLD_PKR == 5_000_000
        assert AML_THRESHOLD_PKR == 10_000_000

    def test_evidence_snippet_is_returned(self):
        result = detect_transaction_value("The sale consideration is PKR 12,500,000 only.")
        assert "12,500,000" in result["evidence"]

    def test_empty_input_is_safe(self):
        for value in ("", None, "   "):
            assert detect_transaction_value(value or "")["detected_value_pkr"] == 0

    def test_all_candidates_are_returned_sorted(self):
        findings = extract_monetary_values(
            "Deposit PKR 900,000 against consideration PKR 20,000,000.")
        assert [f.amount_pkr for f in findings] == sorted(
            (f.amount_pkr for f in findings), reverse=True)


class TestLanguageDetection:
    def test_urdu_script_is_detected(self):
        assert detect_urdu("فرد مالکیت انتقال رجسٹری مالک قبضہ تحصیل")

    def test_english_is_not_flagged_as_urdu(self):
        assert not detect_urdu(
            "This deed of sale is executed between the parties named above "
            "and registered with the Sub-Registrar on 12 March 2021.")

    def test_ratio_is_zero_for_pure_english(self):
        assert urdu_ratio("Sale deed registered") == 0.0

    def test_ratio_is_one_for_pure_urdu(self):
        assert urdu_ratio("فرد مالکیت") == pytest.approx(1.0)

    def test_mixed_content_is_detected(self):
        assert detect_urdu("Registry number 4471 — فرد مالکیت انتقال رجسٹری مالک")

    def test_empty_input_is_safe(self):
        assert detect_urdu("") is False
        assert detect_urdu(None or "") is False


class TestNormalisation:
    def test_whitespace_is_collapsed(self):
        assert normalise_text("a    b\t\tc") == "a b c"

    def test_control_characters_are_removed(self):
        assert "\x00" not in normalise_text("deed\x00text")

    def test_newlines_survive_but_are_capped(self):
        assert normalise_text("a\n\n\n\n\nb") == "a\n\nb"

    def test_none_is_safe(self):
        assert normalise_text(None) == ""


class TestPdfValidation:
    def test_magic_bytes_accepted(self):
        assert validate_pdf_bytes(b"%PDF-1.7\nrest of file")

    def test_non_pdf_rejected(self):
        assert not validate_pdf_bytes(b"PK\x03\x04")          # a .docx/.zip
        assert not validate_pdf_bytes(b"<html>")
        assert not validate_pdf_bytes(b"")


class TestDocumentClassification:
    def test_recognises_document_types(self, sample_pages):
        detected = classify_documents(sample_pages)
        assert "Registry" in detected
        # Both files mention a registry — the deed in English, the fard in Urdu.
        assert "sale_deed.pdf" in detected["Registry"]
        assert "Intiqal" in detected          # "انتقال" on the fard page

    def test_missing_documents_are_reported(self):
        missing = missing_required_documents({"Registry": ["a.pdf"]}, "property")
        assert "Fard-e-Malkiat" in missing
        assert "Registry" not in missing

    def test_unknown_transaction_type_yields_no_requirements(self):
        assert missing_required_documents({}, "nonexistent") == []


class TestFlagReport:
    def test_full_report_on_a_realistic_bundle(self, sample_pages):
        flags = detect_special_flags(sample_pages, "property")

        assert flags["is_inherited"] is True           # "legal heirs of", "the late"
        assert flags["housing_society"] == "DHA Lahore"
        assert flags["detected_value_pkr"] == 12_500_000
        assert flags["fbr_applicable"] is True
        assert flags["aml_threshold"] is True
        assert flags["has_urdu"] is True
        assert flags["has_ocr_pages"] is True
        assert flags["page_count"] == 2
        assert flags["urdu_page_count"] == 1

    def test_negated_statements_in_the_bundle_do_not_raise_flags(self, sample_pages):
        """Page 2 says litigation and encumbrance are absent — flags must stay down."""
        flags = detect_special_flags(sample_pages, "property")
        assert flags["litigation_risk"] is False
        assert flags["encumbrance_risk"] is False

    def test_empty_bundle_is_safe(self):
        flags = detect_special_flags([], "property")
        assert flags["page_count"] == 0
        assert flags["detected_value_pkr"] == 0
        assert flags["is_inherited"] is False

    def test_report_shape_is_stable(self, sample_pages):
        flags = detect_special_flags(sample_pages, "property")
        for key in ("is_inherited", "benami_risk", "has_urdu", "has_ocr_pages",
                    "housing_society", "detected_value_pkr", "aml_threshold",
                    "fbr_applicable", "missing_documents", "matched_indicators"):
            assert key in flags


class TestConstitutionalMapping:
    @pytest.mark.parametrize("topic,expected_article", [
        ("title", "Article 23"),
        ("noc", "Article 24"),
        ("co-owner", "Article 25"),
        ("litigation", "Article 24"),
        ("benami", "Article 24"),
        ("cnic", "Article 4"),
    ])
    def test_known_topics_map_correctly(self, topic, expected_article):
        assert expected_article in get_constitutional_basis(topic)

    def test_unknown_topic_falls_back_to_article_23(self):
        assert "Article 23" in get_constitutional_basis("entirely_unknown_topic")

    def test_empty_topic_is_safe(self):
        assert get_constitutional_basis("")
