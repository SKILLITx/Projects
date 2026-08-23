"""
The due diligence reasoning engine.

Changes of substance over the previous build:

* **The city and housing-society configuration files were never read.**
  ``city_profiles.json`` and ``housing_societies.json`` encoded authority-specific
  NOC types, bye-laws and transfer regimes, but no module consulted them — city
  selection reached only the memorandum header, so an Islamabad review asked the
  same generic NOC question as a Karachi one.  Checklist questions are now
  templated against the selected city's authority and against the detected
  society's actual document list.
* **Red-flag rules matched bare substrings on model output.**  They now run
  through the negation-aware matcher and are evaluated against the source
  documents *as well as* the findings, so a rule can no longer be tripped by the
  model's own paraphrase of an absence.
* **Questions ran strictly sequentially behind a fixed four-second sleep.**
  Execution is now a bounded worker pool governed by the shared token bucket,
  which both removes the dead time and makes concurrent reviews safe.
* **A failed question aborted silently into a fabricated MEDIUM finding.**
  Failures are now recorded with their cause and surfaced in the results payload.
"""

from __future__ import annotations

import logging
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import Any, Callable

from core.config import city_profiles, get_settings, housing_societies
from core.document_processor import (
    any_phrase,
    get_constitutional_basis,
    matched_phrases,
)
from core.query_engine import answer_question

logger = logging.getLogger(__name__)

VALID_TRANSACTION_TYPES = ("property", "loan", "acquisition")


# ──────────────────────────────────────────────────────────────────────────
#  Red-flag rules
# ──────────────────────────────────────────────────────────────────────────
@dataclass(frozen=True)
class RedFlagRule:
    id: str
    label: str
    statute: str
    article: str
    patterns: tuple[str, ...]
    severity: str = "HIGH"
    description: str = ""

    def to_dict(self, evidence: list[str] | None = None) -> dict[str, Any]:
        return {
            "id": self.id,
            "label": self.label,
            "statute": self.statute,
            "article": self.article,
            "severity": self.severity,
            "description": self.description,
            "evidence": evidence or [],
        }


RED_FLAG_RULES: tuple[RedFlagRule, ...] = (
    RedFlagRule(
        id="RF001",
        label="Required NOC absent from the bundle",
        statute="LDA / CDA / RDA / SBCA Bye-Laws",
        article="Article 24 — Protection of property rights",
        patterns=("noc is missing", "noc not obtained", "noc not provided",
                  "without noc", "noc absent", "no objection certificate is missing",
                  "noc has not been", "noc was not"),
        description="Transfer cannot be completed until the controlling development "
                    "authority issues its No Objection Certificate.",
    ),
    RedFlagRule(
        id="RF002",
        label="Sale consideration inconsistent across documents",
        statute="Registration Act 1908, Section 17",
        article="Article 23 — Right to acquire property subject to law",
        patterns=("price discrepancy", "consideration differs", "amount differs",
                  "inconsistent consideration", "differing sale price",
                  "sale price discrepancy", "value stated differs"),
        description="A consideration mismatch attracts stamp-duty and "
                    "withholding-tax exposure and undermines the deed's evidentiary value.",
    ),
    RedFlagRule(
        id="RF003",
        label="Undisclosed litigation, decree or injunction",
        statute="Transfer of Property Act 1882, Section 52 (lis pendens)",
        article="Article 24 — Protection of property rights",
        patterns=("ongoing litigation", "pending litigation", "suit is pending",
                  "suit pending against", "court order against", "injunction against",
                  "caveat against", "stay order against", "decree against",
                  "attachment order", "lis pendens applies"),
        description="Property transferred during pending litigation passes subject to "
                    "the outcome of that suit.",
    ),
    RedFlagRule(
        id="RF004",
        label="Co-owner or legal heir interest without recorded consent",
        statute="Muslim Family Laws Ordinance 1961; Transfer of Property Act 1882",
        article="Article 25 — Equality of citizens",
        patterns=("co-owner without consent", "co owner without consent",
                  "joint owner without consent", "heir without consent",
                  "heirs have not consented", "without written consent",
                  "undisclosed co-owner", "undisclosed heir",
                  "consent of co-owners is missing", "co-sharer without consent"),
        description="A transfer executed without every co-sharer's written consent is "
                    "voidable at the instance of the omitted sharer.",
    ),
    RedFlagRule(
        id="RF005",
        label="CNIC or identity mismatch across documents",
        statute="Registration Act 1908, Section 17; NADRA Ordinance 2000",
        article="Article 4 — Right to be dealt with in accordance with law",
        patterns=("cnic mismatch", "cnic differs", "cnic does not match",
                  "identity mismatch", "name mismatch", "different cnic",
                  "cnic is inconsistent"),
        description="An identity mismatch between the deed, the NOC and the revenue "
                    "record blocks registration and signals possible impersonation.",
    ),
    RedFlagRule(
        id="RF006",
        label="Indicators of a benami arrangement",
        statute="Benami Transactions (Prohibition) Act 2017",
        article="Article 24 — Protection against unlawful deprivation",
        patterns=("benami transaction", "benamidar", "benami arrangement",
                  "ostensible owner", "beneficial owner is different",
                  "consideration paid by a third party", "purchased on behalf of",
                  "name lender"),
        description="Benami property is liable to confiscation and the arrangement "
                    "carries criminal liability for all parties.",
    ),
    RedFlagRule(
        id="RF007",
        label="Mutation (Intiqal) not recorded in the revenue record",
        statute="Land Revenue Act 1967; LRMIS record of rights",
        article="Article 23 — Right to acquire and dispose of property",
        patterns=("mutation is missing", "mutation not recorded", "no mutation",
                  "intiqal is missing", "intiqal not recorded", "mutation not attested",
                  "mutation has not been", "unmutated"),
        description="Without an attested mutation the buyer acquires no entry in the "
                    "record of rights and cannot deal with the land.",
    ),
    RedFlagRule(
        id="RF008",
        label="Subsisting encumbrance, mortgage or charge",
        statute="Transfer of Property Act 1882, Sections 58–60",
        article="Article 24 — Protection of property rights",
        patterns=("subsisting mortgage", "existing charge", "outstanding lien",
                  "property is mortgaged", "encumbrance exists", "hypothecated to",
                  "charge is registered against", "equitable mortgage subsists"),
        description="A live charge must be redeemed and formally released before "
                    "clean title can pass.",
    ),
    RedFlagRule(
        id="RF009",
        label="Stamp duty or registration fee shortfall",
        statute="Stamp Act 1899, Sections 33 and 35",
        article="Article 23 — Right to acquire property subject to law",
        patterns=("insufficiently stamped", "stamp duty not paid", "under-stamped",
                  "deficient stamp duty", "stamp duty shortfall",
                  "registration fee unpaid", "inadequate stamp"),
        description="An insufficiently stamped instrument is inadmissible in evidence "
                    "until the duty and penalty are paid.",
    ),
)


# ──────────────────────────────────────────────────────────────────────────
#  Checklist definitions
# ──────────────────────────────────────────────────────────────────────────
@dataclass
class ChecklistItem:
    id: int
    question: str
    topic: str
    category: str = "core"
    hint: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {"id": self.id, "question": self.question,
                "topic": self.topic, "category": self.category}


# ``{authority}`` and ``{bylaws}`` are filled from the selected city profile.
PROPERTY_CHECKLIST: tuple[dict[str, str], ...] = (
    {"topic": "title",
     "question": "Is the title deed present and registered in the name of the vendor? "
                 "Verify the Registry number, the Sub-Registrar office of registration, "
                 "and the date of registration."},
    {"topic": "encumbrance",
     "question": "Is the property free from all encumbrances, mortgages, charges and liens? "
                 "Identify any bank charge, hypothecation or third-party claim disclosed "
                 "in the documents."},
    {"topic": "noc",
     "question": "Are all NOCs required by {authority} present? Under {bylaws}, identify "
                 "which authority issued each NOC, its date, and whether any required "
                 "NOC is absent from the bundle."},
    {"topic": "boundaries",
     "question": "Are the property boundaries, Khasra number, Khata number and area "
                 "measurements consistent across every submitted document?"},
    {"topic": "litigation",
     "question": "Is there any ongoing or threatened litigation, court order, injunction, "
                 "stay order or caveat against the property or against the vendor?"},
    {"topic": "consideration",
     "question": "Is the sale consideration stated consistently across all documents, and "
                 "is it supported by bank evidence, pay orders or payment receipts?"},
    {"topic": "attestation",
     "question": "Are all signatures, attestations, thumb impressions, witness particulars "
                 "and notarial certifications present and valid on every document?"},
    {"topic": "land_use",
     "question": "Is the land-use classification consistent with the intended purpose of "
                 "acquisition? Check the residential, commercial or agricultural zoning "
                 "recorded by {authority}."},
    {"topic": "utilities",
     "question": "Are utility connections — electricity, gas, water and PTCL — documented "
                 "and registered in the vendor's name? Are any outstanding utility dues "
                 "disclosed?"},
    {"topic": "tax",
     "question": "Are all outstanding property taxes, withholding taxes under Sections 236C "
                 "and 236K of the Income Tax Ordinance 2001, Capital Value Tax and stamp "
                 "duty arrears disclosed and settled?"},
    {"topic": "cnic",
     "question": "Is the vendor's CNIC number verified and identical across the sale deed, "
                 "the NOC, the revenue record and the utility bills?"},
    {"topic": "co-owner",
     "question": "Are there any co-owners, inherited co-sharers, legal heirs or third-party "
                 "interests in the property? If so, is their written consent to the "
                 "transfer documented?"},
    {"topic": "possession",
     "question": "Is the possession transfer date, the handover mechanism and the current "
                 "physical possession status explicitly documented?"},
    {"topic": "conditions",
     "question": "Are all conditions precedent to the transfer clearly identified and "
                 "confirmed as satisfied? List any condition that remains outstanding."},
    {"topic": "mutation",
     "question": "Is a registered mutation (Intiqal) on record in LRMIS? Is the "
                 "Fard-e-Malkiat consistent with the Registry, and is the mode of transfer "
                 "legally valid under Pakistani land revenue law?"},
)

LOAN_CHECKLIST: tuple[dict[str, str], ...] = (
    {"topic": "title",
     "question": "Is the loan or facility agreement present and duly executed by all "
                 "parties? Verify signatures, dates and notarial attestation."},
    {"topic": "encumbrance",
     "question": "Is the mortgage deed or charge document registered with the relevant "
                 "Sub-Registrar under Section 17 of the Registration Act 1908? Verify the "
                 "registration number and date."},
    {"topic": "encumbrance",
     "question": "Is the security property free from all prior encumbrances, charges and "
                 "liens? Has a search been conducted at the Sub-Registrar's office?"},
    {"topic": "title",
     "question": "Is the mortgagor's title to the security property clear and marketable? "
                 "Are all title documents present and mutually consistent?"},
    {"topic": "consideration",
     "question": "Are the loan amount, mark-up rate, repayment schedule and penalty clauses "
                 "specified consistently across all documents?"},
    {"topic": "tax",
     "question": "Are the State Bank of Pakistan prudential regulations complied with? Are "
                 "the debt-to-equity ratio and exposure limits within permissible bounds?"},
    {"topic": "cnic",
     "question": "Is the borrower's CNIC verified and consistent across every loan document? "
                 "Is the borrower an active FBR filer?"},
    {"topic": "boundaries",
     "question": "Is a valuation report for the security property present and prepared by a "
                 "PBA-approved valuer? Does it support the stated loan-to-value ratio?"},
    {"topic": "utilities",
     "question": "Is an insurance or takaful policy over the security property present and "
                 "assigned in favour of the lending institution?"},
    {"topic": "noc",
     "question": "Are all NOCs from {authority} present for the security property? Is the "
                 "property free from any government acquisition notice?"},
    {"topic": "litigation",
     "question": "Is there any ongoing litigation, court order or injunction against the "
                 "borrower, the guarantor or the security property?"},
    {"topic": "conditions",
     "question": "Are the disbursement conditions clearly specified, and has the borrower "
                 "satisfied every condition precedent to disbursement?"},
    {"topic": "attestation",
     "question": "Is the personal or corporate guarantee present and executed? Is the "
                 "guarantor's financial capacity documented?"},
    {"topic": "tax",
     "question": "Are withholding tax obligations under the Income Tax Ordinance 2001 on "
                 "mark-up payments documented and complied with?"},
    {"topic": "mutation",
     "question": "Is the registered mutation (Intiqal) of the security property consistent "
                 "with the title documents? Is the Fard-e-Malkiat attached and verified?"},
)

ACQUISITION_CHECKLIST: tuple[dict[str, str], ...] = (
    {"topic": "title",
     "question": "Is the Share Purchase Agreement or Asset Purchase Agreement present and "
                 "duly executed by authorised signatories of both parties?"},
    {"topic": "attestation",
     "question": "Is the target company duly incorporated under the Companies Act 2017? Are "
                 "the Certificate of Incorporation, Memorandum and Articles of Association "
                 "present?"},
    {"topic": "noc",
     "question": "Are all SECP filings current and compliant? Are the annual return, Form-A, "
                 "Form-29 and audited financial statements filed and up to date?"},
    {"topic": "title",
     "question": "Is the share register present and consistent with the SECP record? Are all "
                 "share transfers properly executed and stamped?"},
    {"topic": "encumbrance",
     "question": "Are there any encumbrances, charges or pledges over the shares or assets of "
                 "the target company registered with SECP?"},
    {"topic": "consideration",
     "question": "Is the consideration consistent across all transaction documents, and is it "
                 "supported by board resolutions and shareholder approvals?"},
    {"topic": "litigation",
     "question": "Are there any pending or threatened litigation, arbitration, regulatory "
                 "proceedings or tax disputes involving the target company?"},
    {"topic": "conditions",
     "question": "Are all material contracts, licences and permits of the target present? Do "
                 "any contain change-of-control clauses requiring counterparty consent?"},
    {"topic": "tax",
     "question": "Are all outstanding tax liabilities — income tax, sales tax and withholding "
                 "tax — disclosed and quantified? Are FBR tax clearance certificates present?"},
    {"topic": "utilities",
     "question": "Are all employee-related liabilities — provident fund, EOBI, SESSI and "
                 "gratuity — disclosed and adequately provided for?"},
    {"topic": "noc",
     "question": "Is a Competition Commission of Pakistan merger filing required under the "
                 "Competition Act 2010? If so, has prior clearance been obtained?"},
    {"topic": "cnic",
     "question": "Are the CNICs of all directors and major shareholders verified and "
                 "consistent with SECP records?"},
    {"topic": "attestation",
     "question": "Are all representations and warranties in the acquisition agreement "
                 "adequately supported by the disclosed documents?"},
    {"topic": "conditions",
     "question": "Are all conditions precedent to closing satisfied or formally waived? List "
                 "any outstanding closing condition."},
    {"topic": "aml",
     "question": "Is Anti-Money Laundering Act 2010 compliance documented? Is the source of "
                 "acquisition funds clearly established and supported by bank evidence?"},
)

CHECKLISTS: dict[str, tuple[dict[str, str], ...]] = {
    "property": PROPERTY_CHECKLIST,
    "loan": LOAN_CHECKLIST,
    "acquisition": ACQUISITION_CHECKLIST,
}


# ──────────────────────────────────────────────────────────────────────────
#  Checklist assembly
# ──────────────────────────────────────────────────────────────────────────
def resolve_city(city: str | None) -> dict[str, Any]:
    """City profile for the selected city, falling back to the first configured one."""
    profiles = city_profiles()
    key = (city or "").strip().lower()
    if key in profiles:
        return {"key": key, **profiles[key]}
    fallback_key = next(iter(profiles))
    return {"key": fallback_key, **profiles[fallback_key]}


def build_checklist(
    transaction_type: str,
    flags: dict[str, Any] | None = None,
    city: str | None = None,
    housing_society: str | None = None,
) -> list[ChecklistItem]:
    """
    Assemble the executable checklist for one review.

    The base taxonomy is templated against the selected city's development
    authority, then extended with supplementary questions that fire only when
    the deterministic ingestion flags detected the corresponding risk.
    """
    flags = flags or {}
    transaction_type = transaction_type if transaction_type in CHECKLISTS else "property"
    profile = resolve_city(city)
    authority = f"{profile['full_name']} ({profile['authority']})"
    bylaws = profile["relevant_bylaws"]
    noc_types = ", ".join(profile["noc_types"]) or "the applicable NOCs"

    items: list[ChecklistItem] = []
    for index, template in enumerate(CHECKLISTS[transaction_type], start=1):
        question = template["question"].format(authority=authority, bylaws=bylaws)
        hint = ""
        if template["topic"] == "noc":
            hint = (f"The controlling authority for this transaction is {authority}. "
                    f"NOC types typically required: {noc_types}. "
                    f"Governing bye-laws: {bylaws}.")
        elif template["topic"] == "land_use":
            hint = f"Zoning is administered by {authority} under {bylaws}."
        elif template["topic"] in {"tax", "mutation"} and profile.get("statutes"):
            hint = "Locally applicable statutes: " + "; ".join(profile["statutes"]) + "."
        items.append(ChecklistItem(
            id=index, question=question, topic=template["topic"],
            category="core", hint=hint,
        ))

    next_id = len(items) + 1

    if flags.get("is_inherited"):
        items.append(ChecklistItem(
            id=next_id, category="inheritance", topic="inheritance",
            question=(
                "The documents indicate an inherited property. Is a succession certificate "
                "present? Are legal heirship certificates issued by a competent court "
                "available? Have all legal heirs consented in writing to the transfer as "
                "required under the Muslim Family Laws Ordinance 1961 and applicable "
                "principles of Islamic inheritance?"),
            hint="Confirm each heir's share is accounted for; an omitted sharer can avoid "
                 "the transfer.",
        ))
        next_id += 1

    if flags.get("benami_risk"):
        items.append(ChecklistItem(
            id=next_id, category="benami", topic="benami",
            question=(
                "Potential benami indicators were detected. Is the sale consideration being "
                "paid by the named buyer from their own declared resources? Is there any "
                "undisclosed beneficial owner or third-party financier? Assess compliance "
                "with the Benami Transactions (Prohibition) Act 2017."),
            hint="Benami property is liable to confiscation; the arrangement is a criminal "
                 "offence for every participant.",
        ))
        next_id += 1

    if flags.get("aml_threshold"):
        value = flags.get("detected_value_pkr", 0) or 0
        items.append(ChecklistItem(
            id=next_id, category="aml", topic="aml",
            question=(
                f"The detected transaction value of PKR {value:,.0f} exceeds the "
                f"PKR 10,000,000 enhanced due diligence threshold. Is the source of funds "
                f"documented? Are the enhanced due diligence requirements of the "
                f"Anti-Money Laundering Act 2010 and the SECP AML/CFT Regulations 2018 "
                f"satisfied?"),
            hint="Advocates are a designated non-financial business and profession for "
                 "AML/CFT purposes.",
        ))
        next_id += 1

    society_name = (housing_society or "").strip() or flags.get("housing_society")
    if society_name:
        societies = housing_societies()
        profile_society = societies.get(society_name, {})
        docs = profile_society.get("transfer_docs") or [
            "society transfer letter", "society NOC", "dues clearance certificate"]
        special = profile_society.get("special_requirements", "")
        items.append(ChecklistItem(
            id=next_id, category="housing_society", topic="housing_society",
            question=(
                f"This transaction involves {society_name}. Are all society-specific "
                f"transfer documents present — specifically the {', '.join(docs)}? Are "
                f"there any outstanding charges payable to {society_name} that must be "
                f"cleared before the transfer can be completed?"),
            hint=(f"{society_name} requirement: {special}" if special else
                  f"Confirm the society's own transfer formalities for {society_name}."),
        ))
        next_id += 1

    if flags.get("encumbrance_risk"):
        items.append(ChecklistItem(
            id=next_id, category="encumbrance", topic="encumbrance",
            question=(
                "Encumbrance indicators were detected in the bundle. Identify every "
                "mortgage, charge, lien or hypothecation affecting the property, state "
                "whether each has been redeemed, and confirm whether a formal release or "
                "no-dues certificate has been issued by the chargeholder."),
            hint="A charge that has been repaid but not formally released still clouds title.",
        ))
        next_id += 1

    if flags.get("ocr_failures"):
        items.append(ChecklistItem(
            id=next_id, category="integrity", topic="attestation",
            question=(
                "Some pages in this bundle could not be read by either native text "
                "extraction or OCR. Identify which documents appear incomplete, and state "
                "what an advocate must verify manually against the physical originals "
                "before relying on this review."),
            hint="Report this as a limitation of the review rather than a defect in title.",
        ))

    return items


# ──────────────────────────────────────────────────────────────────────────
#  Red-flag evaluation
# ──────────────────────────────────────────────────────────────────────────
def detect_red_flags(
    findings: list[dict[str, Any]], source_text: str = ""
) -> list[dict[str, Any]]:
    """
    Evaluate the deterministic rules against findings *and* source documents.

    Matching is negation-aware, which is the fix for the failure mode where a
    finding reading "there is no ongoing litigation" tripped RF003 because it
    contained the literal trigger phrase.
    """
    finding_text = " ".join(
        f"{item.get('finding', '')} {item.get('reasoning', '')} {item.get('recommendation', '')}"
        for item in findings
    ).lower()
    document_text = (source_text or "").lower()
    haystack = f"{finding_text}\n{document_text}"

    triggered: list[dict[str, Any]] = []
    for rule in RED_FLAG_RULES:
        hits = matched_phrases(haystack, rule.patterns)
        if hits:
            triggered.append(rule.to_dict(evidence=hits[:3]))
    return triggered


def _high_risk_topics(findings: list[dict[str, Any]]) -> list[str]:
    return sorted({
        str(item.get("topic") or item.get("category") or "general")
        for item in findings
        if str(item.get("risk_level", "")).upper() == "HIGH"
    })


# ──────────────────────────────────────────────────────────────────────────
#  Execution
# ──────────────────────────────────────────────────────────────────────────
def _fallback_finding(item: ChecklistItem, reason: str) -> dict[str, Any]:
    """
    Conservative placeholder for a question that could not be assessed.

    MEDIUM rather than LOW so the item stays visible in the triage view, and
    rather than HIGH so a transient provider failure does not flood the summary
    and train reviewers to ignore it.
    """
    return {
        "question_id": item.id,
        "question": item.question,
        "topic": item.topic,
        "category": item.category,
        "finding": "This question could not be assessed automatically.",
        "reasoning": reason,
        "document_citation": "Not available",
        "statutory_citation": "Not available",
        "constitutional_basis": get_constitutional_basis(item.topic),
        "risk_level": "MEDIUM",
        "recommendation": "Manual review required — assess this item against the originals.",
        "missing_documents": [],
        "confidence": "LOW",
        "query_source": "checklist",
        "failed": True,
        "error": reason,
    }


def _answer_item(
    item: ChecklistItem, session_index: Any, corpus_index: Any
) -> dict[str, Any]:
    result = answer_question(
        session_index, corpus_index, item.question,
        hint=item.hint or None,
        description=f"Q{item.id} ({item.topic})",
    )
    if not result.get("constitutional_basis"):
        result["constitutional_basis"] = get_constitutional_basis(item.topic)
    result.update({
        "question_id": item.id,
        "question": item.question,
        "topic": item.topic,
        "category": item.category,
        "query_source": "checklist",
        "failed": False,
    })
    return result


def run_checklist(
    session_index: Any,
    legal_corpus_index: Any,
    transaction_type: str = "property",
    flags: dict[str, Any] | None = None,
    *,
    city: str | None = None,
    housing_society: str | None = None,
    source_text: str = "",
    progress_callback: Callable[[int, int], None] | None = None,
) -> dict[str, Any]:
    """
    Execute the full checklist and assemble the structured results payload.

    Questions run through a bounded worker pool.  Concurrency is safe because
    every LLM call reserves capacity from the shared process-wide token bucket
    before it is issued, so the provider ceiling is respected in aggregate
    rather than approximated by a per-loop sleep.
    """
    settings = get_settings()
    flags = flags or {}
    transaction_type = transaction_type if transaction_type in CHECKLISTS else "property"

    items = build_checklist(transaction_type, flags, city, housing_society)
    total = len(items)
    logger.info("Running %d checklist questions (%s, %s) with %d workers",
                total, transaction_type, city or "default", settings.checklist_workers)

    results: dict[int, dict[str, Any]] = {}
    completed = 0
    lock = threading.Lock()

    def _record(index: int, payload: dict[str, Any]) -> None:
        nonlocal completed
        with lock:
            results[index] = payload
            completed += 1
            if progress_callback is not None:
                try:
                    progress_callback(completed, total)
                except Exception:                            # noqa: BLE001
                    pass

    workers = max(1, min(settings.checklist_workers, total))
    with ThreadPoolExecutor(max_workers=workers, thread_name_prefix="checklist") as pool:
        futures = {
            pool.submit(_answer_item, item, session_index, legal_corpus_index): (position, item)
            for position, item in enumerate(items)
        }
        for future in as_completed(futures):
            position, item = futures[future]
            try:
                _record(position, future.result())
            except Exception as exc:                         # noqa: BLE001
                logger.error("Question %d (%s) failed: %s", item.id, item.topic, exc)
                _record(position, _fallback_finding(item, str(exc)))

    findings = [results[position] for position in sorted(results)]

    red_flags = detect_red_flags(findings, source_text)
    high = [f for f in findings if str(f.get("risk_level", "")).upper() == "HIGH"]
    medium = [f for f in findings if str(f.get("risk_level", "")).upper() == "MEDIUM"]
    low = [f for f in findings if str(f.get("risk_level", "")).upper() == "LOW"]
    failures = [f for f in findings if f.get("failed")]

    missing: list[str] = []
    for finding in findings:
        missing.extend(finding.get("missing_documents") or [])
    missing.extend(flags.get("missing_documents") or [])
    seen: set[str] = set()
    deduped_missing = [
        doc for doc in missing
        if doc and not (doc.strip().lower() in seen or seen.add(doc.strip().lower()))
    ]

    profile = resolve_city(city)
    return {
        "transaction_type": transaction_type,
        "city": profile["key"],
        "authority": profile["authority"],
        "authority_full_name": profile["full_name"],
        "relevant_bylaws": profile["relevant_bylaws"],
        "housing_society": (housing_society or "").strip() or flags.get("housing_society"),
        "total_questions": total,
        "findings": findings,
        "red_flags": red_flags,
        "high_risk_count": len(high),
        "medium_risk_count": len(medium),
        "low_risk_count": len(low),
        "failed_count": len(failures),
        "high_risk_topics": _high_risk_topics(findings),
        "missing_documents": deduped_missing,
        "flags": flags,
        "supplementary_questions": [
            item.to_dict() for item in items if item.category != "core"
        ],
    }


def run_freeform_query(
    question: str,
    session_index: Any,
    legal_corpus_index: Any,
) -> dict[str, Any]:
    """Answer one ad-hoc question from the reviewing advocate."""
    cleaned = (question or "").strip()
    if not cleaned:
        return {
            "question": "",
            "finding": "No question was supplied.",
            "reasoning": "",
            "document_citation": "",
            "statutory_citation": "",
            "constitutional_basis": "",
            "risk_level": "LOW",
            "recommendation": "Enter a question to query the documents and statutes.",
            "missing_documents": [],
            "confidence": "LOW",
            "query_source": "freeform",
            "failed": True,
        }

    result = answer_question(
        session_index, legal_corpus_index, cleaned, description="free-form query"
    )
    if not result.get("constitutional_basis"):
        result["constitutional_basis"] = get_constitutional_basis("general")
    result.update({
        "question_id": 0,
        "question": cleaned,
        "topic": "general",
        "category": "freeform",
        "query_source": "freeform",
        "failed": bool(result.get("parse_failed")),
    })
    return result


__all__ = [
    "VALID_TRANSACTION_TYPES", "CHECKLISTS", "RED_FLAG_RULES", "ChecklistItem",
    "build_checklist", "detect_red_flags", "resolve_city", "run_checklist",
    "run_freeform_query", "any_phrase",
]
