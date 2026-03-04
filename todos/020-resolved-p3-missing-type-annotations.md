---
status: resolved
priority: p3
issue_id: "020"
tags: [code-review, quality, rmf-generator]
dependencies: []
---

# Missing Type Annotations Across B1 Scripts

## Problem Statement

Six functions in `retag_template.py` and two in `fill_template.py` lack type annotations. The project uses Python 3.13 and Pydantic (which enforces types), so annotating CLI scripts would improve consistency and IDE support.

## Findings

- **Source**: kieran-python-reviewer
- **Functions missing annotations**:
  - `retag_template.py`: `get_all_paragraphs(doc)`, `has_any_placeholder(text)`, `apply_replacements(text, occurrence_counter)`, `process_paragraph(paragraph, occurrence_counter)`, `retag(src_path, dst_path)`, `verify(dst_path)`
  - `fill_template.py`: `load_system_yaml(path: str)` — param should be `Path` not `str`, `build_context()` — return should be `dict[str, str]` not `dict`
- **Also**: `models/system.py` uses `Optional[str]` instead of modern `str | None`

## Proposed Solutions

### Option A: Add annotations to all functions
- **Effort**: Small (30 min)
- **Risk**: None

## Acceptance Criteria

- [ ] All public functions in both scripts have parameter and return type annotations
- [ ] `load_system_yaml` accepts `Path` parameter (remove `str()` cast at call site)
- [ ] `build_context` returns `dict[str, str]`

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-02 | Created from B1 code review | |
