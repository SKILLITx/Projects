"""
utils/text_cleaning.py

Cleans raw extracted (native or OCR) text while preserving legal
structure: numbered clauses ("1.", "Clause 3.2", "Section 4(a)"),
section titles (ALL CAPS or "SECTION ..." lines), and table-like
spacing. Aggressive whitespace collapsing is avoided wherever it would
destroy that structure.
"""

import re

# Patterns that indicate a line is legally significant and must not be
# merged into the previous line or have its leading numbering stripped.
CLAUSE_PATTERN = re.compile(
    r"^\s*(\(?\d+(\.\d+)*\)?[\.\)]?|\(?[a-zA-Z]\)|SECTION\s+\d+|CLAUSE\s+\d+)\s+",
    re.IGNORECASE,
)

# Common OCR artifacts seen in scanned Pakistani legal documents
# (stamps, signatures bleeding into text, broken ligatures).
OCR_ARTIFACT_PATTERNS = [
    (re.compile(r"[|]{2,}"), ""),          # stray vertical bars from table lines
    (re.compile(r"_{3,}"), ""),             # long underscores from signature lines
    (re.compile(r"[\u200b\u200c\u200d]"), ""),  # zero-width chars common in Urdu OCR
    (re.compile(r"[ \t]{2,}"), " "),        # duplicated spaces/tabs
]


def remove_ocr_artifacts(text: str) -> str:
    for pattern, replacement in OCR_ARTIFACT_PATTERNS:
        text = pattern.sub(replacement, text)
    return text


def fix_broken_line_wrapping(text: str) -> str:
    """
    PDF text extraction frequently breaks a sentence mid-word at the end
    of a printed line. We rejoin lines UNLESS the next line starts a new
    clause/section (preserved) or the current line ends with a sentence
    terminator.
    """
    lines = text.split("\n")
    merged: list[str] = []
    buffer = ""

    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            if buffer:
                merged.append(buffer)
                buffer = ""
            merged.append("")  # preserve paragraph breaks
            continue

        starts_new_clause = bool(CLAUSE_PATTERN.match(line))
        if not buffer:
            buffer = line
        elif starts_new_clause or buffer.endswith((".", ":", ";")):
            merged.append(buffer)
            buffer = line
        else:
            buffer = f"{buffer} {line}"

    if buffer:
        merged.append(buffer)

    return "\n".join(merged)


def clean_text(raw_text: str) -> str:
    """Full cleaning pipeline applied to every extracted page."""
    if not raw_text:
        return ""
    text = remove_ocr_artifacts(raw_text)
    text = fix_broken_line_wrapping(text)
    # Collapse 3+ blank lines into a single blank line, keep structure.
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()
