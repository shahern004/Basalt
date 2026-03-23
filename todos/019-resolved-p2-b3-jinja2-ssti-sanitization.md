---
status: resolved
priority: p2
issue_id: "019"
category: todo
tags: [code-review, security, rmf-generator, b3-prep]
dependencies: []
related:
  - "[[rmf-doc-automation-stack-selection|rmf-stack-decision]]"
---

# B3 Prep: Jinja2 Value Sanitization for LLM Output

## Problem Statement

`fill_template.py` line 177 calls `tpl.render(context)` where context values are passed directly to docxtpl's Jinja2 engine. Currently all values are developer-controlled (hardcoded or from YAML), so this is safe.

In B3, ODP values will come from vLLM structured output. If an LLM response contains Jinja2 metacharacters (`{{ }}`, `{% %}`, `{# #}`), they would be interpreted by the Jinja2 engine during rendering — a Server-Side Template Injection (SSTI) vector.

## Findings

- **Source**: security-sentinel
- **Severity**: Medium (theoretical now, relevant at B3)
- **Mitigating factor**: docxtpl uses `jinja2.sandbox.SandboxedEnvironment` internally, limiting damage
- **Risk scenario**: LLM hallucinates or is prompted to output `{{ config.__class__.__init__.__globals__ }}`

## Proposed Solutions

### Option A: Strip Jinja2 metacharacters from LLM output (Recommended)
```python
import re
JINJA2_PATTERN = re.compile(r'\{\{|\}\}|\{%|%\}|\{#|#\}')

def sanitize_template_value(value: str) -> str:
    return JINJA2_PATTERN.sub('', value)
```
- **Pros**: Simple, defense-in-depth, 5 lines
- **Cons**: Could strip legitimate `{{` in text (unlikely in compliance docs)
- **Effort**: Small
- **Risk**: None

### Option B: Escape metacharacters instead of stripping
- Replace `{{` with `{ {` (space-separated)
- **Pros**: Preserves intent if `{{` appears legitimately
- **Cons**: Slightly more complex
- **Effort**: Small
- **Risk**: None

## Recommended Action

Implement Option A as part of B3 LLM integration. Not needed for B1/B2.

## Technical Details

- **Affected files**: Future `llm/` module or `generators/context_assembler.py`
- **When**: Before LLM-generated values enter the docxtpl rendering pipeline

## Acceptance Criteria

- [ ] All LLM-generated ODP values pass through sanitization before `tpl.render()`
- [ ] Test case: value containing `{{ malicious }}` is stripped before rendering

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-02 | Created from B1 code review | Security reviewer flagged theoretical SSTI vector |

## Resources

- docxtpl uses `jinja2.sandbox.SandboxedEnvironment` (partial mitigation)
- OWASP SSTI reference: https://owasp.org/www-project-web-security-testing-guide/
