"""
services/query_engine/retriever.py

STEP 9: retrieval-only query engine. Deliberately has NO LLM wired in —
Day 2 scope is ingestion + retrieval verification only. Day 3 will plug
a synthesis/memo-generation LLM (Groq Llama 3.3 70B in dev, Claude
Sonnet in production) on top of exactly this retriever, using the same
RetrievedChunk objects as its source-of-truth context.
"""

from typing import List

from services.llamaindex.index_manager import IndexManager
from models.schemas import RetrievedChunk
from utils.logger import get_logger

logger = get_logger(__name__)


class LegalRetriever:
    def __init__(self, index_manager: IndexManager | None = None):
        self.index_manager = index_manager or IndexManager()

    def query(self, session_id: str, question: str, top_k: int = 5) -> List[RetrievedChunk]:
        index = self.index_manager.load_index(session_id)
        retriever = index.as_retriever(similarity_top_k=top_k)
        nodes = retriever.retrieve(question)

        results: List[RetrievedChunk] = []
        for rank, node_with_score in enumerate(nodes, start=1):
            node = node_with_score.node
            meta = node.metadata or {}
            results.append(
                RetrievedChunk(
                    rank=rank,
                    similarity_score=float(node_with_score.score or 0.0),
                    filename=meta.get("filename", "unknown"),
                    page_number=meta.get("page_number", -1),
                    text=node.get_content(),
                    document_id=meta.get("document_id", "unknown"),
                )
            )

        logger.info(f"Query executed for session '{session_id}': '{question}' -> {len(results)} result(s).")
        return results
