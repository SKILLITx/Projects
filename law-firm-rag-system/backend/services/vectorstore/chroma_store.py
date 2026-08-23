"""
services/vectorstore/chroma_store.py

STEP 7: ChromaDB persistence, one collection per upload session, named
with a UUID (the session_id itself). Isolating collections per session
means two simultaneous due-diligence engagements at the firm never mix
documents in retrieval results.
"""

import chromadb
from chromadb.config import Settings as ChromaSettings

from config import settings
from utils.logger import get_logger

logger = get_logger(__name__)


class ChromaStore:
    def __init__(self):
        self.client = chromadb.PersistentClient(
            path=str(settings.CHROMA_PERSIST_DIR),
            settings=ChromaSettings(anonymized_telemetry=False),
        )

    def get_or_create_collection(self, session_id: str):
        """Collection name == session_id (already a UUID by construction)."""
        collection = self.client.get_or_create_collection(name=session_id)
        return collection

    def collection_exists(self, session_id: str) -> bool:
        existing = [c.name for c in self.client.list_collections()]
        return session_id in existing

    def delete_collection(self, session_id: str) -> None:
        if self.collection_exists(session_id):
            self.client.delete_collection(name=session_id)
            logger.info(f"Deleted ChromaDB collection '{session_id}'.")
