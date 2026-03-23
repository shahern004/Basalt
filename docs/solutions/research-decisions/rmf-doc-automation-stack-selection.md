---
title: "RMF Document Automation — OSS Stack Selection"
date: 2026-03-02
category: research-decisions
tags:
  - rmf
  - oscal
  - docxtpl
  - vllm
  - compliance
  - structured-output
  - air-gap
  - nist-800-53
  - pydantic
  - document-generation
components:
  - basalt-stack/tools/rmf-generator
  - basalt-stack/inference/vllm
  - basalt-stack/inference/litellm
status: decided
summary: >
  Researched the full OSS landscape for RMF compliance document automation
  and selected docxtpl + vLLM native structured output + OSCAL catalog +
  YAML system context as the MVP stack for filling .docx RMF plan templates
  with LLM-generated content on an air-gapped network.
aliases:
  - rmf-stack-decision
  - stack-selection
related:
  - "[[2026-03-02-rmf-doc-automation-oss-reuse-brainstorm|rmf-brainstorm]]"
  - "[[rmf-generator-pivot-notes|rmf-pivot]]"
  - "[[basalt-development-roadmap|roadmap]]"
---

# RMF Document Automation — Stack Selection

## Problem

Basalt needs to auto-generate templatized RMF/SSP control artifacts from existing `.docx` NIST 800-53 plan templates. The LLM fills Organization-Defined Parameter (ODP) slots and synthesizes implementation narrative paragraphs, while all formatting, structure, and deterministic content stays pixel-perfect from the original template. Must work fully air-gapped.

Before building custom tooling, we surveyed the OSS landscape to maximize reuse.

## Decided Stack

| Layer | Tool | Why |
|-------|------|-----|
| Template engine | **docxtpl** (900+ stars) | Jinja2-in-docx. Preserves all formatting natively, handles cross-run XML placeholders. Proven for compliance reports. |
| Structured LLM output | **vLLM native `response_format`** | Zero extra deps — already in our stack. Pass JSON schema, get guaranteed-valid JSON. Fallback: instructor → guidance-ai. |
| Control data | **NIST OSCAL catalog JSON** (+ oscal-pydantic) | Data source for control definitions and ODPs. NOT a document generation pipeline. |
| System context | **YAML** (Pydantic validated) | Org data, system description, risk posture. Human-readable, already built (`notional_system.yaml`). |
| Prompt patterns | **Corelight iterative** + **Sapienza accumulated** | Detect slots deterministically → LLM fills → Pydantic validates → retry if invalid. |

## Pipeline

```
notional_system.yaml ──► Pydantic SystemDescription
                              │
OSCAL catalog JSON ──► Control definitions + ODP list
                              │
Template .docx ──► docxtpl extracts placeholder list
                              │
                    ┌─────────┴──────────┐
                    │                    │
              deterministic         vLLM via response_format
              ({Organization},      ([defined ...] ODP values +
               {System Name},       narrative paragraphs,
               impact levels)       constrained to JSON schema)
                    │                    │
                    │              Pydantic validation
                    │              (retry if invalid)
                    │                    │
                    └─────────┬──────────┘
                              │
                    docxtpl context dict
                              │
                    docxtpl.render(context)
                              │
                    pixel-perfect filled .docx
```

## Key Findings

1. **OSCAL = data source, not document generator.** Every OSCAL-to-docx tool (trestle, GoComply, GSA) uses pandoc/OpenXML and none produce pixel-perfect template output. Use OSCAL catalog for control text and ODPs only.

2. **No turnkey OSS exists for "LLM fills compliance templates."** Market gap. Paramify charges $120k+ for this as SaaS. We're building a novel combination, not reinventing a wheel.

3. **vLLM v0.8.2+ has native structured output** via `response_format` in the OpenAI-compatible API. Uses guidance-ai as backend. May eliminate need for instructor/outlines as separate deps. Test through LiteLLM proxy first.

4. **docxtpl handles the hard docx problem.** Cross-run placeholder replacement, formatting preservation, conditionals, loops — all solved. One-time cost: re-tag templates from `{placeholder}` to `{{ jinja2 }}` syntax.

## Tools Evaluated and Rejected

| Tool | Why Rejected |
|------|-------------|
| python-docx | Low-level, no templating; docxtpl wraps it |
| docx-mailmerge2 | No conditionals/loops; less flexible |
| Documentero | Cloud SaaS; not air-gap compatible |
| guidance-ai (21.3k stars) | Overkill if vLLM native suffices; kept as fallback |
| instructor (12.5k stars) | Prompt-level not token-level; less efficient; kept as fallback |
| Outlines (~9k stars) | Redundant given vLLM native support |
| compliance-trestle (237 stars) | Wrong direction — pandoc ≠ pixel-perfect; Phase 2+ candidate |
| CivicActions ssp-toolkit (48 stars) | Rev 4 only; pandoc output; architecture reference only |
| GoComply/fedramp (44 stars) | Explicitly WIP with blank fields; Go not Python |
| GovReady-Q (~100 stars) | Full Django app; massive scope for MVP |
| GSA tools (<20 stars) | Dated (2020), C#, dead projects |
| Paramify | Commercial SaaS ($120k+); validates market |

## Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Template engine | docxtpl | Pixel-perfect formatting, cross-run handling, proven |
| Structured output | vLLM native `response_format` (first), instructor (fallback) | Zero deps; already in stack |
| OSCAL role | Data source only | OSCAL is for representing, not rendering |
| System context | YAML + Pydantic | Human-readable, typed, already built |
| Demo scope | MP (Media Protection) only | 1 template = 30 placeholders, proves the pattern |
| Template re-tagging | Manual for MP, script later | 30 placeholders in one file < 1 hour manual |
| Narrative scope | ODP slot-fills + 1 stretch narrative | Short phrases are reliable; full paragraphs are stretch goal |
| Fallback if no vLLM | `--mock` flag with pre-generated JSON | Pipeline works without live model; preserves air-gap story |
| Web UI | None for MVP | YAGNI — CLI is sufficient |

## YAGNI — Do Not Build

- Full OSCAL SSP authoring pipeline
- OSCAL JSON/XML export
- Multi-agent orchestration framework
- Web UI
- Custom XML run manipulation code
- All 20 control families (just MP for demo)
- Custom constrained generation engine

## Implementation Order (Critical Path to March 5 Demo)

**Day 1 — Template + Data Layer (no LLM needed)**
1. Re-tag MP template to Jinja2 syntax manually (~45 min)
2. Install docxtpl, write standalone `fill_template.py` with hardcoded dict → verify pixel-perfect output
3. Build context assembler: `notional_system.yaml` → Pydantic → docxtpl context dict

**Day 2 — LLM Integration**
4. Define Pydantic schema for 22 ODP values, write prompt + `response_format` call
5. Wire LLM output into docxtpl context; run full pipeline
6. Attempt 1 narrative paragraph (MP-1); fall back to curated example if quality poor

**Day 3 — Demo Prep**
7. Build PowerPoint deck
8. Record backup screencast

**Critical path**: Steps 1→2→3→5. Step 4 (LLM) can be mocked.

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| vLLM/model not ready | Build with `--mock` flag from Day 1. Generate mock JSON via Claude. Download weights as background task. |
| docxtpl cross-run splits (5 of 30 placeholders) | Retype the 5 split placeholders in Word to force single-run, then convert to Jinja2 |
| LLM narrative quality from 20B model | Constrain demo to ODP slot-fills (short phrases). Show 1 curated gold-standard narrative. |
| `response_format` through LiteLLM proxy | Test vLLM direct (8001) first, then through LiteLLM (8000). Fall back to instructor if proxy mangles it. |

## Open Questions (Remaining)

1. Does `response_format` work reliably through LiteLLM proxy? → Test once vLLM is running
2. What notional supporting docs to create? → Suggested: `org_security_policy_excerpts.yaml`, `system_architecture_summary.txt`, `risk_posture.yaml`
3. gpt-oss-20b model format (safetensors vs GGUF)? → Check when downloading

## Existing Assets (Reusable)

| Asset | Path | Status |
|-------|------|--------|
| Pydantic system models | `basalt-stack/tools/rmf-generator/models/system.py` | Ready |
| Pydantic ODP models | `basalt-stack/tools/rmf-generator/models/control.py` | Ready |
| OSCAL catalog (10MB) | `basalt-stack/tools/rmf-generator/data/nist-800-53-catalog.json` | Ready |
| Notional system | `basalt-stack/tools/rmf-generator/data/notional_system.yaml` | Ready |
| 20 RMF plan templates | `rmf-plan-templates/*.docx` | Ready (need re-tagging) |
| `__init__.py` stubs | `models/`, `loaders/`, `llm/`, `generators/` | Broken imports — fix when building |

## Related Documents

| Document | Relation | Update Needed? |
|----------|----------|---------------|
| `docs/brainstorms/2026-03-02-rmf-doc-automation-oss-reuse-brainstorm.md` | Full research details | No — this doc supersedes for quick reference |
| `docs/plans/rmf-generator-pivot-notes.md` | Implementation pause record | Yes — mark research complete |
| `docs/plans/basalt-development-roadmap.md` | Phased roadmap | Yes — add RMF as feature/capability |
| `docs/plans/basalt-system-description.md` | System overview | Yes — add RMF doc automation as capability |
| `docs/plans/basalt-compliance-matrix.md` | Basalt's own compliance | No — but eventually a test case for the tool |
| `CLAUDE.md` | Project instructions | Yes — add rmf-generator to overview |

## Sources

Engines: [docxtpl](https://github.com/elapouya/python-docx-template), [docxtpl docs](https://docxtpl.readthedocs.io/)
Structured output: [guidance-ai](https://github.com/guidance-ai/guidance), [instructor](https://github.com/jxnl/instructor), [Outlines](https://github.com/dottxt-ai/outlines), [vLLM structured outputs](https://docs.vllm.ai/en/latest/features/structured_outputs/), [comparison](https://simmering.dev/blog/structured_output/)
OSCAL: [compliance-trestle](https://github.com/oscal-compass/compliance-trestle), [oscal-pydantic](https://github.com/RS-Credentive/oscal-pydantic), [ssp-toolkit](https://github.com/CivicActions/ssp-toolkit), [awesome-oscal](https://github.com/oscal-club/awesome-oscal)
Patterns: [Sapienza multi-agent paper](https://arxiv.org/html/2402.14871v1), [Corelight styleguide](https://corelight.com/blog/microsoft-style-guide-llm), [multi_agent_document_generation](https://github.com/michelebri/multi_agent_document_generation)
Market: [Paramify](https://www.paramify.com/) ($120k+), [GovReady-Q](https://github.com/GovReady/govready-q)
