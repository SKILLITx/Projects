"""
Model-response parsing and coercion.

The previous build called ``json.loads`` on a lightly-cleaned string and, on
failure, fabricated a placeholder finding — so any response wrapped in prose was
discarded entirely.  These tests pin the recovery behaviour that replaced it.
"""

from __future__ import annotations

import pytest

from core.query_engine import (
    RetrievedChunk,
    SOURCE_CORPUS,
    SOURCE_SESSION,
    build_context,
    coerce_risk,
    coerce_string_list,
    extract_json_object,
)

VALID = '{"finding": "Title is registered.", "risk_level": "LOW"}'


class TestJsonExtraction:
    def test_plain_json(self):
        assert extract_json_object(VALID)["finding"] == "Title is registered."

    def test_markdown_fenced_json(self):
        assert extract_json_object(f"```json\n{VALID}\n```")["risk_level"] == "LOW"

    def test_bare_fence(self):
        assert extract_json_object(f"```\n{VALID}\n```") is not None

    def test_reasoning_model_think_block_is_stripped(self):
        raw = f"<think>Let me consider the deed carefully…</think>\n{VALID}"
        assert extract_json_object(raw)["risk_level"] == "LOW"

    def test_leading_and_trailing_prose_is_survivable(self):
        raw = f"Here is my analysis:\n{VALID}\nLet me know if you need more."
        assert extract_json_object(raw)["finding"] == "Title is registered."

    def test_braces_inside_string_values_do_not_break_matching(self):
        raw = '{"finding": "The clause reads {subject to consent} in the deed."}'
        assert "{subject to consent}" in extract_json_object(raw)["finding"]

    def test_escaped_quotes_are_handled(self):
        raw = '{"finding": "The deed says \\"free from encumbrance\\" at clause 4."}'
        assert "free from encumbrance" in extract_json_object(raw)["finding"]

    def test_nested_objects_are_preserved(self):
        raw = '{"finding": "ok", "meta": {"page": 4, "inner": {"a": 1}}}'
        assert extract_json_object(raw)["meta"]["inner"]["a"] == 1

    @pytest.mark.parametrize("raw", ["", "   ", None, "no json at all",
                                     "{ broken json", "[1, 2, 3]", "[]"])
    def test_unparseable_input_returns_none(self, raw):
        assert extract_json_object(raw or "") is None

    def test_an_object_wrapped_in_an_array_is_recovered(self):
        """A model that returns [{...}] should not cost the lawyer the finding."""
        assert extract_json_object('[{"finding": "x"}]') == {"finding": "x"}


class TestRiskCoercion:
    @pytest.mark.parametrize("raw,expected", [
        ("HIGH", "HIGH"), ("high", "HIGH"), ("  High  ", "HIGH"),
        ("MEDIUM", "MEDIUM"), ("Low", "LOW"),
        ("HIGH RISK", "HIGH"), ("risk_level: MEDIUM", "MEDIUM"),
        ("CRITICAL", "HIGH"), ("severe", "HIGH"),
        ("moderate", "MEDIUM"), ("negligible", "LOW"), ("nil", "LOW"),
    ])
    def test_variants_are_normalised(self, raw, expected):
        assert coerce_risk(raw) == expected

    @pytest.mark.parametrize("raw", [None, "", "  ", "banana", 42, {}])
    def test_unknown_values_fall_back_to_medium(self, raw):
        assert coerce_risk(raw) == "MEDIUM"

    def test_explicit_default_is_respected(self):
        assert coerce_risk(None, default="LOW") == "LOW"

    def test_output_is_always_a_permitted_level(self):
        for raw in ["HIGH", "x", None, 7, "critical", [], "LOW"]:
            assert coerce_risk(raw) in {"LOW", "MEDIUM", "HIGH"}


class TestStringListCoercion:
    def test_a_real_list_passes_through(self):
        assert coerce_string_list(["NOC", "Fard"]) == ["NOC", "Fard"]

    def test_a_comma_separated_string_is_split(self):
        assert coerce_string_list("NOC, Fard, Intiqal") == ["NOC", "Fard", "Intiqal"]

    def test_a_newline_separated_string_is_split(self):
        assert coerce_string_list("NOC\nFard") == ["NOC", "Fard"]

    def test_bullet_markers_are_stripped(self):
        assert coerce_string_list("- NOC\n- Fard") == ["NOC", "Fard"]

    @pytest.mark.parametrize("raw", [None, "", "   ", "none", "N/A", "nil", "[]", "-"])
    def test_empty_sentinels_yield_an_empty_list(self, raw):
        assert coerce_string_list(raw) == []

    def test_nulls_inside_a_list_are_dropped(self):
        assert coerce_string_list(["NOC", None, "", "none"]) == ["NOC"]

    def test_result_is_always_a_list_of_strings(self):
        for raw in [None, "a", ["a"], ("a",), {"a"}, 42]:
            result = coerce_string_list(raw)
            assert isinstance(result, list)
            assert all(isinstance(item, str) for item in result)


class TestContextBuilding:
    def _chunk(self, source: str, text: str = "Clause text here") -> RetrievedChunk:
        return RetrievedChunk(text=text, source=source, file_name="deed.pdf",
                              page_num=3, score=0.9)

    def test_provenance_labels_are_applied(self):
        context = build_context([
            self._chunk(SOURCE_SESSION), self._chunk(SOURCE_CORPUS)])
        assert "[CLIENT DOCUMENT" in context
        assert "[PAKISTANI STATUTE" in context

    def test_citations_include_the_page(self):
        assert "deed.pdf, page 3" in build_context([self._chunk(SOURCE_SESSION)])

    def test_empty_retrieval_produces_an_explicit_statement(self):
        assert "No relevant context" in build_context([])

    def test_character_budget_is_respected(self):
        chunks = [self._chunk(SOURCE_SESSION, "x" * 5000) for _ in range(10)]
        assert len(build_context(chunks, char_budget=6000)) <= 6500

    def test_chunk_without_a_page_still_renders(self):
        chunk = RetrievedChunk(text="Statute text", source=SOURCE_CORPUS,
                               file_name="stamp-act.pdf", page_num=None, score=0.5)
        assert "stamp-act.pdf" in build_context([chunk])
