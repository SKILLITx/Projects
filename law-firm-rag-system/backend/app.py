"""
app.py

FastAPI entrypoint. Run with:
    uvicorn app:app --reload
"""

from fastapi import FastAPI

from routers.ingestion import router as ingestion_router

app = FastAPI(
    title="Legal Due Diligence Ingestion API",
    description="Day 2: Document ingestion & embedding pipeline for Pakistani legal due diligence.",
    version="0.2.0",
)

app.include_router(ingestion_router, tags=["ingestion"])


@app.get("/health")
def health_check():
    return {"status": "ok"}
