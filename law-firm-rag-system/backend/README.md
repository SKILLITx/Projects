# Legal Due Diligence Ingestion Pipeline — Day 2

Core pipeline for the AI-powered Legal Due Diligence System (Pakistani corporate
and real estate law firms). Day 2 scope: **document ingestion & embedding only**.
No LLM, no memo generation — that's Day 3+.

## Folder structure

```
backend/
  app.py                          FastAPI entrypoint (POST /ingest, POST /query/{session_id})
  config.py                       All tunables: chunk size, model names, paths
  query.py                        CLI retrieval tool (no LLM)
  routers/
    ingestion.py                  Thin HTTP layer
  services/
    ingestion_service.py          Orchestrates the full pipeline per upload session
    document_processor/
      pdf_extractor.py            Native text extraction + auto OCR fallback decision
      chunker.py                  LlamaIndex SentenceSplitter (512/50), per-page chunking
    ocr/
      ocr_service.py              pdf2image + pytesseract (English+Urdu)
    embedding/
      embedding_service.py        Local sentence-transformers/all-MiniLM-L6-v2
    vectorstore/
      chroma_store.py             ChromaDB, one collection per session (UUID)
    llamaindex/
      index_manager.py            Builds/persists/loads VectorStoreIndex
    query_engine/
      retriever.py                Retrieval-only query engine (Day 3 LLM plugs in here)
  models/
    schemas.py                    All Pydantic models (DocumentMetadata, Chunk, etc.)
  utils/
    logger.py                     Centralized logging (every stage logged)
    text_cleaning.py               Cleaning that preserves clause numbering/sections
    validators.py                  Extension/size/corruption/password checks
  logs/, uploads/, indexes/        Runtime data (gitignored in practice)
```

## Data flow

1. **Upload** — a bundle of PDFs (e.g. Sale Deed, Registry, NOC, Mutation, Tax
   Certificate) hits `POST /ingest`. A new `session_id` (UUID) is minted —
   this becomes the ChromaDB collection name and the index folder name.
2. **Validate** — extension, size, then `pikepdf` integrity check catches
   password-protected/corrupted files *before* heavier processing.
3. **Extract** (`pdf_extractor.py`) — `pdfplumber` pulls native text per
   page. If a page has fewer than `MIN_TEXT_CHARS_PER_PAGE` characters
   (i.e. it's a scanned image, stamp-only page, etc.), OCR is triggered
   automatically — no manual flag required.
4. **OCR** (`ocr_service.py`) — `pdf2image` rasterizes just that page,
   `pytesseract` runs with `eng+urd` language data to handle mixed
   English/Urdu clauses common in Fard/Intiqal/Mutation records.
5. **Clean** (`text_cleaning.py`) — removes OCR artifacts and rejoins
   broken line-wraps, while explicitly *not* merging lines that start a
   new numbered clause/section, so legal structure survives.
6. **Chunk** (`chunker.py`) — LlamaIndex `SentenceSplitter`, chunk_size=512,
   chunk_overlap=50, run **per page** (not on the whole concatenated
   document) so every chunk's `page_number` metadata stays accurate.
7. **Embed** (`embedding_service.py`) — local
   `sentence-transformers/all-MiniLM-L6-v2`, zero API calls, satisfying
   client-confidentiality requirements for unreleased legal documents.
8. **Store + Index** (`chroma_store.py` + `index_manager.py`) — vectors go
   into a per-session ChromaDB collection; a LlamaIndex `VectorStoreIndex`
   wraps it and is persisted to `indexes/<session_id>/`, so it can be
   reloaded without re-embedding.
9. **Query** (`retriever.py` / `query.py`) — retrieval only, top-k chunks
   with similarity score, filename, page number, and text. No synthesis.

## Where Day 3 plugs in

`services/query_engine/retriever.py` already returns typed
`RetrievedChunk` objects (filename, page, score, text). Day 3's
memo-generation LLM (Groq Llama 3.3 70B in dev, Claude Sonnet in
production) becomes a new service — e.g. `services/llm/memo_generator.py`
— that takes a list of `RetrievedChunk` as context and a prompt template,
and produces a structured due-diligence memo with citations back to
`filename` + `page_number`. No change to ingestion is needed; this is
exactly why retrieval and generation were kept as separate modules.

## Why this isn't a generic RAG chatbot

- **Per-page chunking + page-level metadata everywhere** → every retrieved
  chunk can be cited back to an exact page, which is non-negotiable for
  legal review (vs. a chatbot that just needs "a source").
- **Automatic OCR fallback with Urdu support** → Pakistani land records
  (Fard, Intiqal, Registry) are frequently scanned and bilingual; this is
  handled without any manual user intervention.
- **Clause-aware cleaning** → numbered clauses and section titles are
  protected during cleaning specifically so later retrieval/citation
  doesn't garble "Clause 4.2(a)" into an unreferenceable blob.
- **Session-isolated collections (UUID)** → two concurrent client
  engagements never cross-contaminate retrieval results, which matters
  for conflict-of-interest and confidentiality reasons at a law firm.
- **Transaction-type metadata** (`property` / `loan` / `acquisition`) on
  every chunk → Day 3 can filter retrieval by deal type before synthesis.

## Running it

```bash
pip install -r requirements.txt
# system dependency for OCR:
#   apt-get install tesseract-ocr tesseract-ocr-urd poppler-utils

uvicorn app:app --reload

# in another terminal, after an ingest call returns a session_id:
python query.py --session <session_id> --question "Is there a registered mutation?"
```
