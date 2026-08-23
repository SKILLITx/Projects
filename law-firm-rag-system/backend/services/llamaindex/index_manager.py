"""
services/llamaindex/index_manager.py

STEP 8: builds a LlamaIndex VectorStoreIndex backed by the ChromaDB
collection for a session, persists it to disk, and supports reloading
an existing index later (e.g. for Day 3's query engine, or if the
FastAPI process restarts mid-engagement).
"""

from pathlib import Path
from typing import List

from llama_index.core import StorageContext, VectorStoreIndex, Settings as LlamaSettings
from llama_index.core.schema import TextNode
from llama_index.vector_stores.chroma import ChromaVectorStore

from config import settings as app_settings
from models.schemas import Chunk
from services.embedding.embedding_service import EmbeddingService
from services.vectorstore.chroma_store import ChromaStore
from utils.logger import get_logger

logger = get_logger(__name__)


class IndexManager:
    def __init__(self):
        self.chroma_store = ChromaStore()
        self.embedding_service = EmbeddingService()
        # Bind our local embedding model globally for LlamaIndex so the
        # index never tries to reach out to OpenAI by default.
        LlamaSettings.embed_model = self.embedding_service.model
        LlamaSettings.llm = None  # No LLM today — retrieval only (per spec).

    def _persist_dir(self, session_id: str) -> Path:
        path = app_settings.INDEX_DIR / session_id
        path.mkdir(parents=True, exist_ok=True)
        return path

    def build_index(self, session_id: str, chunks: List[Chunk]) -> VectorStoreIndex:
        collection = self.chroma_store.get_or_create_collection(session_id)
        vector_store = ChromaVectorStore(chroma_collection=collection)
        storage_context = StorageContext.from_defaults(vector_store=vector_store)

        nodes = [
            TextNode(text=chunk.text, id_=chunk.metadata.chunk_id, metadata=chunk.metadata.model_dump(mode="json"))
            for chunk in chunks
        ]

        index = VectorStoreIndex(nodes=nodes, storage_context=storage_context)
        index.storage_context.persist(persist_dir=str(self._persist_dir(session_id)))
        logger.info(f"Index created and persisted for session '{session_id}' ({len(nodes)} node(s)).")
        return index

    def load_index(self, session_id: str) -> VectorStoreIndex:
        if not self.chroma_store.collection_exists(session_id):
            raise FileNotFoundError(f"No index/collection found for session '{session_id}'.")

        collection = self.chroma_store.get_or_create_collection(session_id)
        vector_store = ChromaVectorStore(chroma_collection=collection)
        index = VectorStoreIndex.from_vector_store(vector_store=vector_store)
        logger.info(f"Loaded existing index for session '{session_id}'.")
        return index
