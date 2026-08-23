# Legal RAG System

**AI-assisted first-pass due diligence for Pakistani property, lending and corporate acquisition transactions.**

A retrieval-augmented generation pipeline that ingests a lawyer's PDF bundle, indexes it
alongside a persistent corpus of Pakistani primary legislation, interrogates both corpora
with a jurisdiction-aware diligence checklist, and produces a branded memorandum in Word
and PDF — with every finding traceable to a document page and a statutory provision.

> Built during the skillSYNC AI/ML engineering internship (Pair B).
> `backendd/` and `frontendd/` are this author's work; `backend/` is a parallel
> implementation by the paired teammate and is out of scope.

---

## What makes it different

**Dual-corpus retrieval.** Every question is answered from the client's own documents
*and* the indexed statutes simultaneously, not one or the other. A finding therefore
carries a document citation, a statutory citation and a constitutional article together.

**Jurisdiction awareness.** The controlling authority changes with the city — CDA in
Islamabad, LDA in Lahore, SBCA in Karachi, RDA in Rawalpindi — and the checklist is
templated against whichever applies, down to the specific NOC types and bye-laws.

**Bilingual ingestion.** Revenue records are routinely scans of Urdu manuscript. Pages
that yield no extractable text are rasterised at 300 DPI and OCR'd in Urdu and English,
and the memorandum discloses which pages went through that lossy channel.

**Deterministic where it must be.** Statutory thresholds (PKR 5M for withholding tax
under ss. 236C/236K, PKR 10M for AML enhanced due diligence) are arithmetic, so they are
computed by rule rather than delegated to a model.

**Verifiable by design.** Generation is constrained to a fixed JSON schema so every
answer becomes a row a partner can audit in under a minute.

---

## Architecture

```
┌─ React 19 + Vite 8 ──────────────────────────────────────────────────────┐
│  Upload · live progress · findings triage · free-form Q&A · downloads    │
└──────────────────────────────────┬───────────────────────────────────────┘
                                   │  REST, polled
┌─ FastAPI (async) ─────────────────▼──────────────────────────────────────┐
│  Validation · sessions (SQLite) · background pipeline · rate limiting    │
└──────────────────────────────────┬───────────────────────────────────────┘
                                   │
┌─ Pipeline ────────────────────────▼──────────────────────────────────────┐
│  ingest → index → retrieve (dual + rerank) → generate → memo (docx/pdf)  │
└──────┬─────────────────────────────────────────────┬─────────────────────┘
       │                                             │
  ChromaDB (local, persistent)              Groq — openai/gpt-oss-120b
  384-d multilingual MiniLM                 OpenAI-compatible transport
```

| Layer | Choice | Why |
|---|---|---|
| Orchestration | LlamaIndex | Document-hierarchy retrieval, not multi-tool agency |
| Vector store | ChromaDB (local) | No daemon, no network hop, privileged documents stay on the firm's disk |
| Embeddings | `paraphrase-multilingual-MiniLM-L12-v2` | Places Urdu and English text in the same space |
| Reranking | `ms-marco-MiniLM-L-6-v2` cross-encoder | Bi-encoder similarity is coarse on legal prose; optional, degrades gracefully |
| Generation | Groq `openai/gpt-oss-120b` | Free tier, OpenAI-compatible — production swap is a base URL and a key |
| Sessions | SQLite (WAL) | Survives restarts, supports multiple workers, ships with Python |

---

## Quick start

### Prerequisites

- Python 3.11+ and Node 20+
- A free [Groq API key](https://console.groq.com/keys)
- *Optional, for scanned PDFs:* [Tesseract](https://github.com/tesseract-ocr/tesseract)
  (with the `urd` language pack) and [Poppler](https://poppler.freedesktop.org/)

### Backend

```bash
cd backendd
python -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate
pip install -r requirements.txt

cp .env.example .env              # then add your GROQ_API_KEY

# Put Pakistani statute PDFs in data/legal_corpus/
#   constitution.pdf, property-act.pdf, reg-act.pdf, stamp-act.pdf …

python verify_setup.py            # pre-flight: reports exactly what is missing
uvicorn main:app --reload         # http://localhost:8000  ·  docs at /docs
```

### Frontend

```bash
cd frontendd
npm install
cp .env.example .env              # optional; defaults to localhost:8000
npm run dev                       # http://localhost:5173
```

The first review builds the statutory index (about a minute). Every review after that
reloads it in milliseconds.

---

## Configuration

Everything is environment-driven; see `backendd/.env.example` for the annotated list.
The settings that matter most:

| Variable | Default | Notes |
|---|---|---|
| `GROQ_API_KEY` | — | **Required.** Reviews cannot run without it. |
| `API_KEY` | *(empty)* | Set it to require an `X-API-Key` header on every route. Empty = open, for friction-free demos. |
| `CORS_ORIGINS` | `localhost:5173` | Comma-separated. |
| `MAX_FILES` / `MAX_FILE_MB` / `MAX_BUNDLE_MB` | 10 / 50 / 150 | Upload limits. |
| `SESSION_TTL_HOURS` | 24 | After this, documents and vectors are purged. |
| `CHUNK_SIZE` / `CHUNK_OVERLAP` | 512 / 64 | Explicitly configured, not left to library defaults. |
| `SESSION_TOP_K` / `CORPUS_TOP_K` | 6 / 6 | Retrieved per corpus, before reranking. |
| `TOKENS_PER_MINUTE` | 12000 | Matches the Groq free tier. Raise on a paid plan. |
| `CHECKLIST_WORKERS` | 3 | Concurrent questions; the shared token bucket keeps this safe. |

---

## API

| Method | Route | Purpose |
|---|---|---|
| `GET` | `/api/health` | Deep check — LLM, OCR toolchain, corpus, session counts |
| `GET` | `/api/options` | Cities, societies, firm profiles, limits (the client renders from this) |
| `POST` | `/api/upload` | Multipart bundle → `session_id`; dispatches the review |
| `GET` | `/api/status/{id}` | Stage, percentage, human-readable label |
| `GET` | `/api/results/{id}` | Findings, red flags, risk counts, missing documents |
| `GET` | `/api/download/{id}` | Word memorandum |
| `GET` | `/api/download/{id}/pdf` | PDF memorandum |
| `POST` | `/api/query` | Free-form question against both corpora |
| `DELETE` | `/api/session/{id}` | Erase a session and everything derived from it |

Errors use one envelope throughout, so the client can branch on a stable code:

```json
{ "error": { "code": "results_not_ready", "message": "The review is at stage 'analysing' (70%)…" } }
```

Interactive documentation is at `/docs`.

---

## Tests

```bash
cd backendd
pip install -r requirements-dev.txt
pytest                                    # 303 tests
pytest --cov=core --cov-report=term-missing
```

The suite runs without a Groq key, a GPU or a network — every model-dependent path is
stubbed. Coverage is ~79% of `core/`; the uncovered remainder is the code that genuinely
requires a live model or a loaded index.

```bash
cd frontendd
npm run lint
npm run build
```

CI (`.github/workflows/ci.yml`) runs pytest on Python 3.11/3.12/3.13 and lints and builds
the frontend on every push.

---

## Repository layout

```
backendd/
  main.py                    FastAPI app, routes, background orchestrator
  verify_setup.py            Pre-flight diagnostic
  core/
    config.py                Settings and reference-data loading
    security.py              Session tokens, filename sanitisation, API-key auth
    store.py                 SQLite session persistence
    ratelimit.py             Token bucket and retry-with-backoff
    document_processor.py    Extraction, OCR, language detection, flag rules
    indexer.py               Vector index construction and caching
    query_engine.py          Dual retrieval, reranking, schema-constrained generation
    checklist.py             Diligence taxonomies, red-flag rules, execution
    memo_model.py            Format-agnostic memorandum model
    memo_generator.py        Word writer
    pdf_generator.py         PDF writer
    exceptions.py            Error taxonomy
  config/                    City, society, taxonomy and firm reference data
  data/legal_corpus/         Statute PDFs (you supply these)
  tests/                     303 tests

frontendd/
  src/
    App.jsx                  Shell and state machine
    lib/api.js               Single typed API client
    hooks/                   Polling and notifications
    components/              Upload, progress, results, Q&A, downloads, donut, toasts
    styles/                  Design tokens and application styles
```

---

## Limitations

Stated plainly, because a system handling privileged material should not overstate itself:

- **No accuracy benchmark.** The system has not been scored against a gold-standard set
  of lawyer-annotated bundles, so no precision or recall figure is quoted for the
  findings themselves.
- **Four statutes indexed.** The system prompt names nine; questions touching the
  unindexed five rely on the model's parametric knowledge rather than retrieval. Drop
  more PDFs into `data/legal_corpus/` and the index rebuilds itself.
- **Single-node.** ChromaDB and SQLite are local. Multi-worker deployment works;
  multi-machine needs a shared vector store.
- **OCR quality bounds everything.** A poor scan produces poor text and therefore poor
  findings. The memorandum discloses which pages were OCR'd for exactly this reason.

---

## Disclaimer

This system produces a **first-pass working draft, not legal advice**. Every memorandum
must be reviewed, verified and approved by a qualified Pakistani advocate before it is
relied upon or issued to a client. Findings cite the document and provision they rest on
precisely so that they can be independently verified against the original instruments.
