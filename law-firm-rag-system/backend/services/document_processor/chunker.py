"""
services/document_processor/chunker.py

STEP 5: splits cleaned page text using LlamaIndex's SentenceSplitter
(chunk_size=512, chunk_overlap=50), attaching full traceability
metadata to every chunk. We chunk per-page (not by concatenating the
whole document) specifically so that page_number metadata stays
accurate for citations — a lawyer must be able to jump straight to the
source page.
"""

from typing import List

from llama_index.core.node_parser import SentenceSplitter
from llama_index.core.schema import Document as LlamaDocument

from config import settings
from models.schemas import Chunk, ChunkMetadata, PageContent, TransactionType
from utils.logger import get_logger
from utils.text_cleaning import clean_text

logger = get_logger(__name__)


class DocumentChunker:
    def __init__(self, chunk_size: int = settings.CHUNK_SIZE, chunk_overlap: int = settings.CHUNK_OVERLAP):
        self.splitter = SentenceSplitter(chunk_size=chunk_size, chunk_overlap=chunk_overlap)

    def chunk_pages(
        self,
        pages: List[PageContent],
        session_id: str,
        transaction_type: TransactionType,
    ) -> List[Chunk]:
        chunks: List[Chunk] = []
        chunk_counter = 0

        for page in pages:
            cleaned = clean_text(page.text)
            if not cleaned:
                continue

            llama_doc = LlamaDocument(text=cleaned)
            nodes = self.splitter.get_nodes_from_documents([llama_doc])

            for node in nodes:
                metadata = ChunkMetadata(
                    document_id=page.document_id,
                    filename=page.filename,
                    page_number=page.page_number,
                    transaction_type=transaction_type,
                    session_id=session_id,
                    chunk_index=chunk_counter,
                )
                chunks.append(Chunk(text=node.get_content(), metadata=metadata))
                chunk_counter += 1

        logger.info(f"Chunking complete: produced {len(chunks)} chunk(s) for session '{session_id}'.")
        return chunks
