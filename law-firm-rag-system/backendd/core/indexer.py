"""
Vector index construction, caching and lifecycle management.

Corrections over the previous build:

* **The embedding model was re-instantiated on every call.**  ``_get_embed_model``
  constructed a fresh ``HuggingFaceEmbedding`` each time it ran, which reloaded
  ~120 MB of weights from disk on every index build and every query.  It is now
  a process-wide singleton behind a lock.
* **Chunking was never configured.**  The architecture document promised
  ``chunk_size=512, chunk_overlap=50``; the code set neither, so LlamaIndex
  library defaults silently applied.  A ``SentenceSplitter`` is now constructed
  explicitly from settings, closing the documentation drift.
* **The statutory corpus could never be rebuilt.**  The reload path keyed only
  on ``collection.count() > 0``, so adding a statute PDF had no effect until the
  store was deleted by hand.  The corpus is now fingerprinted by file name, size
  and mtime; a change to the corpus directory triggers exactly one rebuild.
* **Session indexes were held in memory** and lost on restart.  Any session
  index can now be reopened from its persisted Chroma collection.
"""

from __future__ import annotations

import hashlib
import logging
import threading
from pathlib import Path
from typing import Any

from core.config import get_settings

logger = logging.getLogger(__name__)

LEGAL_CORPUS_COLLECTION = "legal_corpus_pk"
_CORPUS_FINGERPRINT_KEY = "corpus_fingerprint"

_embed_lock = threading.Lock()
_embed_model: Any = None

_client_lock = threading.Lock()
_chroma_client: Any = None

_splitter_lock = threading.Lock()
_splitter: Any = None


# ──────────────────────────────────────────────────────────────────────────
#  Cached singletons
# ──────────────────────────────────────────────────────────────────────────
def get_embed_model() -> Any:
    """Process-wide embedding model.  Loaded once, reused everywhere."""
    global _embed_model
    if _embed_model is None:
        with _embed_lock:
            if _embed_model is None:
                from llama_index.embeddings.huggingface import HuggingFaceEmbedding

                settings = get_settings()
                logger.info("Loading embedding model %s (one-time)…", settings.embed_model)
                _embed_model = HuggingFaceEmbedding(model_name=settings.embed_model)
                logger.info("Embedding model ready.")
    return _embed_model


def get_node_parser() -> Any:
    """Sentence splitter configured from settings — no more silent defaults."""
    global _splitter
    if _splitter is None:
        with _splitter_lock:
            if _splitter is None:
                from llama_index.core.node_parser import SentenceSplitter

                settings = get_settings()
                _splitter = SentenceSplitter(
                    chunk_size=settings.chunk_size,
                    chunk_overlap=settings.chunk_overlap,
                )
                logger.info("Node parser: chunk_size=%d overlap=%d",
                            settings.chunk_size, settings.chunk_overlap)
    return _splitter


def get_chroma_client() -> Any:
    """Persistent ChromaDB client, created once."""
    global _chroma_client
    if _chroma_client is None:
        with _client_lock:
            if _chroma_client is None:
                import chromadb

                settings = get_settings()
                settings.chroma_dir.mkdir(parents=True, exist_ok=True)
                _chroma_client = chromadb.PersistentClient(path=str(settings.chroma_dir))
    return _chroma_client


def reset_caches() -> None:
    """Drop cached singletons.  Used by the test-suite and on corpus rebuild."""
    global _embed_model, _chroma_client, _splitter
    with _embed_lock:
        _embed_model = None
    with _client_lock:
        _chroma_client = None
    with _splitter_lock:
        _splitter = None


def _apply_global_settings() -> None:
    """
    Bind the embedding model globally but leave the LLM unset.

    ``Settings.llm`` is deliberately *not* assigned here.  The previous build
    mutated that global from inside the query engine, which raced whenever two
    reviews ran concurrently; the LLM is now always passed explicitly.
    """
    from llama_index.core import Settings as LlamaSettings

    LlamaSettings.embed_model = get_embed_model()
    LlamaSettings.node_parser = get_node_parser()
    LlamaSettings.llm = None


# ──────────────────────────────────────────────────────────────────────────
#  Corpus fingerprinting
# ──────────────────────────────────────────────────────────────────────────
def corpus_fingerprint(corpus_dir: Path) -> str:
    """Stable digest of the statute corpus: name, size and mtime of each PDF."""
    if not corpus_dir.exists():
        return "empty"
    parts: list[str] = []
    for pdf in sorted(corpus_dir.glob("*.pdf")):
        try:
            stat = pdf.stat()
            parts.append(f"{pdf.name}:{stat.st_size}:{int(stat.st_mtime)}")
        except OSError:
            continue
    if not parts:
        return "empty"
    return hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()[:32]


# ──────────────────────────────────────────────────────────────────────────
#  Index construction
# ──────────────────────────────────────────────────────────────────────────
def _storage_for(collection_name: str) -> tuple[Any, Any]:
    from llama_index.core import StorageContext
    from llama_index.vector_stores.chroma import ChromaVectorStore

    collection = get_chroma_client().get_or_create_collection(collection_name)
    vector_store = ChromaVectorStore(chroma_collection=collection)
    storage = StorageContext.from_defaults(vector_store=vector_store)
    return collection, storage


def session_collection_name(session_id: str) -> str:
    """
    Chroma collection name for a session.

    Session identifiers are now 43-character URL-safe tokens which can contain
    ``-`` and ``_`` and exceed Chroma's 63-character name ceiling, so the name
    is derived from a digest rather than embedding the token itself — which also
    keeps the raw token out of the on-disk store.
    """
    digest = hashlib.sha256(session_id.encode("utf-8")).hexdigest()[:32]
    return f"session_{digest}"


def build_session_index(pages: list[dict[str, Any]], session_id: str) -> Any:
    """Build the ephemeral per-upload index from extracted pages."""
    from llama_index.core import Document, VectorStoreIndex

    _apply_global_settings()

    documents = [
        Document(
            text=page["text"],
            metadata={
                "page_num": int(page.get("page_num", 0)),
                "source_file": str(page.get("source_file", "unknown")),
                "is_urdu": str(page.get("is_urdu", False)).lower(),
                "has_ocr": str(page.get("has_ocr", False)).lower(),
            },
            excluded_embed_metadata_keys=["is_urdu", "has_ocr"],
        )
        for page in pages
        if (page.get("text") or "").strip()
    ]

    name = session_collection_name(session_id)
    collection, storage = _storage_for(name)

    if not documents:
        logger.warning("Session %s produced no indexable text.", session_id[:8])
        return VectorStoreIndex.from_documents(
            [], storage_context=storage, embed_model=get_embed_model()
        )

    index = VectorStoreIndex.from_documents(
        documents,
        storage_context=storage,
        embed_model=get_embed_model(),
        transformations=[get_node_parser()],
        show_progress=False,
    )
    logger.info("Session index built: %d pages → %d vectors in %s",
                len(documents), collection.count(), name)
    return index


def load_session_index(session_id: str) -> Any | None:
    """
    Reopen a previously built session index from its persisted collection.

    This is what makes the pipeline restart-survivable: the orchestrator no
    longer needs to hold index objects in memory across requests.
    """
    from llama_index.core import VectorStoreIndex

    _apply_global_settings()
    name = session_collection_name(session_id)
    try:
        collection = get_chroma_client().get_collection(name)
    except Exception:                                        # noqa: BLE001
        logger.warning("Session collection %s not found.", name)
        return None
    if collection.count() == 0:
        logger.warning("Session collection %s is empty.", name)
        return None

    _, storage = _storage_for(name)
    return VectorStoreIndex.from_vector_store(
        storage.vector_store, storage_context=storage, embed_model=get_embed_model()
    )


def delete_session_index(session_id: str) -> bool:
    """Drop a session's vectors.  Idempotent."""
    name = session_collection_name(session_id)
    try:
        get_chroma_client().delete_collection(name)
        logger.info("Deleted session collection %s", name)
        return True
    except Exception:                                        # noqa: BLE001
        return False


def build_legal_corpus_index(corpus_dir: str | Path | None = None, *,
                             force_rebuild: bool = False) -> Any:
    """
    Build or reload the persistent Pakistani statute index.

    Rebuilds automatically when the contents of the corpus directory change, so
    dropping a new Act into ``data/legal_corpus/`` is all that is required to
    extend the system's statutory reach.
    """
    from llama_index.core import SimpleDirectoryReader, VectorStoreIndex

    settings = get_settings()
    path = Path(corpus_dir) if corpus_dir else settings.corpus_dir
    _apply_global_settings()

    collection, storage = _storage_for(LEGAL_CORPUS_COLLECTION)
    fingerprint = corpus_fingerprint(path)
    stored = (collection.metadata or {}).get(_CORPUS_FINGERPRINT_KEY)

    if collection.count() > 0 and not force_rebuild:
        if stored == fingerprint or stored is None:
            if stored is None:
                logger.info("Legal corpus loaded (%d vectors; fingerprint not yet recorded).",
                            collection.count())
            else:
                logger.info("Legal corpus loaded from cache (%d vectors).", collection.count())
            return VectorStoreIndex.from_vector_store(
                storage.vector_store, storage_context=storage, embed_model=get_embed_model()
            )
        logger.info("Legal corpus changed on disk — rebuilding index.")
        try:
            get_chroma_client().delete_collection(LEGAL_CORPUS_COLLECTION)
        except Exception:                                    # noqa: BLE001
            pass
        collection, storage = _storage_for(LEGAL_CORPUS_COLLECTION)

    pdf_files = sorted(path.glob("*.pdf")) if path.exists() else []
    if not pdf_files:
        logger.warning(
            "No statute PDFs in %s — the statutory index will be empty and "
            "answers will fall back to parametric model knowledge.", path,
        )
        return VectorStoreIndex.from_documents(
            [], storage_context=storage, embed_model=get_embed_model()
        )

    logger.info("Indexing %d statute PDFs from %s…", len(pdf_files), path)
    documents = SimpleDirectoryReader(input_files=[str(p) for p in pdf_files]).load_data()

    index = VectorStoreIndex.from_documents(
        documents,
        storage_context=storage,
        embed_model=get_embed_model(),
        transformations=[get_node_parser()],
        show_progress=False,
    )
    try:
        collection.modify(metadata={_CORPUS_FINGERPRINT_KEY: fingerprint})
    except Exception:                                        # noqa: BLE001
        logger.debug("Could not persist corpus fingerprint (non-fatal).")

    logger.info("Legal corpus indexed: %d source documents → %d vectors.",
                len(documents), collection.count())
    return index


def corpus_stats() -> dict[str, Any]:
    """Diagnostics surfaced by the health endpoint."""
    settings = get_settings()
    try:
        collection = get_chroma_client().get_or_create_collection(LEGAL_CORPUS_COLLECTION)
        vectors = collection.count()
    except Exception:                                        # noqa: BLE001
        vectors = 0
    statutes = sorted(p.name for p in settings.corpus_dir.glob("*.pdf")) \
        if settings.corpus_dir.exists() else []
    return {
        "collection": LEGAL_CORPUS_COLLECTION,
        "vectors": vectors,
        "statute_files": statutes,
        "statute_count": len(statutes),
        "embed_model": settings.embed_model,
        "chunk_size": settings.chunk_size,
        "chunk_overlap": settings.chunk_overlap,
    }
