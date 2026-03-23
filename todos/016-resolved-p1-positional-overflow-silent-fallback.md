---
status: resolved
priority: p1
issue_id: "016"
category: todo
tags: [code-review, correctness, rmf-generator]
dependencies: []
related:
  - "[[2026-03-02-rmf-doc-automation-oss-reuse-brainstorm|rmf-brainstorm]]"
  - "[[rmf-doc-automation-stack-selection|rmf-stack-decision]]"
---

# Silent Fallback on Positional Placeholder Overflow

## Problem Statement

In `retag_template.py` line 126, the positional replacement logic silently falls back to the last mapping value when more occurrences are found than expected:

```python
replacement = values[idx] if idx < len(values) else values[-1]
```

If a template has more occurrences of `{Low, Moderate, or High}` than the 3 defined (Confidentiality, Integrity, Availability), the extra occurrence silently gets mapped to `{{ availability }}` — injecting **wrong data into a compliance document**. For an RMF/NIST 800-53 document, silent data corruption is unacceptable.

## Findings

- **Source**: kieran-python-reviewer, performance-oracle (2 agents independently flagged)
- **File**: `basalt-stack/tools/rmf-generator/retag_template.py`, line 126
- **Current behavior**: Silent fallback to `values[-1]` on overflow
- **Expected behavior**: Fail loudly with a clear error message
- **Scope**: Affects all 3 positional mappings (`{Low, Moderate, or High}`, `{Name, Rank, Organization}`, `{Title}`)

## Proposed Solutions

### Option A: Raise ValueError on overflow (Recommended)
- **Pros**: Fail-fast, immediately surfaces template changes or mapping errors
- **Cons**: None for a one-time script
- **Effort**: Small (2-line change)
- **Risk**: None

```python
if idx >= len(values):
    raise ValueError(
        f"Unexpected occurrence #{idx + 1} of positional placeholder "
        f"'{key}' (only {len(values)} mappings defined)"
    )
replacement = values[idx]
```

### Option B: Log warning and continue
- **Pros**: Non-blocking for exploratory runs
- **Cons**: Still produces incorrect output silently if warning is missed
- **Effort**: Small
- **Risk**: Medium — compliance docs with wrong data could go unnoticed

## Recommended Action

Option A. A compliance document generator must never silently produce wrong data.

## Technical Details

- **Affected files**: `basalt-stack/tools/rmf-generator/retag_template.py`
- **Affected components**: `apply_replacements()` function
- **Database changes**: None

## Acceptance Criteria

- [ ] `retag_template.py` raises `ValueError` when a positional placeholder has more occurrences than defined mappings
- [ ] Running `python retag_template.py --verify` still succeeds (no overflow in MP template)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-02 | Created from B1 code review | 2 of 6 review agents independently flagged this |

## Resources

- PR/Branch: B1 uncommitted changes on `master`
