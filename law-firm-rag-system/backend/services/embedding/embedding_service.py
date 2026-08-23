"""
services/embedding/embedding_service.py

STEP 6: generates embeddings locally via
sentence-transformers/all-MiniLM-L6-v2. No network/API calls — this
matters because legal documents (sale deeds, loan agreements, SECP
filings) cannot be sent to a third-party embedding API for client
confidentiality reasons.

Wrapped as a LlamaIndex HuggingFaceEmbedding so it plugs directly into
VectorStoreIndex in services/llamaindex/index_manager.py.
"""

from typing import List

from llama_index.embeddings.huggingface import HuggingFaceEmbedding

from config import settings
from utils.logger import get_logger

logger = get_logger(__name__)


class EmbeddingService:
    _model: HuggingFaceEmbedding | None = None  # lazy singleton, model load is expensive

    def __init__(self, model_name: str = settings.EMBEDDING_MODEL_NAME):
        self.model_name = model_name
        if EmbeddingService._model is None:
            logger.info(f"Loading local embedding model '{model_name}'...")
            EmbeddingService._model = HuggingFaceEmbedding(model_name=model_name)
            logger.info("Embedding model loaded.")

    @property
    def model(self) -> HuggingFaceEmbedding:
        return EmbeddingService._model

    def embed_texts(self, texts: List[str]) -> List[List[float]]:
        vectors = self.model.get_text_embedding_batch(texts, show_progress=False)
        logger.info(f"Embedding generation complete for {len(texts)} chunk(s).")
        return vectors

    def embed_query(self, query: str) -> List[float]:
        return self.model.get_query_embedding(query)
