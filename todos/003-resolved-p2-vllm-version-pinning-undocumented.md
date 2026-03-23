---
status: resolved
priority: p2
issue_id: "003"
category: todo
tags: [code-review, documentation, vllm, gotchas]
dependencies: []
related:
  - "[[vllm-gpt-oss-20b-version-requirements|vllm-version]]"
  - "[[basalt-development-roadmap|roadmap]]"
---

# P2: Document vLLM version pinning requirement

## Problem Statement

gpt-oss-20b requires vLLM v0.10.2+ for MoE architecture and MXFP4 quantization support. Using older versions (e.g., the originally specified v0.8.4) causes silent model load failure. This is documented in `docs/solutions/vllm-gpt-oss-20b-version-requirements.md` but not in CLAUDE.md.

## Findings

- `basalt-stack/inference/vllm/.env`: `VLLM_TAG=v0.10.2` (correct)
- Roadmap Phase 2 notes: documents the version change
- Solution doc: `docs/solutions/vllm-gpt-oss-20b-version-requirements.md`
- GPU memory configs: RTX 4000 ADA (20GB dev) vs RTX A6000 (48GB prod) have different optimal settings
- Source: Learnings Researcher agent

## Proposed Solutions

### Option A: Add version note to startup sequence + Key Notes (Recommended)
Expand the vLLM startup comment to mention v0.10.2+ requirement. Add a Key Notes bullet with GPU config guidance.

- Effort: Small
- Risk: None

### Option B: Add a dedicated vLLM Configuration section
More detailed section with version, GPU configs, and air-gap notes.

- Effort: Medium
- Risk: May be too verbose for root CLAUDE.md

## Acceptance Criteria

- [ ] vLLM v0.10.2+ requirement stated in CLAUDE.md
- [ ] Link to solution doc for detailed reasoning
- [ ] GPU memory configuration guidance for dev vs prod hardware

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
| 2026-03-02 | Resolved: vLLM v0.10.2+ requirement documented in both Startup Sequence and Gotchas section of root CLAUDE.md |
