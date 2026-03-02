# Brainstorm: RMF Document Automation — OSS Reuse Strategy

**Date**: 2026-03-02
**Status**: Active research
**Demo deadline**: Thursday, March 5, 2026

---

## What We're Building

An MVP tool that takes existing `.docx` RMF plan templates (we have 20 control families) + organizational/system data → uses a self-hosted LLM to:
1. **Fill `[defined ...]` ODP parameter slots** with org-tailored values
2. **Synthesize implementation narrative paragraphs** where the LLM reasons about how a specific system meets a specific control
3. **Output a pixel-perfect filled `.docx`** — formatting identical to the input template

Plus a **demo PowerPoint** showing the workflow, value prop for air-gapped networks, and proof it's using a self-hosted LLM.

### LLM Scope (Constrained)
- **Deterministic**: Org name, system name, acronym, impact levels, dates, signatories, control text → straight replacement
- **LLM slot-fill**: `[defined frequency]` → "annually and upon significant system changes"
- **LLM narrative**: Entire paragraphs describing how the system implements a control, synthesizing org risk posture + system architecture + control requirements

---

## OSS Landscape Research

### Tier 1: Document Template Engines (DOCX manipulation)

| Tool | Stars | What it does | Fits? | Notes |
|------|-------|-------------|-------|-------|
| **[docxtpl](https://github.com/elapouya/python-docx-template)** | 900+ | Jinja2 templating inside .docx. Preserves formatting. Handles cross-run placeholders. | **YES** | Actively maintained, PyPI. Proven for compliance reports. Handles loops, conditionals, tables. Requires re-tagging templates to Jinja2 syntax. |
| **[python-docx](https://python-docx.readthedocs.io/)** | 4k+ | Low-level .docx read/write. No templating. | Partial | docxtpl wraps this already. Would need custom cross-run code. |
| **[docx-mailmerge2](https://pypi.org/project/docx-mailmerge2/)** | — | Mail merge fields in .docx. | Maybe | Simpler than docxtpl. Uses Word's native merge fields instead of Jinja2. No re-tagging needed if templates use merge fields. Less flexible (no conditionals/loops). |
| **Documentero** | — | Cloud SaaS template engine. | **NO** | Cloud-only. Not air-gap compatible. Not open source. |

**Decision point**: `docxtpl` is the strongest candidate, BUT requires templates to use `{{ variable }}` Jinja2 syntax. Two paths:
- **A)** Pre-process our templates: convert `{Organization}` → `{{ organization }}` and `[defined frequency]` → `{{ odp_defined_frequency }}` once, save as Jinja2 templates
- **B)** Write raw python-docx replacement code that handles our existing placeholder syntax directly

### Tier 2: Structured LLM Output (Constrained Generation)

| Tool | Stars | What it does | Fits? | Notes |
|------|-------|-------------|-------|-------|
| **[guidance-ai](https://github.com/guidance-ai/guidance)** | **21.3k** | Microsoft's constrained LLM generation. Regex, CFG, Pydantic schema enforcement at token level. | **YES — strong fit** | Works with vLLM natively (merged in v0.8.2). Token-level constraining = guaranteed valid output structure. Supports Pydantic models. MIT license. Steeper learning curve than instructor. |
| **[instructor](https://github.com/jxnl/instructor)** | **12.5k** | Structured JSON from LLMs via Pydantic. Prompt-level (function calling), not token-level. Auto-retry on validation failure. | **YES — simpler** | 3M+ monthly PyPI downloads. Works with any OpenAI-compatible API (LiteLLM). Easier API than guidance. Less efficient (prompt-level vs token-level). |
| **[Outlines](https://github.com/dottxt-ai/outlines)** | ~9k | Constrained token sampling. Pydantic → CFG → constrained decoding. | **YES** | [Best recommendation for local LLMs](https://simmering.dev/blog/structured_output/) per independent comparison. Easier than guidance, supports Pydantic directly. Works with vLLM. |
| **[vLLM native structured output](https://docs.vllm.ai/en/latest/features/structured_outputs/)** | — | Built-in `guided_json` / `response_format` via OpenAI API. Uses xgrammar or guidance backend. | **YES — zero extra deps** | Pass JSON schema in `response_format` param via standard OpenAI API. No extra library needed. Already in our stack. |
| **[LMQL](https://lmql.ai/)** | ~3k | Query language for LLMs. | Overkill | Academic feel. More complexity than we need. |

**Key comparison** ([source](https://simmering.dev/blog/structured_output/)):
- **Token-level constrained** (guidance, outlines, vLLM native): Most efficient, guaranteed valid output, requires local model control ✓ (we have vLLM)
- **Prompt-level / function calling** (instructor): Simpler API, works with any endpoint, but less efficient and not guaranteed
- **Recommendation**: For local vLLM, constrained generation wins. vLLM's native `response_format` may be sufficient with zero extra dependencies.

### Tier 3: OSCAL / Compliance-Specific Tools

| Tool | Stars | What it does | Fits? | Notes |
|------|-------|-------------|-------|-------|
| **[compliance-trestle](https://github.com/oscal-compass/compliance-trestle)** | 237 | OSCAL compliance-as-code. Markdown → OSCAL JSON → pandoc → docx. | **Wrong direction for MVP** | Great for OSCAL-native SSP authoring. But: pandoc ≠ pixel-perfect, requires full OSCAL workspace. **Phase 2+ candidate.** |
| **[CivicActions ssp-toolkit](https://github.com/CivicActions/ssp-toolkit)** | 48 | Python/Jinja2: YAML → markdown → pandoc → docx. | **Architecture reference** | Active (v1.0.0 Apr 2025). Rev 4 only. Good pattern: YAML input, Jinja2 templates. But pandoc output. |
| **[GoComply/fedramp](https://github.com/GoComply/fedramp)** | 44 | Go: OSCAL SSP → FedRAMP docx templates. | **Incomplete** | Explicitly "work in progress" with blank fields. Go, not Python. |
| **[oscal-pydantic](https://github.com/RS-Credentive/oscal-pydantic)** | 22 | Pydantic models auto-generated from OSCAL JSON schema. | **Useful utility** | CC0 license. Could replace our hand-written OSCAL models. Last release Jul 2023, v2 branch exists. Lightweight — just datamodels. |
| **[GovReady-Q](https://github.com/GovReady/govready-q)** | ~100 | Web GRC: questionnaire → SSP. OSCAL import/export. | **No for MVP** | Full Django app. Massive scope. |
| **GSA tools** (oscal-ssp-to-word, oscal-gen-tool) | <20 | C# OSCAL→Word converters. | **No** | Dated (2020), C#/Windows, dead projects. |
| **Paramify** | — | Commercial: OSCAL SSP automation, one-click docx. | **No (SaaS)** | Validates market — they charge $120k+. |
| **[NIST OLIR](https://csrc.nist.gov/projects/olir)** | — | Cross-framework control mapping (800-53 ↔ CSF ↔ CIS). | **Post-MVP** | Web-based, no API yet. Future multi-framework support. |

### Tier 4: LLM + Document Generation Patterns

| Source | What it offers | Key Takeaway |
|--------|---------------|-------------|
| **[Multi-agent doc generation](https://github.com/michelebri/multi_agent_document_generation)** (Sapienza) | 3-agent pipeline: semantics → retrieval → generation. | **Accumulated prompt** pattern: context grows richer per section, reducing hallucination. Process sections sequentially. |
| **[Sapienza paper](https://arxiv.org/html/2402.14871v1)** | Academic research on above. | "Give just the action to do" vs "respond with content" dramatically reduces hallucination. Separate semantic extraction from content generation. |
| **[Corelight llm-styleguide-helper](https://corelight.com/blog/microsoft-style-guide-llm)** | Vale linting + LLM correction pipeline for style compliance. | **Iterative refinement**: detect violations with deterministic tool → LLM fixes → re-check → repeat until clean. Analogous to: parse template slots deterministically → LLM fills → validate. |
| **[HuggingFace discussion](https://discuss.huggingface.co/t/custom-llm-for-document-template-and-its-html-form-generation-from-big-documents-40-pages/78312)** | User doing docxtpl + LLM at scale. | Confirms "using docxtpl to fill out manually created word jinja templates works effectively." |

---

## Key Findings

### 1. OSCAL: Data Source, Not Document Generator
OSCAL is mature for **representing** compliance data in machine-readable format. It is NOT a document generation tool. Every OSCAL-to-docx pipeline (trestle, GoComply, GSA) uses a separate rendering step and **none produce pixel-perfect template matches**.

**Our approach**: Use OSCAL catalog as a **data source** for control definitions and ODPs. Don't force our template-fill workflow into an OSCAL SSP authoring pipeline. Square peg, round hole for MVP.

### 2. "LLM Fills Compliance Templates" = Market Gap
No turnkey OSS solution exists. Paramify charges $120k+ for essentially this (as SaaS). The open-source tools either:
- Generate docs from scratch (trestle, ssp-toolkit) — no template fidelity
- Convert between formats (GoComply, GSA) — incomplete, dated
- Do template-fill without LLM intelligence (docxtpl) — no compliance knowledge

**Our value-add**: The combination is novel.

### 3. docxtpl Is the Right Document Layer
- Proven (900+ stars, actively maintained, 3M+ docxtpl downloads)
- Handles cross-run placeholder issues natively
- Preserves all formatting, styles, fonts, tables
- Jinja2 supports conditionals and loops
- One-time cost: re-tag templates to Jinja2 syntax

### 4. vLLM Native Structured Output May Be Enough
vLLM v0.8.2+ has built-in `response_format` support via OpenAI-compatible API. Pass a JSON schema → get guaranteed-valid JSON back. This might eliminate the need for instructor, outlines, or guidance as separate dependencies. **Test this first before adding libraries.**

### 5. guidance-ai Is the Premium Option
If vLLM native structured output isn't sufficient (e.g., need more complex grammars, interleaved generation, or template-style prompts), guidance-ai (21.3k stars, Microsoft-backed, MIT) is the most powerful constrained generation library. Already integrated into vLLM as a backend.

### 6. Iterative Refinement Pattern (Corelight)
The detect → fix → re-check loop from the style guide blog applies directly:
1. Parse template to extract all placeholder slots (deterministic)
2. LLM generates values for each slot (constrained output)
3. Validate output against schema (Pydantic)
4. If invalid → retry with error context
5. Fill template (docxtpl)

---

## Recommended Stack (Updated)

| Layer | Primary Choice | Fallback | Role |
|-------|---------------|----------|------|
| Template engine | **docxtpl** | raw python-docx | Fill .docx preserving formatting |
| Structured LLM output | **vLLM native `response_format`** | instructor → guidance-ai | Constrain LLM output to Pydantic schemas |
| OSCAL data | **oscal-pydantic** + NIST catalog JSON | Hand-written models (already built) | Typed control definitions |
| System context | **YAML** (Pydantic validated) | — | Org data, system description, risk posture |
| Prompt patterns | **Corelight iterative** + **Sapienza accumulated** | — | Section-by-section, detect-fill-validate |

### Pipeline Flow (Updated)
```
notional_system.yaml ──► Pydantic SystemDescription
                              │
OSCAL catalog JSON ──► oscal-pydantic control objects
  (or hand-parsed)            │
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

---

## Open Questions

1. **Template re-tagging strategy**: Script the `{placeholder}` → `{{ jinja2 }}` conversion, or manual for MP only, script later?
2. **Narrative scope for demo**: How many sections in MP need full narrative paragraphs vs. just ODP slot-fills?
3. **Notional input docs**: What fictional supporting documents to create? (org risk assessment, architecture description, security policy excerpts)
4. **vLLM readiness**: Model weights not downloaded. Fallback plan if inference isn't ready by Wednesday?
5. **vLLM structured output testing**: Does `response_format` with JSON schema work reliably through LiteLLM proxy, or do we need to call vLLM directly?

---

## What NOT to Build (YAGNI)

- Full OSCAL SSP authoring pipeline (compliance-trestle territory)
- OSCAL JSON/XML export
- Multi-agent orchestration framework
- Web UI
- Custom XML run manipulation code (docxtpl handles this)
- Support for all 20 control families (demo needs 1: MP)
- Custom constrained generation engine (vLLM has it built in)

---

## Sources

### Document Template Engines
- [docxtpl (python-docx-template)](https://github.com/elapouya/python-docx-template) — 900+ stars, Jinja2-in-docx
- [docxtpl docs](https://docxtpl.readthedocs.io/) — Technical reference
- [docx-mailmerge2](https://pypi.org/project/docx-mailmerge2/) — Alternative merge-field approach

### Structured LLM Output
- [guidance-ai](https://github.com/guidance-ai/guidance) — 21.3k stars, Microsoft, token-level constraining
- [instructor](https://github.com/jxnl/instructor) — 12.5k stars, Pydantic structured output
- [Outlines](https://github.com/dottxt-ai/outlines) — Constrained token sampling
- [vLLM structured outputs](https://docs.vllm.ai/en/latest/features/structured_outputs/) — Native support
- [Structured output comparison](https://simmering.dev/blog/structured_output/) — Independent evaluation

### OSCAL / Compliance Tools
- [compliance-trestle](https://github.com/oscal-compass/compliance-trestle) — 237 stars, IBM/NIST OSCAL tooling
- [compliance-trestle SSP demo](https://github.com/oscal-compass/compliance-trestle-ssp-demo)
- [CivicActions ssp-toolkit](https://github.com/CivicActions/ssp-toolkit) — 48 stars, Python/Jinja2
- [oscal-pydantic](https://github.com/RS-Credentive/oscal-pydantic) — 22 stars, OSCAL Pydantic models
- [GoComply/fedramp](https://github.com/GoComply/fedramp) — 44 stars, Go, OSCAL→docx (WIP)
- [GSA oscal-ssp-to-word](https://github.com/GSA/oscal-ssp-to-word) — C#, dated
- [GSA oscal-gen-tool](https://github.com/GSA/oscal-gen-tool) — C#, dated
- [GovReady-Q](https://github.com/GovReady/govready-q) — Web GRC
- [awesome-oscal](https://github.com/oscal-club/awesome-oscal) — Tool directory
- [NIST OLIR](https://csrc.nist.gov/projects/olir) — Cross-framework mapping
- [Paramify](https://www.paramify.com/) — Commercial ($120k+), validates market

### LLM + Document Patterns
- [Multi-agent doc generation](https://github.com/michelebri/multi_agent_document_generation) — 28 stars, Sapienza
- [Sapienza paper](https://arxiv.org/html/2402.14871v1) — Accumulated prompt patterns
- [Corelight llm-styleguide-helper](https://corelight.com/blog/microsoft-style-guide-llm) — Iterative detect-fix-validate
- [HuggingFace discussion](https://discuss.huggingface.co/t/custom-llm-for-document-template-and-its-html-form-generation-from-big-documents-40-pages/78312) — Validates docxtpl + LLM approach

### Other References
- [Documentero](https://docs.documentero.com/documentation/) — Cloud SaaS (not suitable)
- [YData SDK](https://docs.sdk.ydata.ai/latest/) — Synthetic data (not relevant)
