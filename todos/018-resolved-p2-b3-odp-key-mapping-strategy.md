---
status: resolved
priority: p2
issue_id: "018"
tags: [code-review, architecture, rmf-generator, b3-prep]
dependencies: []
---

# B3 Design Decision: ODP Key Mapping Strategy

## Problem Statement

There is a structural gap between how ODP values are identified in the codebase:

1. **`retag_template.py`** maps bracket placeholders to Jinja2 names: `[defined frequency]` -> `{{ odp_defined_frequency }}`
2. **`models/control.py`** (`ODPValue`) uses bracket placeholders: `placeholder = "[defined frequency]"`
3. **`fill_template.py`** uses Jinja2 names as dict keys: `"odp_defined_frequency": "annually"`

In B3, the LLM will return `NarrativeOutput` containing `list[ODPValue]` with bracket-style placeholders. Converting those to the flat `dict[str, str]` that docxtpl needs requires a mapping from bracket placeholders to Jinja2 variable names. This mapping currently lives **only** in `retag_template.py`'s `SIMPLE_MAPPINGS` — a "one-time" script that future work won't touch.

## Findings

- **Source**: architecture-strategist
- **Severity**: Medium (does not block B1 or B2, but must be resolved before B3)
- **Key files**:
  - `retag_template.py` — holds authoritative mapping in `SIMPLE_MAPPINGS`
  - `models/control.py` — `ODPValue.placeholder` uses bracket notation
  - `fill_template.py` — `HARDCODED_ODP_VALUES` uses Jinja2 variable names

## Proposed Solutions

### Option A: LLM returns Jinja2 variable names directly (Recommended for MVP)
- Have the LLM prompt/schema use `odp_defined_frequency` as the key, not `[defined frequency]`
- **Pros**: Simplest, no extra mapping layer needed, LLM output drops directly into context dict
- **Cons**: Couples LLM schema to template internals
- **Effort**: Small
- **Risk**: Low

### Option B: Extract shared mapping module
- Create `mappings.py` with `BRACKET_TO_JINJA2` dict extracted from `retag_template.py`
- B3 uses this to translate `ODPValue.placeholder` -> Jinja2 name
- **Pros**: Clean separation, single source of truth
- **Cons**: Extra module, slight over-engineering for one template
- **Effort**: Medium
- **Risk**: Low

### Option C: Add Jinja2 name field to ODPValue model
- Extend `ODPValue` with `jinja2_name: str` alongside `placeholder: str`
- **Pros**: Self-contained, no external mapping needed
- **Cons**: Redundant data, model knows about template internals
- **Effort**: Small
- **Risk**: Low

## Recommended Action

**DECIDED: Option A** (2026-03-02). LLM prompt/schema will use Jinja2 variable names
directly. Comment added to `retag_template.py` noting SIMPLE_MAPPINGS is authoritative
reference only — B3 does not need a runtime mapping layer.

## Technical Details

- **Affected files**: `models/control.py`, `fill_template.py`, future `llm/` module
- **Decision needed by**: Before B3 implementation

## Acceptance Criteria

- [ ] Design decision documented (which option chosen)
- [ ] B3 implementation can produce a `dict[str, str]` keyed by Jinja2 variable names from LLM output

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-02 | Created from B1 code review | Architecture reviewer identified structural gap |

## Resources

- `docs/solutions/research-decisions/rmf-doc-automation-stack-selection.md`
