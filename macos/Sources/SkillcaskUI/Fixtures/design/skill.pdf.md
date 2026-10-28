---
name: pdf
description: Read, fill and create PDF files.
license: Apache-2.0
---
## When to use

Use this skill whenever a task reads from or writes to a .pdf file: extracting text or tables, merging, splitting, rotating, filling forms, OCR on scans.

## Reading

Prefer `pdftotext -layout` for text PDFs. For scanned pages run `scripts/ocr.py` first and read its output.

## Forms

List fields with `scripts/fields.py`, then fill with `scripts/fill_form.py` from a JSON mapping…
