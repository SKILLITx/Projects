"""
Checklist assembly, city/society wiring and red-flag evaluation.

The wiring tests pin the fix for configuration that shipped but was never read:
``city_profiles.json`` and ``housing_societies.json`` existed from the first
commit, yet no module consulted them, so an Islamabad review and a Karachi
review asked identical generic NOC questions.
"""

from __future__ import annotations

import pytest

from core.checklist import (
    CHECKLISTS,
    RED_FLAG_RULES,
    VALID_TRANSACTION_TYPES,
    build_checklist,
    detect_red_flags,
    resolve_city,
)


class TestChecklistStructure:
    def test_all_three_taxonomies_exist_with_fifteen_questions(self):
        assert set(CHECKLISTS) == set(VALID_TRANSACTION_TYPES)
        for name, checklist in CHECKLISTS.items():
            assert len(checklist) == 15, name

    def test_every_question_has_a_topic(self):
        for name, checklist in CHECKLISTS.items():
            for item in checklist:
                assert item["topic"].strip(), name
                assert item["question"].strip(), name

    def test_ids_are_contiguous_from_one(self):
        items = build_checklist("property", {}, "islamabad")
        assert [item.id for item in items] == list(range(1, len(items) + 1))

    def test_no_duplicate_ids_even_with_every_supplement_active(self):
        flags = {
            "is_inherited": True, "benami_risk": True, "aml_threshold": True,
            "encumbrance_risk": True, "ocr_failures": 2, "detected_value_pkr": 5e7,
        }
        items = build_checklist("property", flags, "lahore", "DHA Lahore")
        ids = [item.id for item in items]
        assert len(ids) == len(set(ids))


class TestCityWiring:
    """The configuration files that previously sat unread."""

    def test_islamabad_questions_name_the_cda(self):
        items = build_checklist("property", {}, "islamabad")
        noc = next(item for item in items if item.topic == "noc")
        assert "Capital Development Authority" in noc.question
        assert "CDA" in noc.question

    def test_karachi_questions_name_the_sbca(self):
        items = build_checklist("property", {}, "karachi")
        noc = next(item for item in items if item.topic == "noc")
        assert "Sindh Building Control Authority" in noc.question
        assert "CDA" not in noc.question

    def test_two_cities_produce_genuinely_different_questions(self):
        lahore = {item.question for item in build_checklist("property", {}, "lahore")}
        karachi = {item.question for item in build_checklist("property", {}, "karachi")}
        assert lahore != karachi

    def test_bylaws_are_substituted(self):
        items = build_checklist("property", {}, "lahore")
        assert any("LDA Bye-Laws" in item.question for item in items)

    def test_noc_hint_carries_the_authority_specific_noc_types(self):
        items = build_checklist("property", {}, "islamabad")
        noc = next(item for item in items if item.topic == "noc")
        assert "CDA Building NOC" in noc.hint

    def test_unknown_city_falls_back_without_raising(self):
        items = build_checklist("property", {}, "atlantis")
        assert len(items) == 15
        assert "{authority}" not in " ".join(item.question for item in items)

    def test_no_template_placeholder_ever_leaks_into_a_question(self):
        for transaction in VALID_TRANSACTION_TYPES:
            for city in ("islamabad", "lahore", "karachi", "rawalpindi", "unknown"):
                for item in build_checklist(transaction, {}, city):
                    assert "{" not in item.question, (transaction, city)

    def test_resolve_city_is_case_insensitive(self):
        assert resolve_city("ISLAMABAD")["authority"] == "CDA"
        assert resolve_city("  Lahore ")["authority"] == "LDA"


class TestSupplementaryQuestions:
    def test_base_checklist_has_no_supplements(self):
        items = build_checklist("property", {}, "islamabad")
        assert all(item.category == "core" for item in items)
        assert len(items) == 15

    def test_inheritance_flag_injects_a_succession_question(self):
        items = build_checklist("property", {"is_inherited": True}, "islamabad")
        supplement = [i for i in items if i.category == "inheritance"]
        assert len(supplement) == 1
        assert "succession certificate" in supplement[0].question.lower()
        assert "Muslim Family Laws Ordinance 1961" in supplement[0].question

    def test_benami_flag_injects_a_benami_question(self):
        items = build_checklist("property", {"benami_risk": True}, "islamabad")
        assert any("Benami Transactions (Prohibition) Act 2017" in i.question
                   for i in items)

    def test_aml_flag_quotes_the_detected_value(self):
        items = build_checklist(
            "property", {"aml_threshold": True, "detected_value_pkr": 25_000_000},
            "islamabad")
        aml = next(i for i in items if i.category == "aml")
        assert "25,000,000" in aml.question
        assert "Anti-Money Laundering Act 2010" in aml.question

    def test_housing_society_question_lists_that_society_actual_documents(self):
        items = build_checklist("property", {}, "lahore", "DHA Lahore")
        society = next(i for i in items if i.category == "housing_society")
        assert "DHA Lahore" in society.question
        assert "DHA Transfer Letter" in society.question
        assert "DHA Dues Clearance" in society.question

    def test_different_societies_produce_different_document_lists(self):
        dha = next(i for i in build_checklist("property", {}, "lahore", "DHA Lahore")
                   if i.category == "housing_society")
        bahria = next(i for i in build_checklist(
            "property", {}, "rawalpindi", "Bahria Town Rawalpindi")
            if i.category == "housing_society")
        assert dha.question != bahria.question
        assert "Bahria Allocation Letter" in bahria.question

    def test_society_detected_from_flags_also_triggers_the_question(self):
        items = build_checklist("property", {"housing_society": "DHA Islamabad"},
                                "islamabad")
        assert any(i.category == "housing_society" for i in items)

    def test_ocr_failures_inject_an_integrity_question(self):
        items = build_checklist("property", {"ocr_failures": 3}, "islamabad")
        assert any(i.category == "integrity" for i in items)

    def test_every_flag_together_produces_the_full_set(self):
        flags = {
            "is_inherited": True, "benami_risk": True, "aml_threshold": True,
            "encumbrance_risk": True, "ocr_failures": 1, "detected_value_pkr": 5e7,
        }
        items = build_checklist("property", flags, "lahore", "DHA Lahore")
        categories = {item.category for item in items}
        assert {"core", "inheritance", "benami", "aml",
                "housing_society", "encumbrance", "integrity"} <= categories
        assert len(items) == 21


class TestRedFlagRules:
    def test_rule_ids_are_unique_and_well_formed(self):
        ids = [rule.id for rule in RED_FLAG_RULES]
        assert len(ids) == len(set(ids))
        assert all(rule_id.startswith("RF") for rule_id in ids)

    def test_every_rule_carries_full_attribution(self):
        for rule in RED_FLAG_RULES:
            assert rule.statute.strip()
            assert rule.article.startswith("Article")
            assert rule.patterns
            assert rule.description.strip()

    def test_a_real_defect_triggers_its_rule(self, sample_findings):
        flags = detect_red_flags(sample_findings)
        assert any(flag["id"] == "RF001" for flag in flags)

    def test_negated_finding_does_not_trigger_a_flag(self):
        """
        The headline regression: the previous build's RF003 fired on a finding
        that said litigation was *absent*, because the trigger phrase appeared
        inside the negation.
        """
        findings = [{
            "finding": "There is no ongoing litigation against the property.",
            "reasoning": "No suit pending against the vendor was disclosed anywhere.",
            "risk_level": "LOW",
        }]
        assert not any(flag["id"] == "RF003" for flag in detect_red_flags(findings))

    def test_genuine_litigation_still_triggers_rf003(self):
        findings = [{
            "finding": "Ongoing litigation was disclosed at page 7.",
            "reasoning": "A suit pending against the vendor is recorded.",
            "risk_level": "HIGH",
        }]
        assert any(flag["id"] == "RF003" for flag in detect_red_flags(findings))

    def test_source_documents_are_also_searched(self):
        source = "The property is subject to a subsisting mortgage in favour of HBL."
        assert any(flag["id"] == "RF008" for flag in detect_red_flags([], source))

    def test_evidence_is_attached_to_each_triggered_flag(self, sample_findings):
        flags = detect_red_flags(sample_findings)
        assert flags and all("evidence" in flag for flag in flags)

    def test_no_findings_yields_no_flags(self):
        assert detect_red_flags([]) == []
        assert detect_red_flags([], "") == []

    def test_malformed_findings_do_not_raise(self):
        assert isinstance(detect_red_flags([{}, {"finding": None}]), list)


class TestTransactionTypes:
    @pytest.mark.parametrize("transaction", VALID_TRANSACTION_TYPES)
    def test_each_type_builds(self, transaction):
        items = build_checklist(transaction, {}, "islamabad")
        assert len(items) == 15

    def test_unknown_type_falls_back_to_property(self):
        unknown = build_checklist("spaceship", {}, "islamabad")
        known = build_checklist("property", {}, "islamabad")
        assert [i.question for i in unknown] == [i.question for i in known]

    def test_loan_checklist_references_sbp_regulations(self):
        questions = " ".join(i.question for i in build_checklist("loan", {}, "islamabad"))
        assert "State Bank of Pakistan" in questions

    def test_acquisition_checklist_references_secp_and_ccp(self):
        questions = " ".join(
            i.question for i in build_checklist("acquisition", {}, "islamabad"))
        assert "SECP" in questions
        assert "Competition Commission of Pakistan" in questions
