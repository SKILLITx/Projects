#!/usr/bin/env python3
"""
Pre-flight check.

Run this before a demo. It replaces the previous ``test_pipeline.py``, which
was a manual harness with no assertions that printed a green tick regardless of
what had actually happened — including when the API key was absent and the
whole generation step had silently been skipped.

This reports, honestly, which parts of the system are ready and which are not,
and exits non-zero if anything essential is missing.

    python verify_setup.py                 # check the environment
    python verify_setup.py path/to.pdf     # also run ingestion on a real file
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

GREEN, RED, YELLOW, BLUE, DIM, RESET = (
    "\033[32m", "\033[31m", "\033[33m", "\033[34m", "\033[2m", "\033[0m"
)

results: list[tuple[str, bool, str]] = []


def check(label: str, ok: bool, detail: str = "", *, essential: bool = True) -> bool:
    icon = f"{GREEN}PASS{RESET}" if ok else (
        f"{RED}FAIL{RESET}" if essential else f"{YELLOW}WARN{RESET}")
    print(f"  [{icon}] {label}")
    if detail:
        print(f"         {DIM}{detail}{RESET}")
    results.append((label, ok or not essential, detail))
    return ok


def heading(text: str) -> None:
    print(f"\n{BLUE}{text}{RESET}\n{DIM}{'─' * 66}{RESET}")


def main() -> int:
    print(f"\n{BLUE}{'═' * 66}\n  LEGAL RAG SYSTEM — PRE-FLIGHT CHECK\n{'═' * 66}{RESET}")

    # ── Configuration ────────────────────────────────────────────────────
    heading("1. Configuration")
    try:
        from core.config import city_profiles, get_settings, housing_societies
        settings = get_settings()
        check("Settings load", True,
              f"v{settings.app_version}, log level {settings.log_level}")
        check("Groq API key present", settings.llm_configured,
              "Set GROQ_API_KEY in backendd/.env — reviews cannot run without it.")
        check("City profiles", len(city_profiles()) > 0,
              f"{len(city_profiles())} cities: {', '.join(sorted(city_profiles()))}")
        check("Housing societies", len(housing_societies()) > 0,
              f"{len(housing_societies())} configured", essential=False)
        check("Authentication", True,
              "ENABLED — X-API-Key required" if settings.auth_enabled
              else "disabled (open access; set API_KEY to enable)",
              essential=False)
    except Exception as exc:                                 # noqa: BLE001
        check("Settings load", False, str(exc))
        return 1

    # ── Dependencies ─────────────────────────────────────────────────────
    heading("2. Python dependencies")
    for module, label, essential in [
        ("fastapi", "FastAPI", True),
        ("pdfplumber", "pdfplumber (PDF text)", True),
        ("docx", "python-docx (Word output)", True),
        ("reportlab", "reportlab (PDF output)", True),
        ("chromadb", "ChromaDB (vector store)", True),
        ("llama_index.core", "LlamaIndex core", True),
        ("sentence_transformers", "sentence-transformers (embeddings)", True),
        ("langdetect", "langdetect", False),
        ("pytesseract", "pytesseract (OCR)", False),
    ]:
        try:
            __import__(module)
            check(label, True, essential=essential)
        except ImportError as exc:
            check(label, False, str(exc), essential=essential)

    # ── OCR toolchain ────────────────────────────────────────────────────
    heading("3. OCR toolchain")
    try:
        from core.document_processor import probe_ocr
        capability = probe_ocr()
        check("Tesseract binary", capability.tesseract,
              f"{settings.tesseract_cmd}", essential=False)
        check("Poppler (pdftoppm)", capability.poppler,
              "Required to rasterise scanned pages.", essential=False)
        urdu = "urd" in capability.languages
        check("Urdu language pack", urdu,
              f"Installed languages: {', '.join(capability.languages[:12]) or 'none detected'}",
              essential=False)
        if not capability.available:
            print(f"         {YELLOW}Scanned PDFs will yield no text without OCR.{RESET}")
    except Exception as exc:                                 # noqa: BLE001
        check("OCR probe", False, str(exc), essential=False)

    # ── Storage ──────────────────────────────────────────────────────────
    heading("4. Storage")
    try:
        settings.ensure_directories()
        check("Directories writable", True,
              f"{settings.upload_dir.name}/, {settings.output_dir.name}/, "
              f"{settings.chroma_dir.name}/")
        from core.store import SessionStore
        store = SessionStore(settings.db_path, ttl_hours=settings.session_ttl_hours)
        check("Session store", True,
              f"{settings.db_path.name} — {store.total()} session(s) on record")
    except Exception as exc:                                 # noqa: BLE001
        check("Storage", False, str(exc))

    # ── Statutory corpus ─────────────────────────────────────────────────
    heading("5. Statutory corpus")
    statutes = sorted(settings.corpus_dir.glob("*.pdf")) if settings.corpus_dir.exists() else []
    check("Statute PDFs present", bool(statutes),
          ", ".join(p.name for p in statutes) or
          f"Drop Pakistani statute PDFs into {settings.corpus_dir}")
    try:
        from core.indexer import corpus_stats
        stats = corpus_stats()
        check("Corpus indexed", stats["vectors"] > 0,
              f"{stats['vectors']} vectors, chunk_size={stats['chunk_size']}, "
              f"overlap={stats['chunk_overlap']}"
              if stats["vectors"] else
              "Not yet built — the first review will index it (about a minute).",
              essential=False)
    except Exception as exc:                                 # noqa: BLE001
        check("Corpus index", False, str(exc), essential=False)

    # ── Checklist assembly (no model required) ───────────────────────────
    heading("6. Checklist assembly")
    try:
        from core.checklist import RED_FLAG_RULES, build_checklist
        base = build_checklist("property", {}, "islamabad")
        full = build_checklist(
            "property",
            {"is_inherited": True, "benami_risk": True, "aml_threshold": True,
             "detected_value_pkr": 25_000_000},
            "lahore", "DHA Lahore")
        check("Base checklist", len(base) == 15, f"{len(base)} questions")
        check("Supplementary injection", len(full) > len(base),
              f"{len(full)} questions with all flags active")
        check("City wiring", "Capital Development Authority" in
              next(i.question for i in base if i.topic == "noc"),
              "NOC questions name the selected city's authority")
        check("Red-flag rules", len(RED_FLAG_RULES) > 0,
              f"{len(RED_FLAG_RULES)} deterministic rules")
    except Exception as exc:                                 # noqa: BLE001
        check("Checklist assembly", False, str(exc))

    # ── Optional: real ingestion ─────────────────────────────────────────
    if len(sys.argv) > 1:
        heading("7. Ingestion on a real document")
        path = Path(sys.argv[1])
        if not path.exists():
            check("File exists", False, str(path))
        else:
            try:
                from core.document_processor import (
                    detect_special_flags, extract_text_from_pdf)
                pages = extract_text_from_pdf(path)
                readable = sum(1 for p in pages if p["text"].strip())
                check("Text extraction", readable > 0,
                      f"{len(pages)} pages, {readable} with text, "
                      f"{sum(1 for p in pages if p['has_ocr'])} OCR'd, "
                      f"{sum(1 for p in pages if p['is_urdu'])} Urdu")
                flags = detect_special_flags(pages, "property")
                check("Flag detection", True,
                      f"value=PKR {flags['detected_value_pkr']:,.0f}, "
                      f"inherited={flags['is_inherited']}, "
                      f"benami={flags['benami_risk']}, "
                      f"society={flags['housing_society'] or 'none'}")
                if flags["missing_documents"]:
                    print(f"         {DIM}Missing: "
                          f"{', '.join(flags['missing_documents'])}{RESET}")
            except Exception as exc:                         # noqa: BLE001
                check("Ingestion", False, str(exc))

    # ── Summary ──────────────────────────────────────────────────────────
    failures = [label for label, ok, _ in results if not ok]
    print(f"\n{BLUE}{'═' * 66}{RESET}")
    if failures:
        print(f"  {RED}{len(failures)} essential check(s) failed:{RESET}")
        for label in failures:
            print(f"    · {label}")
        print(f"{BLUE}{'═' * 66}{RESET}\n")
        return 1

    print(f"  {GREEN}All essential checks passed — the system is ready.{RESET}")
    print(f"  {DIM}Start the API with:  uvicorn main:app --reload{RESET}")
    print(f"{BLUE}{'═' * 66}{RESET}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
