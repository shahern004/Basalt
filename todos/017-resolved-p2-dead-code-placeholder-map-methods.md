---
status: resolved
priority: p2
issue_id: "017"
category: todo
tags: [code-review, dead-code, rmf-generator]
dependencies: []
related:
  - "[[2026-03-02-rmf-doc-automation-oss-reuse-brainstorm|rmf-brainstorm]]"
---

# Dead Code: placeholder_map() and signatory_replacements() in SystemDescription

## Problem Statement

`models/system.py` lines 61-88 contain two methods (`placeholder_map()` and `signatory_replacements()`) that are never called by any code in the project. They were designed for a pre-retag workflow using original `{curly}` placeholder syntax, but B1 moved the mapping logic to module-level dicts in `retag_template.py` and `fill_template.py`.

These methods are architecturally misleading: `placeholder_map()` returns keys like `{Organization}` (original template syntax), while the actual pipeline now expects keys like `organization` (Jinja2 variable names). A future developer reading `system.py` might try to use `placeholder_map()` and get silently wrong behavior.

## Findings

- **Source**: kieran-python-reviewer, code-simplicity-reviewer, architecture-strategist (3 agents independently flagged)
- **File**: `basalt-stack/tools/rmf-generator/models/system.py`, lines 61-88
- **Methods**: `SystemDescription.placeholder_map()` and `SystemDescription.signatory_replacements()`
- **Impact**: 28 lines of dead code creating confusion about source of truth for mappings

## Proposed Solutions

### Option A: Delete both methods (Recommended)
- **Pros**: Eliminates confusion, reduces code surface
- **Cons**: None — methods are unused
- **Effort**: Small (delete 28 lines)
- **Risk**: None

### Option B: Add deprecation comment
- **Pros**: Preserves code for reference
- **Cons**: Still misleading if someone imports and uses them
- **Effort**: Small
- **Risk**: Low

## Recommended Action

Option A. Delete the methods. Git history preserves them if needed.

## Technical Details

- **Affected files**: `basalt-stack/tools/rmf-generator/models/system.py`

## Acceptance Criteria

- [ ] `placeholder_map()` and `signatory_replacements()` removed from `SystemDescription`
- [ ] `from typing import Optional` removed if no longer needed (use `str | None` for Python 3.13)
- [ ] `fill_template.py` and `retag_template.py` still run successfully

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-02 | Created from B1 code review | 3 of 6 agents converged on this finding |

## Resources

- PR/Branch: B1 uncommitted changes on `master`
