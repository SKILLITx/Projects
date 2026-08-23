"""
PDF ingestion, OCR fallback, language detection and deterministic flagging.

Substantive corrections over the previous build:

* **Monetary extraction was unbounded and unit-blind.**  A thirteen-digit CNIC
  or a plot number could be read as a rupee amount and silently trip the
  ``PKR 10M`` anti-money-laundering threshold.  Extraction now requires a
  currency cue, understands ``lakh`` / ``crore`` / ``million`` / ``billion``,
  rejects values outside a plausible band, and refuses to read digit runs that
  look like identity or account numbers.
* **Flag detection matched bare substrings.**  ``"on behalf of"`` fired the
  benami flag on wholly innocent recitals, and — worse — a sentence reading
  ``"there is no ongoing litigation"`` contained the literal trigger phrase.
  Matching is now word-boundary regex with a negation window, so a negated
  statement suppresses rather than raises the flag.
* **Urdu detection relied on a twelve-word lexicon plus a probabilistic
  detector that raises on short input.**  Detection now also measures the
  proportion of Arabic-script codepoints, which is robust on OCR output.
* **OCR failed opaquely.**  Missing Poppler or Tesseract binaries produced a
  bare exception; the toolchain is now probed once and reported precisely.
"""

from __future__ import annotations

import logging
import re
import shutil
import unicodedata
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable

from core.config import document_taxonomy, get_settings
from core.exceptions import CorruptPdfError

logger = logging.getLogger(__name__)

PDF_MAGIC = b"%PDF-"


# ──────────────────────────────────────────────────────────────────────────
#  Domain vocabulary
# ──────────────────────────────────────────────────────────────────────────
URDU_INDICATORS: tuple[str, ...] = (
    "واقع", "موضع", "مالک", "بیع", "خریدار", "فروخت",
    "قبضہ", "رجسٹری", "انتقال", "فرد", "مالکیت", "تحصیل",
    "جمع بندی", "خسرہ", "وراثت", "منتقلی",
)

# Arabic-script Unicode blocks used by Urdu.
_URDU_RANGES: tuple[tuple[int, int], ...] = (
    (0x0600, 0x06FF),   # Arabic
    (0x0750, 0x077F),   # Arabic Supplement
    (0x08A0, 0x08FF),   # Arabic Extended-A
    (0xFB50, 0xFDFF),   # Arabic Presentation Forms-A
    (0xFE70, 0xFEFF),   # Arabic Presentation Forms-B
)

INHERITED_INDICATORS: tuple[str, ...] = (
    "late", "deceased", "legal heirs of", "legal heir of", "virasat",
    "succession", "inheritance", "inherited", "marhoom", "warisan",
    "tarka", "succession certificate", "heirship",
)

BENAMI_INDICATORS: tuple[str, ...] = (
    "on behalf of", "beneficial owner", "beneficial ownership",
    "in trust for", "benamidar", "benami", "ostensible owner",
    "name lender", "front man",
)

AML_INDICATORS: tuple[str, ...] = (
    "source of funds", "beneficial owner", "payment receipt",
    "bank transfer", "demand draft", "pay order", "telegraphic transfer",
    "cash payment", "remittance",
)

LITIGATION_INDICATORS: tuple[str, ...] = (
    "suit pending", "pending litigation", "ongoing litigation",
    "court order", "injunction", "caveat", "stay order",
    "decree against", "lis pendens", "attachment order",
)

ENCUMBRANCE_INDICATORS: tuple[str, ...] = (
    "mortgage", "charge", "lien", "hypothecation", "encumbrance",
    "pledged", "equitable mortgage",
)

HOUSING_SOCIETY_PATTERNS: dict[str, tuple[str, ...]] = {
    "DHA Islamabad": ("dha islamabad", "defence housing authority islamabad"),
    "DHA Lahore": ("dha lahore", "defence housing authority lahore"),
    "Bahria Town Rawalpindi": ("bahria town rawalpindi", "bahria rawalpindi"),
    "Bahria Town Lahore": ("bahria town lahore", "bahria lahore"),
}

CONSTITUTIONAL_MAP: dict[str, str] = {
    "title": "Article 23 — Right to acquire and dispose of property",
    "noc": "Article 24 — Protection of property rights",
    "encumbrance": "Article 24 — Protection of property rights",
    "co-owner": "Article 25 — Equality of citizens",
    "litigation": "Article 24 — Protection of property rights",
    "ownerless": "Article 172 — Property vesting in Federal/Provincial government",
    "tax": "Article 23 — Right to acquire property subject to law",
    "inheritance": "Article 23 — Right to acquire and dispose of property",
    "benami": "Article 24 — Protection against unlawful deprivation",
    "mutation": "Article 23 — Right to acquire and dispose of property",
    "aml": "Article 23 — Right to acquire property subject to law",
    "housing_society": "Article 24 — Protection of property rights",
    "boundaries": "Article 24 — Protection of property rights",
    "consideration": "Article 23 — Right to acquire property subject to law",
    "attestation": "Article 4 — Right of individuals to be dealt with in accordance with law",
    "land_use": "Article 24 — Protection of property rights",
    "utilities": "Article 9 — Security of person",
    "cnic": "Article 4 — Right of individuals to be dealt with in accordance with law",
    "possession": "Article 24 — Protection of property rights",
    "conditions": "Article 23 — Right to acquire and dispose of property",
    "general": "Article 23 — Right to acquire and dispose of property",
}

DEFAULT_CONSTITUTIONAL_BASIS = "Article 23 — Right to acquire and dispose of property"

# Document-type recognition, used to report which required documents are absent.
DOCUMENT_TYPE_PATTERNS: dict[str, tuple[str, ...]] = {
    "Fard-e-Malkiat": ("fard-e-malkiat", "fard e malkiat", "fard malkiat", "فرد مالکیت", "record of rights"),
    "Intiqal": ("intiqal", "inteqal", "mutation", "انتقال"),
    "Registry": ("registry", "registered deed", "sale deed", "رجسٹری", "conveyance deed"),
    "Aks Shajra": ("aks shajra", "shajra kishtwar", "shajra nasb", "عکس شجرہ"),
    "Jamabandi": ("jamabandi", "jama bandi", "جمع بندی"),
    "NOC": ("no objection certificate", "noc"),
    "CNIC": ("cnic", "computerised national identity", "computerized national identity", "شناختی کارڈ"),
    "Loan Agreement": ("loan agreement", "facility agreement", "financing agreement"),
    "Mortgage Deed": ("mortgage deed", "deed of mortgage", "charge document"),
    "Valuation Report": ("valuation report", "valuer report", "assessment of value"),
    "Insurance Policy": ("insurance policy", "policy of insurance", "takaful certificate"),
    "Share Purchase Agreement": ("share purchase agreement", "share sale agreement"),
    "Memorandum of Association": ("memorandum of association",),
    "Articles of Association": ("articles of association",),
    "SECP Certificate": ("certificate of incorporation", "secp certificate", "secp registration"),
    "Due Diligence Report": ("due diligence report", "legal due diligence"),
    "Title Documents": ("title deed", "title document", "allotment letter", "transfer letter"),
}


# ──────────────────────────────────────────────────────────────────────────
#  Negation-aware matching
# ──────────────────────────────────────────────────────────────────────────
NEGATION_CUES: tuple[str, ...] = (
    "no", "not", "never", "without", "free from", "free of", "absent",
    "absence of", "absence", "nil", "none", "neither", "nor", "clear of",
    "unencumbered", "discharged", "released", "redeemed",
    "does not", "did not", "is not", "are not", "was not", "were not",
    "cannot", "no such", "there is no", "there are no", "shall not",
    "lack of", "lacking", "devoid of", "excluding",
)

_NEGATION_WINDOW = 60          # characters scanned to the left of a match
_NEGATION_PATTERN = re.compile(
    r"\b(?:" + "|".join(re.escape(cue) for cue in NEGATION_CUES) + r")\b",
    re.IGNORECASE,
)


@lru_cache(maxsize=512)
def _phrase_pattern(phrase: str) -> re.Pattern[str]:
    """Word-boundary regex for a phrase, tolerant of variable whitespace."""
    parts = [re.escape(token) for token in phrase.split()]
    body = r"\s+".join(parts)
    prefix = r"\b" if phrase[:1].isalnum() else ""
    suffix = r"\b" if phrase[-1:].isalnum() else ""
    return re.compile(prefix + body + suffix, re.IGNORECASE)


def is_negated(text: str, start: int) -> bool:
    """Whether the match beginning at ``start`` sits inside a negation window."""
    window_start = max(0, start - _NEGATION_WINDOW)
    window = text[window_start:start]
    # A clause boundary resets negation scope: "no NOC. Litigation is pending"
    for boundary in (";", ".", " but ", " however ", " although ", " whereas "):
        cut = window.rfind(boundary)
        if cut != -1:
            window = window[cut + len(boundary):]
    return bool(_NEGATION_PATTERN.search(window))


def find_phrase(text: str, phrase: str, *, respect_negation: bool = True) -> bool:
    """
    Whether ``phrase`` occurs in ``text`` as a real, non-negated mention.

    This is the single primitive behind every deterministic flag in the system.
    """
    if not text or not phrase:
        return False
    for match in _phrase_pattern(phrase).finditer(text):
        if not respect_negation or not is_negated(text, match.start()):
            return True
    return False


def any_phrase(text: str, phrases: Iterable[str], *, respect_negation: bool = True) -> bool:
    return any(find_phrase(text, phrase, respect_negation=respect_negation) for phrase in phrases)


def matched_phrases(text: str, phrases: Iterable[str], *,
                    respect_negation: bool = True) -> list[str]:
    return [p for p in phrases if find_phrase(text, p, respect_negation=respect_negation)]


# ──────────────────────────────────────────────────────────────────────────
#  Toolchain probing
# ──────────────────────────────────────────────────────────────────────────
@dataclass(frozen=True)
class OcrCapability:
    tesseract: bool
    poppler: bool
    languages: tuple[str, ...] = ()
    detail: str = ""

    @property
    def available(self) -> bool:
        return self.tesseract and self.poppler


@lru_cache(maxsize=1)
def probe_ocr() -> OcrCapability:
    """Detect once whether the OCR toolchain is actually usable."""
    settings = get_settings()
    notes: list[str] = []

    tesseract_ok = False
    languages: tuple[str, ...] = ()
    try:
        import pytesseract                                   # noqa: PLC0415

        pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd
        resolved = shutil.which(settings.tesseract_cmd) or (
            settings.tesseract_cmd if Path(settings.tesseract_cmd).exists() else None
        )
        if resolved:
            tesseract_ok = True
            try:
                languages = tuple(pytesseract.get_languages(config=""))
            except Exception:                                # noqa: BLE001
                notes.append("Tesseract present but language list unavailable.")
        else:
            notes.append(f"Tesseract binary not found at {settings.tesseract_cmd!r}.")
    except ImportError:
        notes.append("pytesseract is not installed.")

    poppler_ok = bool(shutil.which("pdftoppm") or shutil.which("pdftoppm.exe"))
    if not poppler_ok:
        notes.append("Poppler (pdftoppm) not found on PATH — scanned pages cannot be rasterised.")

    return OcrCapability(
        tesseract=tesseract_ok,
        poppler=poppler_ok,
        languages=languages,
        detail=" ".join(notes) or "OCR toolchain available.",
    )


def _ocr_language_string() -> str:
    """Requested OCR languages, narrowed to those actually installed."""
    settings = get_settings()
    capability = probe_ocr()
    requested = [lang for lang in settings.ocr_languages.split("+") if lang]
    if not capability.languages:
        return settings.ocr_languages
    usable = [lang for lang in requested if lang in capability.languages]
    if not usable:
        return "eng" if "eng" in capability.languages else capability.languages[0]
    if len(usable) < len(requested):
        missing = sorted(set(requested) - set(usable))
        logger.warning("OCR language pack(s) missing: %s — proceeding with %s",
                       ", ".join(missing), "+".join(usable))
    return "+".join(usable)


# ──────────────────────────────────────────────────────────────────────────
#  Text normalisation and language detection
# ──────────────────────────────────────────────────────────────────────────
_WHITESPACE = re.compile(r"[^\S\n]+")
_NEWLINES = re.compile(r"\n{3,}")


def normalise_text(text: str | None) -> str:
    """NFKC-normalise, collapse whitespace, strip control characters."""
    if not text:
        return ""
    cleaned = unicodedata.normalize("NFKC", text)
    cleaned = "".join(
        ch for ch in cleaned
        if ch in "\n\t" or unicodedata.category(ch)[0] != "C"
    )
    cleaned = _WHITESPACE.sub(" ", cleaned)
    cleaned = _NEWLINES.sub("\n\n", cleaned)
    return cleaned.strip()


def urdu_ratio(text: str) -> float:
    """Proportion of letters that fall in Arabic-script Unicode blocks."""
    if not text:
        return 0.0
    letters = 0
    urdu = 0
    for ch in text:
        if not ch.isalpha():
            continue
        letters += 1
        code = ord(ch)
        if any(low <= code <= high for low, high in _URDU_RANGES):
            urdu += 1
    return (urdu / letters) if letters else 0.0


def detect_urdu(text: str) -> bool:
    """
    Whether a page carries meaningful Urdu content.

    Script ratio first (robust on OCR noise), then the domain lexicon, and only
    then the probabilistic detector — which is both slowest and least reliable
    on the short, noisy strings this pipeline produces.
    """
    if not text:
        return False
    if urdu_ratio(text) >= 0.12:
        return True
    if sum(1 for indicator in URDU_INDICATORS if indicator in text) >= 2:
        return True
    if len(text.strip()) < 40:
        return False
    try:
        from langdetect import DetectorFactory, detect       # noqa: PLC0415

        DetectorFactory.seed = 0                             # deterministic output
        return detect(text) in {"ur", "fa", "ar"}
    except Exception:                                        # noqa: BLE001
        return False


# ──────────────────────────────────────────────────────────────────────────
#  Monetary extraction
# ──────────────────────────────────────────────────────────────────────────
FBR_THRESHOLD_PKR = 5_000_000
AML_THRESHOLD_PKR = 10_000_000

# Plausibility band: below this a "value" is almost certainly a fee or a page
# number; above it, a mis-parsed identity or account number.
MIN_PLAUSIBLE_PKR = 50_000
MAX_PLAUSIBLE_PKR = 500_000_000_000          # PKR 500 billion

_MULTIPLIERS: dict[str, float] = {
    "thousand": 1e3, "lakhs": 1e5, "lakh": 1e5, "lacs": 1e5, "lac": 1e5,
    "million": 1e6, "crores": 1e7, "crore": 1e7, "karor": 1e7,
    "arab": 1e9, "billion": 1e9,
}
_MULTIPLIER_ALTERNATION = "|".join(sorted(_MULTIPLIERS, key=len, reverse=True))

_CURRENCY_CUE = r"(?:pkr|rs\.?|rupees?|₨|روپے)"

# "PKR 12,500,000"  /  "Rs. 75 lakh"  /  "rupees 2.5 crore"
_CUE_THEN_AMOUNT = re.compile(
    _CURRENCY_CUE + r"\s*([0-9][0-9,\.]*)\s*(" + _MULTIPLIER_ALTERNATION + r")?\b",
    re.IGNORECASE,
)
# "50 lakh rupees"  /  "2 crore PKR"
_AMOUNT_THEN_CUE = re.compile(
    r"\b([0-9][0-9,\.]*)\s*(" + _MULTIPLIER_ALTERNATION + r")\s*" + _CURRENCY_CUE,
    re.IGNORECASE,
)
# A bare multiplier phrase is accepted only near a consideration keyword.
_BARE_MULTIPLIER = re.compile(
    r"\b([0-9][0-9,\.]*)\s*(" + _MULTIPLIER_ALTERNATION + r")\b",
    re.IGNORECASE,
)
_CONSIDERATION_CUE = re.compile(
    r"\b(?:consideration|sale price|purchase price|total amount|value of (?:the )?property"
    r"|agreed amount|sale consideration|loan amount|facility amount|price)\b",
    re.IGNORECASE,
)
# Identity / account numbers that must never be read as money.
_IDENTITY_LIKE = re.compile(
    r"\b\d{5}-\d{7}-\d\b"                # CNIC
    r"|\b\d{13}\b"                       # bare CNIC digits
    r"|\bPK\d{2}[A-Z]{4}\d{16}\b"        # IBAN
    r"|\b\d{4}-\d{4}-\d{4}-\d{4}\b",     # card-like
    re.IGNORECASE,
)


def _parse_number(raw: str) -> float | None:
    """Parse a possibly comma-grouped decimal, rejecting nonsense."""
    cleaned = raw.replace(",", "").strip().rstrip(".")
    if not cleaned or cleaned.count(".") > 1:
        return None
    try:
        value = float(cleaned)
    except ValueError:
        return None
    return value if value > 0 else None


@dataclass
class MonetaryFinding:
    amount_pkr: float
    snippet: str
    basis: str


def extract_monetary_values(text: str) -> list[MonetaryFinding]:
    """
    Every plausible PKR amount in ``text``, with the snippet that produced it.

    Requiring a currency cue (or proximity to a consideration keyword) is what
    stops plot numbers, Khasra numbers and CNICs from being read as money.
    """
    if not text:
        return []

    masked = _IDENTITY_LIKE.sub(" [id] ", text)
    findings: list[MonetaryFinding] = []
    seen: set[tuple[int, float]] = set()

    def _record(number: float, multiplier: str | None, match: re.Match[str], basis: str) -> None:
        factor = _MULTIPLIERS.get((multiplier or "").lower(), 1.0)
        amount = number * factor
        if not (MIN_PLAUSIBLE_PKR <= amount <= MAX_PLAUSIBLE_PKR):
            return
        key = (match.start(), amount)
        if key in seen:
            return
        seen.add(key)
        start = max(0, match.start() - 40)
        snippet = masked[start:match.end() + 40].strip()
        findings.append(MonetaryFinding(amount_pkr=amount, snippet=snippet, basis=basis))

    for match in _CUE_THEN_AMOUNT.finditer(masked):
        number = _parse_number(match.group(1))
        if number is not None:
            _record(number, match.group(2), match, "currency cue before amount")

    for match in _AMOUNT_THEN_CUE.finditer(masked):
        number = _parse_number(match.group(1))
        if number is not None:
            _record(number, match.group(2), match, "currency cue after amount")

    for match in _BARE_MULTIPLIER.finditer(masked):
        window = masked[max(0, match.start() - 120): match.end() + 120]
        if not _CONSIDERATION_CUE.search(window):
            continue
        number = _parse_number(match.group(1))
        if number is not None:
            _record(number, match.group(2), match, "consideration keyword nearby")

    findings.sort(key=lambda f: f.amount_pkr, reverse=True)
    return findings


def detect_transaction_value(text: str) -> dict[str, Any]:
    """Highest plausible transaction value plus the statutory thresholds it trips."""
    findings = extract_monetary_values(text)
    top = findings[0] if findings else None
    value = top.amount_pkr if top else 0.0
    return {
        "detected_value_pkr": value,
        "above_5m": value >= FBR_THRESHOLD_PKR,
        "above_10m": value >= AML_THRESHOLD_PKR,
        "evidence": top.snippet if top else "",
        "basis": top.basis if top else "",
        "candidate_count": len(findings),
    }


# ──────────────────────────────────────────────────────────────────────────
#  PDF extraction
# ──────────────────────────────────────────────────────────────────────────
@dataclass
class PageRecord:
    page_num: int
    text: str
    source_file: str
    is_urdu: bool = False
    has_ocr: bool = False
    char_count: int = 0
    ocr_failed: bool = False

    def to_dict(self) -> dict[str, Any]:
        return {
            "page_num": self.page_num,
            "text": self.text,
            "source_file": self.source_file,
            "is_urdu": self.is_urdu,
            "has_ocr": self.has_ocr,
            "char_count": self.char_count,
            "ocr_failed": self.ocr_failed,
        }


def is_pdf(path: Path | str) -> bool:
    """Validate by magic bytes, not by file extension."""
    try:
        with Path(path).open("rb") as handle:
            return handle.read(5) == PDF_MAGIC
    except OSError:
        return False


def validate_pdf_bytes(content: bytes) -> bool:
    return content[:5] == PDF_MAGIC


def extract_text_from_pdf(pdf_path: str | Path) -> list[dict[str, Any]]:
    """
    Extract text page-by-page, falling back to OCR on sparse pages.

    Never raises for a single bad page: a page that cannot be read yields an
    empty record flagged ``ocr_failed`` so the memorandum can disclose it,
    rather than aborting a fifty-page bundle over one corrupt object.
    """
    import pdfplumber                                        # noqa: PLC0415

    settings = get_settings()
    path = Path(pdf_path)
    if not path.exists():
        raise CorruptPdfError(f"{path.name} could not be found on disk.", file=path.name)
    if not is_pdf(path):
        raise CorruptPdfError(f"{path.name} is not a valid PDF file.", file=path.name)

    records: list[PageRecord] = []
    try:
        with pdfplumber.open(path) as pdf:
            if len(pdf.pages) == 0:
                raise CorruptPdfError(f"{path.name} contains no pages.", file=path.name)

            ocr_budget = settings.ocr_max_pages
            for page_num, page in enumerate(pdf.pages, start=1):
                try:
                    raw = page.extract_text() or ""
                except Exception as exc:                     # noqa: BLE001
                    logger.warning("Page %d of %s failed native extraction: %s",
                                   page_num, path.name, exc)
                    raw = ""

                text = normalise_text(raw)
                has_ocr = False
                ocr_failed = False

                if len(text) < settings.ocr_min_chars:
                    if ocr_budget > 0:
                        ocr_budget -= 1
                        ocr_text = _ocr_page(path, page_num)
                        if ocr_text:
                            text = normalise_text(ocr_text)
                            has_ocr = True
                        else:
                            ocr_failed = True
                    else:
                        ocr_failed = True
                        logger.warning("OCR budget exhausted at page %d of %s",
                                       page_num, path.name)

                records.append(PageRecord(
                    page_num=page_num,
                    text=text,
                    source_file=path.name,
                    is_urdu=detect_urdu(text),
                    has_ocr=has_ocr,
                    char_count=len(text),
                    ocr_failed=ocr_failed,
                ))
    except CorruptPdfError:
        raise
    except Exception as exc:                                 # noqa: BLE001
        raise CorruptPdfError(
            f"{path.name} could not be parsed: {exc}", file=path.name
        ) from exc

    logger.info(
        "Extracted %s: %d pages, %d OCR'd, %d Urdu, %d chars total",
        path.name, len(records),
        sum(1 for r in records if r.has_ocr),
        sum(1 for r in records if r.is_urdu),
        sum(r.char_count for r in records),
    )
    return [record.to_dict() for record in records]


def _ocr_page(pdf_path: Path, page_num: int) -> str:
    """Rasterise a single page and run Tesseract.  Returns '' on any failure."""
    capability = probe_ocr()
    if not capability.available:
        logger.warning("OCR requested for %s p%d but unavailable: %s",
                       pdf_path.name, page_num, capability.detail)
        return ""

    settings = get_settings()
    try:
        import pytesseract                                   # noqa: PLC0415
        from pdf2image import convert_from_path              # noqa: PLC0415

        pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd
        images = convert_from_path(
            str(pdf_path), first_page=page_num, last_page=page_num, dpi=settings.ocr_dpi,
        )
        if not images:
            return ""
        return pytesseract.image_to_string(images[0], lang=_ocr_language_string()) or ""
    except Exception as exc:                                 # noqa: BLE001
        logger.warning("OCR failed on %s page %d: %s", pdf_path.name, page_num, exc)
        return ""


# ──────────────────────────────────────────────────────────────────────────
#  Document classification and flagging
# ──────────────────────────────────────────────────────────────────────────
def classify_documents(pages: Iterable[dict[str, Any]]) -> dict[str, list[str]]:
    """Map recognised document types to the source files they appear in."""
    detected: dict[str, set[str]] = {}
    for page in pages:
        text = (page.get("text") or "").lower()
        if not text:
            continue
        source = page.get("source_file", "unknown")
        for doc_type, patterns in DOCUMENT_TYPE_PATTERNS.items():
            if any(pattern in text for pattern in patterns):
                detected.setdefault(doc_type, set()).add(source)
    return {doc_type: sorted(files) for doc_type, files in sorted(detected.items())}


def missing_required_documents(
    detected: dict[str, list[str]], transaction_type: str
) -> list[str]:
    """Required document types for this transaction that were not recognised."""
    required = document_taxonomy()["required_documents"].get(transaction_type, [])
    return [doc for doc in required if doc not in detected]


@dataclass
class FlagReport:
    """Deterministic, pre-model assessment of a document bundle."""

    is_inherited: bool = False
    benami_risk: bool = False
    litigation_risk: bool = False
    encumbrance_risk: bool = False
    has_urdu: bool = False
    has_ocr_pages: bool = False
    ocr_failures: int = 0
    housing_society: str | None = None
    detected_value_pkr: float = 0.0
    value_evidence: str = ""
    high_value_txn: bool = False
    aml_threshold: bool = False
    fbr_applicable: bool = False
    aml_indicators: bool = False
    page_count: int = 0
    urdu_page_count: int = 0
    ocr_page_count: int = 0
    empty_page_count: int = 0
    total_characters: int = 0
    detected_documents: dict[str, list[str]] = field(default_factory=dict)
    missing_documents: list[str] = field(default_factory=list)
    matched_indicators: dict[str, list[str]] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "is_inherited": self.is_inherited,
            "benami_risk": self.benami_risk,
            "litigation_risk": self.litigation_risk,
            "encumbrance_risk": self.encumbrance_risk,
            "has_urdu": self.has_urdu,
            "has_ocr_pages": self.has_ocr_pages,
            "ocr_failures": self.ocr_failures,
            "housing_society": self.housing_society,
            "detected_value_pkr": self.detected_value_pkr,
            "value_evidence": self.value_evidence,
            "high_value_txn": self.high_value_txn,
            "aml_threshold": self.aml_threshold,
            "fbr_applicable": self.fbr_applicable,
            "aml_indicators": self.aml_indicators,
            "page_count": self.page_count,
            "urdu_page_count": self.urdu_page_count,
            "ocr_page_count": self.ocr_page_count,
            "empty_page_count": self.empty_page_count,
            "total_characters": self.total_characters,
            "detected_documents": self.detected_documents,
            "missing_documents": self.missing_documents,
            "matched_indicators": self.matched_indicators,
        }


def detect_special_flags(
    pages: list[dict[str, Any]], transaction_type: str = "property"
) -> dict[str, Any]:
    """
    Deterministic risk assessment run *before* any model is consulted.

    Every boolean here either injects a supplementary checklist question or
    populates a compliance row in the memorandum, so precision matters more
    than recall — which is why negation is respected throughout.
    """
    pages = pages or []
    corpus = " ".join((page.get("text") or "") for page in pages)
    lowered = corpus.lower()

    society: str | None = None
    for name, patterns in HOUSING_SOCIETY_PATTERNS.items():
        if any(pattern in lowered for pattern in patterns):
            society = name
            break

    value = detect_transaction_value(corpus)
    detected_docs = classify_documents(pages)

    inherited_hits = matched_phrases(lowered, INHERITED_INDICATORS)
    benami_hits = matched_phrases(lowered, BENAMI_INDICATORS)
    litigation_hits = matched_phrases(lowered, LITIGATION_INDICATORS)
    encumbrance_hits = matched_phrases(lowered, ENCUMBRANCE_INDICATORS)
    aml_hits = matched_phrases(lowered, AML_INDICATORS)

    report = FlagReport(
        is_inherited=bool(inherited_hits),
        benami_risk=bool(benami_hits),
        litigation_risk=bool(litigation_hits),
        encumbrance_risk=bool(encumbrance_hits),
        has_urdu=any(page.get("is_urdu") for page in pages),
        has_ocr_pages=any(page.get("has_ocr") for page in pages),
        ocr_failures=sum(1 for page in pages if page.get("ocr_failed")),
        housing_society=society,
        detected_value_pkr=value["detected_value_pkr"],
        value_evidence=value["evidence"],
        high_value_txn=value["above_5m"],
        aml_threshold=value["above_10m"],
        fbr_applicable=value["above_5m"],
        aml_indicators=bool(aml_hits),
        page_count=len(pages),
        urdu_page_count=sum(1 for page in pages if page.get("is_urdu")),
        ocr_page_count=sum(1 for page in pages if page.get("has_ocr")),
        empty_page_count=sum(1 for page in pages if not (page.get("text") or "").strip()),
        total_characters=sum(int(page.get("char_count") or 0) for page in pages),
        detected_documents=detected_docs,
        missing_documents=missing_required_documents(detected_docs, transaction_type),
        matched_indicators={
            "inheritance": inherited_hits,
            "benami": benami_hits,
            "litigation": litigation_hits,
            "encumbrance": encumbrance_hits,
            "aml": aml_hits,
        },
    )
    return report.to_dict()


def get_constitutional_basis(topic: str) -> str:
    """Constitutional article for a checklist topic tag."""
    if not topic:
        return DEFAULT_CONSTITUTIONAL_BASIS
    key = topic.strip().lower()
    if key in CONSTITUTIONAL_MAP:
        return CONSTITUTIONAL_MAP[key]
    for keyword, article in CONSTITUTIONAL_MAP.items():
        if keyword in key:
            return article
    return DEFAULT_CONSTITUTIONAL_BASIS
