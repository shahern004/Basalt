# RMF Generator — Pivot Notes (2026-03-02)

## Status: RESEARCH COMPLETE → Resuming with OSS Stack

Research phase complete (2026-03-02). Stack selected: **docxtpl + vLLM native
structured output + OSCAL catalog + YAML system context**.

See `docs/solutions/research-decisions/rmf-doc-automation-stack-selection.md`
for the full decision record, implementation order, and risk mitigations.

## What Exists (built so far)

```
basalt-stack/tools/rmf-generator/
├── requirements.txt              ✅ Created
├── models/
│   ├── __init__.py               ✅ Created
│   ├── system.py                 ✅ Pydantic models for org/system context
│   └── control.py                ✅ Pydantic models for ODP values + source tracking
├── loaders/
│   └── __init__.py               ✅ Created (loader not built yet)
├── llm/
│   └── __init__.py               ✅ Created (synthesizer not built yet)
├── generators/
│   └── __init__.py               ✅ Created (generators not built yet)
├── data/
│   ├── nist-800-53-catalog.json  ✅ Downloaded (~10MB, full NIST OSCAL Rev5 catalog)
│   └── notional_system.yaml      ✅ Created (MERIDIAN fictional federal system)
├── templates/                    ❌ Empty
└── output/                       ❌ Empty
```

## What We Learned from Template Analysis

### Source templates: `rmf-plan-templates/` (20 .docx files, all control families)
- Recommended demo control: **MP — Media Protection Plan**

### Placeholder types found in MP template:
- **10 curly-brace** `{...}` — deterministic org data (name, acronym, impact levels, signatories)
- **22 bracket** `[defined ...]` — Organization-Defined Parameters needing tailored values
- **25 of 30** bracket tokens fit in single Word XML runs (easy replacement)
- **5 of 30** are split across runs (need run-reconstruction for pixel-perfect replacement)

### Key design principle confirmed:
> Templates define ALL structure. LLM only fills `[defined ...]` ODP values.
> Everything else (formatting, control text, tables) is deterministic.

## Research Results (2026-03-02)

All questions answered. No turnkey OSS exists for "LLM fills compliance templates."
Selected stack maximizes reuse of battle-tested components:
- **docxtpl** (900+ stars) — template engine, handles cross-run natively ✅
- **vLLM native `response_format`** — structured output, zero extra deps ✅
- **OSCAL catalog** — data source for control definitions (NOT doc generation) ✅
- **oscal-pydantic** — typed Python models from OSCAL schema (evaluate) ✅
- compliance-trestle, GovReady-Q, GoComply — evaluated and rejected for MVP

## Infrastructure Status (unchanged)

- LiteLLM: ✅ running on :8000
- Langfuse: ✅ running on :3001
- vLLM image: ✅ pulled (34.2GB), container NOT started (model weights not downloaded)
- LITELLM_MASTER_KEY: `sk-120fb1a...` (in litellm/.env)

## Demo Deadline

**Thursday, March 5** — mixed federal audience.
Fallback: use Claude-generated sample output if vLLM/gpt-oss-20b isn't ready.
