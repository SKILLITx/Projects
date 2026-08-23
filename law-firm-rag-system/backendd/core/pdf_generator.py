"""
PDF memorandum writer.

``reportlab`` was declared in ``requirements.txt`` from the first commit but no
module ever imported it — the PDF deliverable promised in the architecture
document did not exist.  This writer closes that gap, consuming the same
:class:`~core.memo_model.MemoModel` as the Word writer so the two artefacts
cannot diverge in content, ordering or compliance determinations.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

from core.memo_model import DISCLAIMER, MemoModel, build_memo_model

logger = logging.getLogger(__name__)

NAVY = colors.HexColor("#143C6E")
AZURE = colors.HexColor("#0070A4")
RISK_RED = colors.HexColor("#AA2323")
AMBER = colors.HexColor("#B85C00")
FOREST = colors.HexColor("#1E6E37")
SLATE = colors.HexColor("#4B5563")
HAIRLINE = colors.HexColor("#D8DEE9")
SHADE_LABEL = colors.HexColor("#EEF2F8")
SHADE_HIGH = colors.HexColor("#FBE9E9")
SHADE_MEDIUM = colors.HexColor("#FDF2E3")
SHADE_LOW = colors.HexColor("#EAF6EE")
SHADE_MUTED = colors.HexColor("#F4F6FA")

RISK_STYLE = {
    "HIGH": ("HIGH RISK", RISK_RED, SHADE_HIGH),
    "MEDIUM": ("MEDIUM RISK", AMBER, SHADE_MEDIUM),
    "LOW": ("LOW RISK", FOREST, SHADE_LOW),
}

CONTENT_WIDTH = A4[0] - 4.4 * cm


def _styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "MemoTitle", parent=base["Title"], fontName="Helvetica-Bold",
            fontSize=17, leading=21, textColor=NAVY, alignment=TA_CENTER,
            spaceAfter=2),
        "subtitle": ParagraphStyle(
            "MemoSubtitle", parent=base["Normal"], fontName="Helvetica",
            fontSize=11.5, leading=15, textColor=AZURE, alignment=TA_CENTER,
            spaceAfter=10),
        "firm": ParagraphStyle(
            "Firm", parent=base["Normal"], fontName="Helvetica-Bold",
            fontSize=15, leading=19, textColor=NAVY, alignment=TA_CENTER),
        "tagline": ParagraphStyle(
            "Tagline", parent=base["Normal"], fontName="Helvetica-Oblique",
            fontSize=9, leading=12, textColor=AZURE, alignment=TA_CENTER),
        "contact": ParagraphStyle(
            "Contact", parent=base["Normal"], fontName="Helvetica",
            fontSize=8, leading=11, textColor=SLATE, alignment=TA_CENTER,
            spaceAfter=8),
        "h1": ParagraphStyle(
            "H1", parent=base["Heading1"], fontName="Helvetica-Bold",
            fontSize=12.5, leading=16, textColor=NAVY,
            spaceBefore=12, spaceAfter=4),
        "h2": ParagraphStyle(
            "H2", parent=base["Heading2"], fontName="Helvetica-Bold",
            fontSize=10.5, leading=14, textColor=AZURE,
            spaceBefore=8, spaceAfter=3),
        "question": ParagraphStyle(
            "Question", parent=base["Normal"], fontName="Helvetica-Bold",
            fontSize=9.5, leading=12.5, textColor=NAVY,
            spaceBefore=9, spaceAfter=3),
        "body": ParagraphStyle(
            "Body", parent=base["Normal"], fontName="Helvetica",
            fontSize=9, leading=12.5, alignment=TA_JUSTIFY, spaceAfter=5),
        "note": ParagraphStyle(
            "Note", parent=base["Normal"], fontName="Helvetica-Oblique",
            fontSize=8, leading=11, textColor=SLATE, alignment=TA_JUSTIFY,
            spaceAfter=5),
        "cell": ParagraphStyle(
            "Cell", parent=base["Normal"], fontName="Helvetica",
            fontSize=8, leading=10.8),
        "cell_label": ParagraphStyle(
            "CellLabel", parent=base["Normal"], fontName="Helvetica-Bold",
            fontSize=8, leading=10.8, textColor=NAVY),
        "cell_head": ParagraphStyle(
            "CellHead", parent=base["Normal"], fontName="Helvetica-Bold",
            fontSize=8, leading=10.8, textColor=colors.white),
    }


def _escape(value: Any, fallback: str = "Not stated") -> str:
    """Escape for reportlab's mini-markup, preserving line breaks."""
    text = str(value if value is not None else "").strip()
    if not text:
        text = fallback
    text = (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
    return text.replace("\n", "<br/>")


def _grid(extra: list[tuple] | None = None) -> TableStyle:
    commands: list[tuple] = [
        ("GRID", (0, 0), (-1, -1), 0.4, HAIRLINE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 3.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
    ]
    commands.extend(extra or [])
    return TableStyle(commands)


class _MemoTemplate(BaseDocTemplate):
    """Document template that paints the running header and footer."""

    def __init__(self, path: str, model: MemoModel, **kwargs: Any) -> None:
        super().__init__(path, pagesize=A4,
                         leftMargin=2.2 * cm, rightMargin=2.2 * cm,
                         topMargin=2.0 * cm, bottomMargin=1.8 * cm, **kwargs)
        self.model = model
        frame = Frame(self.leftMargin, self.bottomMargin,
                      self.width, self.height, id="body")
        self.addPageTemplates([
            PageTemplate(id="memo", frames=[frame], onPage=self._decorate)
        ])

    def _decorate(self, canvas: Any, doc: Any) -> None:
        canvas.saveState()
        canvas.setFont("Helvetica", 7.5)
        canvas.setFillColor(SLATE)
        canvas.drawRightString(
            A4[0] - 2.2 * cm, A4[1] - 1.35 * cm,
            f"{self.model.firm_name} — Due Diligence Review",
        )
        canvas.setStrokeColor(HAIRLINE)
        canvas.setLineWidth(0.5)
        canvas.line(2.2 * cm, A4[1] - 1.5 * cm, A4[0] - 2.2 * cm, A4[1] - 1.5 * cm)
        canvas.drawCentredString(A4[0] / 2.0, 1.15 * cm, f"Page {doc.page}")
        canvas.restoreState()


def _letterhead(story: list, model: MemoModel, style: dict) -> None:
    if not model.has_letterhead:
        return
    story.append(Paragraph(_escape(model.firm_name.upper()), style["firm"]))
    if model.firm_tagline:
        story.append(Paragraph(_escape(model.firm_tagline), style["tagline"]))
    contact = " · ".join(
        part for part in (model.firm_address, model.firm_phone, model.firm_email) if part
    )
    if contact:
        story.append(Paragraph(_escape(contact), style["contact"]))
    rule = Table([[""]], colWidths=[CONTENT_WIDTH], rowHeights=[1.2])
    rule.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), NAVY)]))
    story.append(rule)
    story.append(Spacer(1, 10))


def _cover(story: list, model: MemoModel, style: dict) -> None:
    story.append(Paragraph(_escape(model.title), style["title"]))
    story.append(Paragraph(_escape(model.subtitle), style["subtitle"]))

    label, colour, shade = RISK_STYLE.get(model.overall_risk, RISK_STYLE["LOW"])
    banner = Table([[Paragraph(
        f'<font color="{colour.hexval()}"><b>OVERALL ASSESSMENT: {label}</b></font>',
        ParagraphStyle("Banner", fontName="Helvetica-Bold", fontSize=11,
                       leading=15, alignment=TA_CENTER),
    )]], colWidths=[CONTENT_WIDTH])
    banner.setStyle(_grid([("BACKGROUND", (0, 0), (-1, -1), shade)]))
    story.append(banner)
    story.append(Spacer(1, 12))


def _key_value_table(rows: list[tuple[str, str]], style: dict,
                     label_width: float = 5.4 * cm) -> Table:
    data = [
        [Paragraph(_escape(key, ""), style["cell_label"]),
         Paragraph(_escape(value), style["cell"])]
        for key, value in rows
    ]
    table = Table(data, colWidths=[label_width, CONTENT_WIDTH - label_width])
    table.setStyle(_grid([("BACKGROUND", (0, 0), (0, -1), SHADE_LABEL)]))
    return table


def _summary(story: list, model: MemoModel, style: dict) -> None:
    story.append(Paragraph("1.&nbsp; Transaction Summary", style["h1"]))
    story.append(_key_value_table([
        ("Prepared by", model.firm_name),
        ("Date of review", model.generated_at),
        ("Transaction type", model.transaction_type.title()),
        ("City", model.city.title()),
        ("Controlling authority", model.authority_full_name or "Not determined"),
        ("Applicable bye-laws", model.relevant_bylaws or "Not determined"),
        ("Housing society", model.housing_society or "Not applicable"),
        ("Documents reviewed", str(len(model.document_names))),
        ("Questions assessed", str(model.total_questions)),
    ], style))
    story.append(Spacer(1, 8))

    if model.document_names:
        story.append(Paragraph("1.1&nbsp; Documents in the reviewed bundle", style["h2"]))
        listing = "<br/>".join(
            f"{index}. {_escape(name)}"
            for index, name in enumerate(model.document_names, start=1)
        )
        story.append(Paragraph(listing, style["body"]))
        story.append(Spacer(1, 6))


def _executive(story: list, model: MemoModel, style: dict) -> None:
    story.append(Paragraph("2.&nbsp; Executive Summary", style["h1"]))
    story.append(Paragraph(_escape(model.executive_summary), style["body"]))
    story.append(Spacer(1, 6))


def _risk(story: list, model: MemoModel, style: dict) -> None:
    story.append(Paragraph("3.&nbsp; Risk Summary", style["h1"]))
    headers = ["HIGH RISK", "MEDIUM RISK", "LOW RISK", "NOT ASSESSED"]
    colours = [RISK_RED, AMBER, FOREST, SLATE]
    shades = [SHADE_HIGH, SHADE_MEDIUM, SHADE_LOW, SHADE_MUTED]
    counts = [model.high_risk_count, model.medium_risk_count,
              model.low_risk_count, model.failed_count]

    centre = ParagraphStyle("Centre", fontName="Helvetica-Bold", fontSize=8,
                            leading=11, alignment=TA_CENTER)
    big = ParagraphStyle("Big", fontName="Helvetica-Bold", fontSize=15,
                         leading=19, alignment=TA_CENTER)

    header_row = [
        Paragraph(f'<font color="{colour.hexval()}">{header}</font>', centre)
        for header, colour in zip(headers, colours)
    ]
    value_row = [
        Paragraph(f'<font color="{colour.hexval()}">{count}</font>', big)
        for count, colour in zip(counts, colours)
    ]
    width = CONTENT_WIDTH / 4.0
    table = Table([header_row, value_row], colWidths=[width] * 4)
    commands = [("VALIGN", (0, 0), (-1, -1), "MIDDLE")]
    for column, shade in enumerate(shades):
        commands.append(("BACKGROUND", (column, 0), (column, -1), shade))
    table.setStyle(_grid(commands))
    story.append(table)
    story.append(Spacer(1, 8))


def _red_flags(story: list, model: MemoModel, style: dict) -> None:
    story.append(Paragraph("4.&nbsp; Red Flags", style["h1"]))
    if not model.red_flags:
        story.append(Paragraph(
            f'<font color="{FOREST.hexval()}">No transaction-stopping defect was '
            f'detected in the documents supplied. This is not a warranty of clean '
            f'title; it records only that the deterministic rules in this system '
            f'did not fire.</font>', style["body"]))
        story.append(Spacer(1, 6))
        return

    data = [[Paragraph("Ref", style["cell_head"]),
             Paragraph("Defect", style["cell_head"]),
             Paragraph("Statutory and constitutional basis", style["cell_head"])]]
    for flag in model.red_flags:
        detail = str(flag.get("label", ""))
        if flag.get("description"):
            detail += f"\n{flag['description']}"
        basis = f"{flag.get('statute', '')}\n{flag.get('article', '')}".strip()
        data.append([
            Paragraph(_escape(flag.get("id"), ""), style["cell_label"]),
            Paragraph(f'<font color="{RISK_RED.hexval()}">{_escape(detail)}</font>',
                      style["cell"]),
            Paragraph(_escape(basis, ""), style["cell"]),
        ])
    table = Table(data, colWidths=[1.8 * cm, 7.2 * cm, CONTENT_WIDTH - 9.0 * cm],
                  repeatRows=1)
    table.setStyle(_grid([
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("BACKGROUND", (0, 1), (0, -1), SHADE_HIGH),
    ]))
    story.append(table)
    story.append(Spacer(1, 8))


def _findings(story: list, model: MemoModel, style: dict) -> None:
    story.append(Paragraph("5.&nbsp; Clause-by-Clause Findings", style["h1"]))
    story.append(Paragraph(
        "Findings are ordered by assessed risk. Each entry records the evidence relied "
        "on and the provision it engages, so that any conclusion can be independently "
        "verified against the original document.", style["note"]))

    if not model.findings:
        story.append(Paragraph("No findings were produced.", style["body"]))
        return

    for finding in model.findings:
        risk = str(finding.get("risk_level", "LOW")).upper()
        label, colour, shade = RISK_STYLE.get(risk, RISK_STYLE["LOW"])

        rows: list[tuple[str, str]] = [
            ("Risk", label),
            ("Finding", str(finding.get("finding") or "")),
            ("Reasoning", str(finding.get("reasoning") or "")),
            ("Document citation", str(finding.get("document_citation") or "")),
            ("Statutory citation", str(finding.get("statutory_citation") or "")),
            ("Constitutional basis", str(finding.get("constitutional_basis") or "")),
            ("Recommendation", str(finding.get("recommendation") or "")),
        ]
        missing = finding.get("missing_documents") or []
        if missing:
            rows.append(("Documents required", "; ".join(str(m) for m in missing)))
        if finding.get("confidence"):
            rows.append(("Model confidence", str(finding["confidence"]).upper()))

        data = []
        for key, value in rows:
            if key == "Risk":
                cell = Paragraph(
                    f'<font color="{colour.hexval()}"><b>{value}</b></font>', style["cell"])
            else:
                cell = Paragraph(_escape(value), style["cell"])
            data.append([Paragraph(_escape(key, ""), style["cell_label"]), cell])

        table = Table(data, colWidths=[3.9 * cm, CONTENT_WIDTH - 3.9 * cm])
        table.setStyle(_grid([
            ("BACKGROUND", (0, 0), (0, -1), SHADE_LABEL),
            ("BACKGROUND", (1, 0), (1, 0), shade),
        ]))

        block = [
            Paragraph(
                f"Q{finding.get('question_id', '—')}.&nbsp; "
                f"{_escape(str(finding.get('question', ''))[:170], '')}",
                style["question"]),
            table,
        ]
        story.append(KeepTogether(block) if len(rows) <= 7 else block[0])
        if len(rows) > 7:
            story.append(table)
    story.append(Spacer(1, 8))


def _compliance(story: list, model: MemoModel, style: dict) -> None:
    story.append(Paragraph("6.&nbsp; Tax, AML and Processing Compliance", style["h1"]))
    data = [[Paragraph("Matter", style["cell_head"]),
             Paragraph("Determination", style["cell_head"])]]
    highlight_rows: list[int] = []
    for index, row in enumerate(model.compliance_rows, start=1):
        text = row.value + (f"\n{row.note}" if row.note else "")
        if row.action_required:
            highlight_rows.append(index)
            body = Paragraph(
                f'<font color="{RISK_RED.hexval()}"><b>{_escape(text)}</b></font>',
                style["cell"])
        else:
            body = Paragraph(_escape(text), style["cell"])
        data.append([Paragraph(_escape(row.label, ""), style["cell_label"]), body])

    table = Table(data, colWidths=[7.4 * cm, CONTENT_WIDTH - 7.4 * cm], repeatRows=1)
    commands = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("BACKGROUND", (0, 1), (0, -1), SHADE_LABEL),
    ]
    commands.extend(("BACKGROUND", (1, row), (1, row), SHADE_HIGH) for row in highlight_rows)
    table.setStyle(_grid(commands))
    story.append(table)
    story.append(Spacer(1, 6))
    story.append(Paragraph(
        "Statutory reference: Income Tax Ordinance 2001, sections 236C and 236K "
        "(withholding tax on immovable property transactions); Anti-Money Laundering "
        "Act 2010 (enhanced due diligence); SECP AML/CFT Regulations 2018 (designated "
        "non-financial businesses and professions). Constitutional basis: Article 23 — "
        "right to acquire property subject to law.", style["note"]))
    story.append(Spacer(1, 6))


def _missing(story: list, model: MemoModel, style: dict) -> None:
    story.append(Paragraph("7.&nbsp; Documents to Requisition", style["h1"]))
    if not model.missing_documents:
        story.append(Paragraph(
            f'<font color="{FOREST.hexval()}">No further documents were identified as '
            f'missing from the bundle.</font>', style["body"]))
    else:
        listing = "<br/>".join(
            f'<font color="{RISK_RED.hexval()}">•&nbsp; {_escape(name)}</font>'
            for name in model.missing_documents
        )
        story.append(Paragraph(listing, style["body"]))
    story.append(Spacer(1, 6))


def _disclaimer(story: list, style: dict) -> None:
    story.append(Paragraph("8.&nbsp; Scope and Disclaimer", style["h1"]))
    story.append(Paragraph(_escape(DISCLAIMER), style["note"]))


# ──────────────────────────────────────────────────────────────────────────
#  Entry point
# ──────────────────────────────────────────────────────────────────────────
def generate_memo_pdf(
    results: dict[str, Any],
    output_path: str | Path,
    firm_name: str = "Law Firm",
    firm_address: str = "",
    firm_phone: str = "",
    firm_email: str = "",
    firm_tagline: str = "",
    transaction_type: str = "property",
    city: str = "islamabad",
    document_names: list[str] | None = None,
    flags: dict[str, Any] | None = None,
) -> str:
    """Render the memorandum as a PDF and return its path."""
    model = build_memo_model(
        results,
        firm_name=firm_name, firm_address=firm_address, firm_phone=firm_phone,
        firm_email=firm_email, firm_tagline=firm_tagline,
        transaction_type=transaction_type, city=city,
        document_names=document_names, flags=flags,
    )
    return write_pdf(model, output_path)


def write_pdf(model: MemoModel, output_path: str | Path) -> str:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)

    style = _styles()
    story: list = []
    _letterhead(story, model, style)
    _cover(story, model, style)
    _summary(story, model, style)
    _executive(story, model, style)
    _risk(story, model, style)
    _red_flags(story, model, style)
    story.append(PageBreak())
    _findings(story, model, style)
    _compliance(story, model, style)
    _missing(story, model, style)
    _disclaimer(story, style)

    _MemoTemplate(str(path), model,
                  title="Due Diligence Review Memorandum",
                  author=model.firm_name).build(story)
    logger.info("PDF memorandum written: %s", path)
    return str(path)
