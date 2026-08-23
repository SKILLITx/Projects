"""
query.py

STEP 9: simple command-line retrieval interface. No LLM — prints the
top-k retrieved chunks with similarity score, document name, page
number, and text, so a developer/lawyer can sanity-check retrieval
quality before Day 3's memo-generation LLM is wired in.

Usage:
    python query.py --session <session_id> --question "Is there a registered mutation?"
    python query.py --session <session_id> --question "..." --top-k 5
"""

import argparse

from services.query_engine.retriever import LegalRetriever


def main():
    parser = argparse.ArgumentParser(description="Query a legal due diligence ingestion session.")
    parser.add_argument("--session", required=True, help="Session ID (UUID) returned by /ingest.")
    parser.add_argument("--question", required=True, help="Natural language question.")
    parser.add_argument("--top-k", type=int, default=5, help="Number of chunks to retrieve.")
    args = parser.parse_args()

    retriever = LegalRetriever()
    results = retriever.query(session_id=args.session, question=args.question, top_k=args.top_k)

    print(f"\nQuestion: {args.question}\n")
    if not results:
        print("No results found.")
        return

    for r in results:
        print("-" * 80)
        print(f"Rank: {r.rank}")
        print(f"Similarity Score: {r.similarity_score:.4f}")
        print(f"Document: {r.filename}")
        print(f"Page: {r.page_number}")
        print(f"Text:\n{r.text}\n")


if __name__ == "__main__":
    main()
