"""
The memorandum as data, independent of any output format.

Both the Word writer and the PDF writer consume this model, which is why the
two deliverables cannot drift apart: section order, risk arithmetic, compliance
determinations and the disclaimer are decided exactly once, here.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

FBR_THRESHOLD_PKR = 5_000_000
AML_THRESHOLD_PKR = 10_000_000

RISK_ORDER = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}

DISCLAIMER = (
    "This memorandum has been prepared with the assistance of an AI-supported legal "
    "review system. It is a first-pass working draft, not legal advice, and must be "
    "reviewed, verified and approved by a qualified Pakistani advocate before it is "
    "relied upon or issued to a client. Every finding records the document and the "
    "statutory provision it rests on precisely so that it can be independently "
    "verified against the original instruments. Where a page was processed by optical "
    "character recognition, or where a question could not be assessed automatically, "
    "that limitation is disclosed in the relevant section below."
)


@dataclass
class ComplianceRow:
    label: str
    value: str
    action_required: bool = False
    note: str = ""


@dataclass
class MemoModel:
    """Everything the writers need, already computed."""

    firm_name: str
    firm_address: str = ""
    firm_phone: str = ""
    firm_email: str = ""
    firm_tagline: str = ""

    transaction_type: str = "property"
    city: str = "islamabad"
    authority: str = ""
    authority_full_name: str = ""
    relevant_bylaws: str = ""
    housing_society: str | None = None

    generated_at: str = ""
    document_names: list[str] = field(default_factory=list)

    total_questions: int = 0
    high_risk_count: int = 0
    medium_risk_count: int = 0
    low_risk_count: int = 0
    failed_count: int = 0

    findings: list[dict[str, Any]] = field(default_factory=list)
    red_flags: list[dict[str, Any]] = field(default_factory=list)
    missing_documents: list[str] = field(default_factory=list)
    compliance_rows: list[ComplianceRow] = field(default_factory=list)
    detected_documents: dict[str, list[str]] = field(default_factory=dict)

    executive_summary: str = ""
    has_letterhead: bool = False

    @property
    def title(self) -> str:
        return "DUE DILIGENCE REVIEW MEMORANDUM"

    @property
    def subtitle(self) -> str:
        location = self.city.title() if self.city else ""
        return f"{self.transaction_type.title()} Transaction — {location}".strip(" —")

    @property
    def overall_risk(self) -> str:
        if self.high_risk_count or self.red_flags:
            return "HIGH"
        if self.medium_risk_count:
            return "MEDIUM"
        return "LOW"


def _clean(value: Any, fallback: str = "Not stated") -> str:
    text = str(value if value is not None else "").strip()
    return text or fallback


def _sorted_findings(findings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Highest risk first, then by question order — partners read top-down."""
    return sorted(
        findings,
        key=lambda f: (
            RISK_ORDER.get(str(f.get("risk_level", "LOW")).upper(), 3),
            int(f.get("question_id") or 0),
        ),
    )


def _build_compliance_rows(flags: dict[str, Any]) -> list[ComplianceRow]:
    value = float(flags.get("detected_value_pkr") or 0)
    fbr = bool(flags.get("fbr_applicable"))
    aml = bool(flags.get("aml_threshold"))

    rows = [
        ComplianceRow(
            label="Detected transaction value",
            value=(f"PKR {value:,.0f}" if value else
                   "Not detected in the supplied documents"),
            note=_clean(flags.get("value_evidence"), "") [:180],
        ),
        ComplianceRow(
            label=("Withholding tax applicable\n"
                   "(Income Tax Ordinance 2001, ss. 236C / 236K — above PKR 5,000,000)"),
            value=("Yes — withholding tax arises (1% for filers, 2% for non-filers)"
                   if fbr else "No — below the PKR 5,000,000 threshold"),
            action_required=fbr,
        ),
        ComplianceRow(
            label=("Enhanced due diligence required\n"
                   "(Anti-Money Laundering Act 2010 — above PKR 10,000,000)"),
            value=("Yes — source of funds documentation is required"
                   if aml else "No — below the PKR 10,000,000 threshold"),
            action_required=aml,
        ),
        ComplianceRow(
            label="AML risk indicators present in documents",
            value=("Yes — review the source of funds documentation"
                   if flags.get("aml_indicators") else "None detected"),
            action_required=bool(flags.get("aml_indicators")),
        ),
        ComplianceRow(
            label="Benami indicators present",
            value=("Yes — assess under the Benami Transactions (Prohibition) Act 2017"
                   if flags.get("benami_risk") else "None detected"),
            action_required=bool(flags.get("benami_risk")),
        ),
        ComplianceRow(
            label="Inheritance / succession indicators present",
            value=("Yes — succession and heirship documentation required"
                   if flags.get("is_inherited") else "None detected"),
            action_required=bool(flags.get("is_inherited")),
        ),
        ComplianceRow(
            label="Urdu content detected",
            value=(f"Yes — {flags.get('urdu_page_count', 0)} page(s); multilingual "
                   f"processing applied" if flags.get("has_urdu")
                   else "No — English-only bundle"),
        ),
        ComplianceRow(
            label="Pages processed by OCR",
            value=(f"Yes — {flags.get('ocr_page_count', 0)} scanned page(s) were "
                   f"OCR-processed" if flags.get("has_ocr_pages")
                   else "No — all pages carried extractable text"),
            note=("OCR output should be spot-checked against the physical originals."
                  if flags.get("has_ocr_pages") else ""),
        ),
    ]

    if flags.get("ocr_failures"):
        rows.append(ComplianceRow(
            label="Pages that could not be read",
            value=f"{flags['ocr_failures']} page(s) yielded no text by any method",
            action_required=True,
            note="These pages must be reviewed manually against the originals.",
        ))
    return rows


def _build_executive_summary(model: MemoModel, flags: dict[str, Any]) -> str:
    parts: list[str] = []

    scope = (f"This memorandum records a first-pass due diligence review of "
             f"{len(model.document_names)} document"
             f"{'s' if len(model.document_names) != 1 else ''} "
             f"in a {model.transaction_type} transaction")
    if model.authority_full_name:
        scope += f" falling under the jurisdiction of {model.authority_full_name}"
    if model.housing_society:
        scope += f", situated in {model.housing_society}"
    parts.append(scope + f". {model.total_questions} diligence questions were assessed.")

    if model.high_risk_count:
        parts.append(
            f"{model.high_risk_count} item"
            f"{'s were' if model.high_risk_count != 1 else ' was'} assessed as HIGH risk "
            f"and require partner attention before the transaction proceeds.")
    else:
        parts.append("No item was assessed as HIGH risk on the documents supplied.")

    if model.red_flags:
        labels = "; ".join(flag["label"] for flag in model.red_flags[:4])
        parts.append(f"{len(model.red_flags)} red flag"
                     f"{'s were' if len(model.red_flags) != 1 else ' was'} raised: {labels}.")

    if model.missing_documents:
        parts.append(
            f"{len(model.missing_documents)} document"
            f"{'s appear' if len(model.missing_documents) != 1 else ' appears'} to be "
            f"absent from the bundle and should be requisitioned from the vendor.")

    value = float(flags.get("detected_value_pkr") or 0)
    if value >= AML_THRESHOLD_PKR:
        parts.append(
            f"The detected consideration of PKR {value:,.0f} exceeds the "
            f"PKR 10,000,000 threshold, so enhanced due diligence under the "
            f"Anti-Money Laundering Act 2010 is engaged in addition to withholding "
            f"tax under sections 236C and 236K.")
    elif value >= FBR_THRESHOLD_PKR:
        parts.append(
            f"The detected consideration of PKR {value:,.0f} exceeds the "
            f"PKR 5,000,000 threshold, engaging withholding tax under sections "
            f"236C and 236K of the Income Tax Ordinance 2001.")

    if model.failed_count:
        parts.append(
            f"{model.failed_count} question"
            f"{'s could' if model.failed_count != 1 else ' could'} not be assessed "
            f"automatically and are marked for manual review.")

    return " ".join(parts)


def build_memo_model(
    results: dict[str, Any],
    *,
    firm_name: str = "Law Firm",
    firm_address: str = "",
    firm_phone: str = "",
    firm_email: str = "",
    firm_tagline: str = "",
    transaction_type: str | None = None,
    city: str | None = None,
    document_names: list[str] | None = None,
    flags: dict[str, Any] | None = None,
) -> MemoModel:
    """Fold the pipeline results into a format-agnostic memorandum model."""
    results = results or {}
    flags = flags or results.get("flags") or {}

    model = MemoModel(
        firm_name=_clean(firm_name, "Law Firm"),
        firm_address=str(firm_address or "").strip(),
        firm_phone=str(firm_phone or "").strip(),
        firm_email=str(firm_email or "").strip(),
        firm_tagline=str(firm_tagline or "").strip(),
        transaction_type=str(transaction_type or results.get("transaction_type") or "property"),
        city=str(city or results.get("city") or "islamabad"),
        authority=str(results.get("authority") or ""),
        authority_full_name=str(results.get("authority_full_name") or ""),
        relevant_bylaws=str(results.get("relevant_bylaws") or ""),
        housing_society=results.get("housing_society") or flags.get("housing_society"),
        generated_at=datetime.now().strftime("%d %B %Y at %H:%M"),
        document_names=list(document_names or []),
        total_questions=int(results.get("total_questions") or 0),
        high_risk_count=int(results.get("high_risk_count") or 0),
        medium_risk_count=int(results.get("medium_risk_count") or 0),
        low_risk_count=int(results.get("low_risk_count") or 0),
        failed_count=int(results.get("failed_count") or 0),
        findings=_sorted_findings(list(results.get("findings") or [])),
        red_flags=list(results.get("red_flags") or []),
        missing_documents=list(results.get("missing_documents") or []),
        detected_documents=dict(flags.get("detected_documents") or {}),
    )
    model.has_letterhead = bool(model.firm_name and model.firm_name != "Law Firm")
    model.compliance_rows = _build_compliance_rows(flags)
    model.executive_summary = _build_executive_summary(model, flags)
    return model
