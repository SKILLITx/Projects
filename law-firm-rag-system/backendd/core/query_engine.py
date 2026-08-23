"""
Retrieval and generation: dual-corpus fusion, reranking, schema enforcement.

The most consequential change in this rebuild is the retrieval strategy.  The
previous engine wrapped both indexes in a ``RouterQueryEngine`` driven by an
``LLMSingleSelector``, which routes each question to **exactly one** corpus.
That is wrong for the questions this system actually asks: *"does this deed
satisfy section 17 of the Registration Act"* needs the client's deed **and** the
Act simultaneously, and single-select retrieved only one of them.  It also spent
an extra LLM call per question purely on routing.

The replacement is a fusion retriever: both indexes are queried in parallel,
their nodes are tagged by provenance, optionally reranked by a cross-encoder,
and passed to a single synthesis call.  This removes the routing call, removes
the single-select limitation, and produces answers that cite a document and a
statute in the same breath — which is the whole point of the product.

Also fixed: the previous build mutated the global ``Settings.llm`` from inside
``build_dual_engine``, which raced whenever two reviews ran concurrently.  The
LLM is now passed explicitly at every call site.
"""

from __future__ import annotations

import json
import logging
import re
import threading
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from typing import Any, Iterable

from core.config import get_settings
from core.exceptions import ConfigurationError, LlmUnavailableError
from core.ratelimit import CompositeLimiter, build_llm_limiter, retry_with_backoff

logger = logging.getLogger(__name__)

SOURCE_SESSION = "client_documents"
SOURCE_CORPUS = "pakistani_statutes"

RISK_LEVELS = ("LOW", "MEDIUM", "HIGH")

SYSTEM_PROMPT = """You are an expert Pakistani legal due diligence assistant \
supporting a qualified advocate. You analyse legal documents under Pakistani law, \
including the Constitution of Pakistan 1973, the Transfer of Property Act 1882, \
the Registration Act 1908, the Stamp Act 1899, the Land Revenue Act 1967, \
the Companies Act 2017, the Muslim Family Laws Ordinance 1961, the Benami \
Transactions (Prohibition) Act 2017, the Anti-Money Laundering Act 2010 and the \
Income Tax Ordinance 2001.

You are given retrieved context from two distinct sources, each labelled:
  [CLIENT DOCUMENT] — the lawyer's own uploaded bundle
  [PAKISTANI STATUTE] — primary legislation

Respond with a single valid JSON object and nothing else. No preamble, no
markdown fences, no commentary outside the JSON. The schema is:

{
  "finding": "<what the client's documents actually show on this question>",
  "reasoning": "<step-by-step legal reasoning quoting the specific text relied on>",
  "document_citation": "<source file and page number from [CLIENT DOCUMENT] context>",
  "statutory_citation": "<the controlling Pakistani statute and section>",
  "constitutional_basis": "<the relevant Article of the Constitution of Pakistan 1973>",
  "risk_level": "LOW" | "MEDIUM" | "HIGH",
  "recommendation": "<one concrete action for the reviewing advocate>",
  "missing_documents": ["<document that should exist but was not provided>"],
  "confidence": "LOW" | "MEDIUM" | "HIGH"
}

Rules that must never be broken:
- risk_level and confidence must be exactly LOW, MEDIUM or HIGH.
- Never invent facts. If the documents do not answer the question, say so plainly
  in "finding", set risk_level to MEDIUM, and list what is needed in
  "missing_documents".
- document_citation must name a real file and page from the supplied context.
  Write "Not found in supplied documents" if there is none.
- Prefer the most specific statutory provision available over a general one.
- Assess risk from the buyer's or lender's perspective: an absent NOC, an
  unregistered mutation, an undisclosed co-owner or a live encumbrance is HIGH.
"""


# ──────────────────────────────────────────────────────────────────────────
#  Shared limiter
# ──────────────────────────────────────────────────────────────────────────
_limiter_lock = threading.Lock()
_limiter: CompositeLimiter | None = None


def get_limiter() -> CompositeLimiter:
    """Process-wide limiter shared by every LLM call, so concurrency is safe."""
    global _limiter
    if _limiter is None:
        with _limiter_lock:
            if _limiter is None:
                settings = get_settings()
                _limiter = build_llm_limiter(
                    tokens_per_minute=settings.tokens_per_minute,
                    requests_per_minute=settings.requests_per_minute,
                    est_tokens_per_query=settings.est_tokens_per_query,
                )
                logger.info(
                    "LLM limiter: %d tokens/min, %d requests/min, ~%d tokens/query",
                    settings.tokens_per_minute, settings.requests_per_minute,
                    settings.est_tokens_per_query,
                )
    return _limiter


def reset_limiter() -> None:
    global _limiter
    with _limiter_lock:
        _limiter = None


# ──────────────────────────────────────────────────────────────────────────
#  LLM
# ──────────────────────────────────────────────────────────────────────────
_llm_lock = threading.Lock()
_llm: Any = None


def get_llm() -> Any:
    """Configured Groq client.  Raises if no credential is present."""
    global _llm
    settings = get_settings()
    if not settings.llm_configured:
        raise ConfigurationError(
            "GROQ_API_KEY is not set. Add it to backendd/.env before running a review.",
            variable="GROQ_API_KEY",
        )
    if _llm is None:
        with _llm_lock:
            if _llm is None:
                from llama_index.llms.groq import Groq

                _llm = Groq(
                    model=settings.llm_model,
                    api_key=settings.groq_api_key,
                    temperature=settings.llm_temperature,
                    timeout=settings.llm_timeout_s,
                    system_prompt=SYSTEM_PROMPT,
                )
                logger.info("LLM ready: %s (temperature %.2f)",
                            settings.llm_model, settings.llm_temperature)
    return _llm


def reset_llm() -> None:
    global _llm
    with _llm_lock:
        _llm = None


# ──────────────────────────────────────────────────────────────────────────
#  Reranking
# ──────────────────────────────────────────────────────────────────────────
_rerank_lock = threading.Lock()
_reranker: Any = None
_rerank_unavailable = False


def get_reranker() -> Any | None:
    """
    Cross-encoder reranker, or ``None`` when unavailable.

    Reranking is a genuine quality win — bi-encoder similarity is a coarse
    proxy for relevance on legal prose — but it is strictly optional: if the
    model cannot be loaded the pipeline degrades to raw similarity order
    rather than failing the review.
    """
    global _reranker, _rerank_unavailable
    settings = get_settings()
    if not settings.rerank_enabled or _rerank_unavailable:
        return None
    if _reranker is None:
        with _rerank_lock:
            if _reranker is None and not _rerank_unavailable:
                try:
                    from sentence_transformers import CrossEncoder

                    logger.info("Loading reranker %s…", settings.rerank_model)
                    _reranker = CrossEncoder(settings.rerank_model, max_length=512)
                    logger.info("Reranker ready.")
                except Exception as exc:                     # noqa: BLE001
                    logger.warning("Reranker unavailable (%s) — using similarity order.", exc)
                    _rerank_unavailable = True
                    return None
    return _reranker


def reset_reranker() -> None:
    global _reranker, _rerank_unavailable
    with _rerank_lock:
        _reranker = None
        _rerank_unavailable = False


# ──────────────────────────────────────────────────────────────────────────
#  Retrieval
# ──────────────────────────────────────────────────────────────────────────
@dataclass
class RetrievedChunk:
    text: str
    source: str
    file_name: str
    page_num: int | None
    score: float

    @property
    def label(self) -> str:
        return "CLIENT DOCUMENT" if self.source == SOURCE_SESSION else "PAKISTANI STATUTE"

    @property
    def citation(self) -> str:
        if self.page_num:
            return f"{self.file_name}, page {self.page_num}"
        return self.file_name

    def render(self) -> str:
        return f"[{self.label} — {self.citation}]\n{self.text.strip()}"


def _node_to_chunk(node: Any, source: str) -> RetrievedChunk:
    metadata = getattr(node, "metadata", None) or {}
    if not metadata and hasattr(node, "node"):
        metadata = getattr(node.node, "metadata", None) or {}

    text = ""
    for accessor in ("get_content", "get_text"):
        method = getattr(node, accessor, None)
        if callable(method):
            try:
                text = method()
                break
            except Exception:                                # noqa: BLE001
                continue
    if not text:
        text = str(getattr(node, "text", "") or "")

    page = metadata.get("page_num") or metadata.get("page_label")
    try:
        page_num = int(page) if page is not None else None
    except (TypeError, ValueError):
        page_num = None

    return RetrievedChunk(
        text=text,
        source=source,
        file_name=str(metadata.get("source_file")
                      or metadata.get("file_name")
                      or ("Client bundle" if source == SOURCE_SESSION else "Pakistani statute")),
        page_num=page_num,
        score=float(getattr(node, "score", 0.0) or 0.0),
    )


def _retrieve_from(index: Any, query: str, top_k: int, source: str) -> list[RetrievedChunk]:
    if index is None:
        return []
    try:
        retriever = index.as_retriever(similarity_top_k=top_k)
        return [_node_to_chunk(node, source) for node in retriever.retrieve(query)]
    except Exception as exc:                                 # noqa: BLE001
        logger.warning("Retrieval from %s failed: %s", source, exc)
        return []


def retrieve_dual(session_index: Any, corpus_index: Any, question: str) -> list[RetrievedChunk]:
    """
    Query both corpora concurrently and fuse the results.

    Both indexes are always consulted — this is the fix for the single-select
    router that could only ever see one of them per question.
    """
    settings = get_settings()
    with ThreadPoolExecutor(max_workers=2, thread_name_prefix="retrieve") as pool:
        session_future = pool.submit(
            _retrieve_from, session_index, question, settings.session_top_k, SOURCE_SESSION)
        corpus_future = pool.submit(
            _retrieve_from, corpus_index, question, settings.corpus_top_k, SOURCE_CORPUS)
        session_chunks = session_future.result()
        corpus_chunks = corpus_future.result()

    return rerank_chunks(question, session_chunks, corpus_chunks)


def rerank_chunks(
    question: str,
    session_chunks: list[RetrievedChunk],
    corpus_chunks: list[RetrievedChunk],
) -> list[RetrievedChunk]:
    """
    Rerank each corpus independently, then interleave.

    Reranking the two pools *separately* is deliberate.  A single pooled ranking
    would let long statutory passages, which score well on lexical overlap,
    crowd the client's own clauses out of the context window entirely — which is
    exactly the failure the dual-index design exists to prevent.  Independent
    ranking guarantees the model always sees evidence from both sides.
    """
    settings = get_settings()
    reranker = get_reranker()

    def _rank(chunks: list[RetrievedChunk]) -> list[RetrievedChunk]:
        if not chunks:
            return []
        if reranker is None:
            return sorted(chunks, key=lambda c: c.score, reverse=True)[:settings.rerank_top_n]
        try:
            pairs = [(question, chunk.text[:2000]) for chunk in chunks]
            scores = reranker.predict(pairs)
            for chunk, score in zip(chunks, scores):
                chunk.score = float(score)
        except Exception as exc:                             # noqa: BLE001
            logger.warning("Reranking failed (%s) — falling back to similarity order.", exc)
        return sorted(chunks, key=lambda c: c.score, reverse=True)[:settings.rerank_top_n]

    ranked_session = _rank(session_chunks)
    ranked_corpus = _rank(corpus_chunks)

    fused: list[RetrievedChunk] = []
    for index in range(max(len(ranked_session), len(ranked_corpus))):
        if index < len(ranked_session):
            fused.append(ranked_session[index])
        if index < len(ranked_corpus):
            fused.append(ranked_corpus[index])
    return fused


def build_context(chunks: Iterable[RetrievedChunk], *, char_budget: int = 12_000) -> str:
    """Render retrieved chunks into a provenance-labelled prompt context."""
    rendered: list[str] = []
    used = 0
    for chunk in chunks:
        block = chunk.render()
        if used + len(block) > char_budget:
            continue
        rendered.append(block)
        used += len(block)
    return "\n\n---\n\n".join(rendered) if rendered else "No relevant context was retrieved."


# ──────────────────────────────────────────────────────────────────────────
#  Response parsing
# ──────────────────────────────────────────────────────────────────────────
_THINK_BLOCK = re.compile(r"<think>.*?</think>", re.DOTALL | re.IGNORECASE)
_CODE_FENCE = re.compile(r"```(?:json)?\s*|\s*```", re.IGNORECASE)


def extract_json_object(raw: str) -> dict[str, Any] | None:
    """
    Pull the first well-formed JSON object out of a model response.

    Handles reasoning-model ``<think>`` blocks, markdown fences, and leading or
    trailing prose, then falls back to brace-matching so a response wrapped in
    commentary still parses instead of being discarded.
    """
    if not raw or not raw.strip():
        return None

    cleaned = _THINK_BLOCK.sub("", raw)
    cleaned = _CODE_FENCE.sub("", cleaned).strip()

    try:
        parsed = json.loads(cleaned)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass

    # Brace matching, respecting string literals and escapes.
    start = cleaned.find("{")
    while start != -1:
        depth = 0
        in_string = False
        escaped = False
        for position in range(start, len(cleaned)):
            char = cleaned[position]
            if escaped:
                escaped = False
                continue
            if char == "\\":
                escaped = True
                continue
            if char == '"':
                in_string = not in_string
                continue
            if in_string:
                continue
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    candidate = cleaned[start:position + 1]
                    try:
                        parsed = json.loads(candidate)
                        if isinstance(parsed, dict):
                            return parsed
                    except json.JSONDecodeError:
                        break
        start = cleaned.find("{", start + 1)
    return None


def coerce_risk(value: Any, default: str = "MEDIUM") -> str:
    """Normalise any model-supplied risk value onto the permitted enum."""
    if not value:
        return default
    text = str(value).strip().upper()
    for level in RISK_LEVELS:
        if level in text:
            return level
    if text in {"CRITICAL", "SEVERE", "MAJOR"}:
        return "HIGH"
    if text in {"MODERATE", "AVERAGE"}:
        return "MEDIUM"
    if text in {"MINOR", "NEGLIGIBLE", "NONE", "NIL"}:
        return "LOW"
    return default


def coerce_string_list(value: Any) -> list[str]:
    """Normalise ``missing_documents`` regardless of what the model emitted."""
    if value is None:
        return []
    if isinstance(value, str):
        text = value.strip()
        if not text or text.lower() in {"none", "n/a", "nil", "[]", "-"}:
            return []
        parts = re.split(r"[;\n]|,(?![^(]*\))", text)
        return [part.strip(" -•\t") for part in parts if part.strip(" -•\t")]
    if isinstance(value, (list, tuple, set)):
        out: list[str] = []
        for item in value:
            if item is None:
                continue
            text = str(item).strip()
            if text and text.lower() not in {"none", "n/a", "nil"}:
                out.append(text)
        return out
    return [str(value).strip()]


# ──────────────────────────────────────────────────────────────────────────
#  Generation
# ──────────────────────────────────────────────────────────────────────────
def _build_prompt(question: str, context: str, hint: str | None) -> str:
    guidance = f"\n\nJurisdictional guidance for this question:\n{hint}" if hint else ""
    return (
        f"{SYSTEM_PROMPT}\n\n"
        f"=== RETRIEVED CONTEXT ===\n{context}\n\n"
        f"=== QUESTION ===\n{question}{guidance}\n\n"
        f"Respond now with the JSON object only."
    )


def complete(prompt: str, *, description: str = "llm call") -> str:
    """One rate-limited, retried completion.  Returns the raw response text."""
    settings = get_settings()
    llm = get_llm()
    limiter = get_limiter()

    def _call() -> str:
        limiter.acquire(token_cost=settings.est_tokens_per_query)
        response = llm.complete(prompt)
        return str(response)

    try:
        return retry_with_backoff(
            _call,
            max_retries=settings.max_retries,
            base_delay=settings.retry_base_delay_s,
            description=description,
        )
    except Exception as exc:                                 # noqa: BLE001
        raise LlmUnavailableError(
            f"The language model could not be reached: {exc}", operation=description
        ) from exc


def answer_question(
    session_index: Any,
    corpus_index: Any,
    question: str,
    *,
    hint: str | None = None,
    description: str = "checklist question",
) -> dict[str, Any]:
    """
    Full retrieve-then-generate cycle for one question.

    Returns the parsed finding augmented with the provenance of every chunk the
    model was shown, so the client can display exactly what evidence produced
    the answer.
    """
    chunks = retrieve_dual(session_index, corpus_index, question)
    context = build_context(chunks)
    raw = complete(_build_prompt(question, context, hint), description=description)

    parsed = extract_json_object(raw)
    if parsed is None:
        logger.warning("Unparseable model response for %s — using conservative fallback.",
                       description)
        return {
            "finding": (raw.strip()[:600] or "The model returned no usable response."),
            "reasoning": "The model's response could not be parsed as structured JSON.",
            "document_citation": "Not available",
            "statutory_citation": "Not available",
            "constitutional_basis": "",
            "risk_level": "MEDIUM",
            "recommendation": "Manual review required — this item was not machine-assessable.",
            "missing_documents": [],
            "confidence": "LOW",
            "parse_failed": True,
            "retrieved_sources": [c.citation for c in chunks],
        }

    return {
        "finding": str(parsed.get("finding") or "No finding was returned.").strip(),
        "reasoning": str(parsed.get("reasoning") or "").strip(),
        "document_citation": str(parsed.get("document_citation")
                                 or "Not found in supplied documents").strip(),
        "statutory_citation": str(parsed.get("statutory_citation") or "").strip(),
        "constitutional_basis": str(parsed.get("constitutional_basis") or "").strip(),
        "risk_level": coerce_risk(parsed.get("risk_level")),
        "recommendation": str(parsed.get("recommendation")
                              or "Verify this item against the original documents.").strip(),
        "missing_documents": coerce_string_list(parsed.get("missing_documents")),
        "confidence": coerce_risk(parsed.get("confidence"), default="MEDIUM"),
        "parse_failed": False,
        "retrieved_sources": [c.citation for c in chunks],
        "client_chunks": sum(1 for c in chunks if c.source == SOURCE_SESSION),
        "statute_chunks": sum(1 for c in chunks if c.source == SOURCE_CORPUS),
    }
