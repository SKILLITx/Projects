"""
routers/ingestion.py

Thin HTTP layer. All real logic lives in services/. Exposes:
  POST /ingest        - upload a bundle of PDFs for one session
  POST /query/{sid}    - retrieval-only query against a session's index
"""

from typing import List

from fastapi import APIRouter, File, Form, HTTPException, UploadFile

from models.schemas import QueryResult, TransactionType, UploadSessionResult
from services.ingestion_service import IngestionService
from services.query_engine.retriever import LegalRetriever
from utils.logger import get_logger

router = APIRouter()
logger = get_logger(__name__)

ingestion_service = IngestionService()
retriever = LegalRetriever()


@router.post("/ingest", response_model=UploadSessionResult)
async def ingest_bundle(
    files: List[UploadFile] = File(...),
    transaction_type: TransactionType = Form(TransactionType.UNSPECIFIED),
):
    if not files:
        raise HTTPException(status_code=400, detail="No files provided.")

    file_tuples = []
    for f in files:
        content = await f.read()
        file_tuples.append((f.filename, content))

    result = ingestion_service.ingest_bundle(file_tuples, transaction_type=transaction_type)
    return result


@router.post("/query/{session_id}", response_model=QueryResult)
def query_session(session_id: str, question: str, top_k: int = 5):
    try:
        results = retriever.query(session_id=session_id, question=question, top_k=top_k)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

    return QueryResult(query=question, session_id=session_id, results=results)
