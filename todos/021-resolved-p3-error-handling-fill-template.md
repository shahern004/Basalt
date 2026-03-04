---
status: resolved
priority: p3
issue_id: "021"
tags: [code-review, quality, rmf-generator]
dependencies: []
---

# Error Handling Gaps in fill_template.py

## Problem Statement

`fill_template.py` lacks user-friendly error handling in three areas:

1. **YAML parsing** (line 92): `yaml.safe_load()` raises raw `yaml.YAMLError` on malformed input
2. **Pydantic validation** (line 93): `SystemDescription(**data)` raises a verbose `ValidationError` wall
3. **Template rendering** (line 177): `tpl.render(context)` raises raw `UndefinedError` if a variable is missing

For a CLI tool, catching these and printing human-readable messages improves the developer experience.

## Findings

- **Source**: kieran-python-reviewer, security-sentinel
- **File**: `basalt-stack/tools/rmf-generator/fill_template.py`

## Proposed Solutions

### Option A: Wrap each in try/except with clear messages
```python
try:
    data = yaml.safe_load(f)
except yaml.YAMLError as exc:
    print(f"ERROR: Invalid YAML in {path}: {exc}", file=sys.stderr)
    sys.exit(1)
```
- **Effort**: Small (add 3 try/except blocks, ~15 lines)
- **Risk**: None

## Acceptance Criteria

- [ ] Malformed YAML produces a one-line error message, not a traceback
- [ ] Missing YAML fields produce a clear "field X required" message
- [ ] Missing template variables produce a helpful message

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-02 | Created from B1 code review | |
