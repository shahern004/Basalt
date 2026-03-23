---
status: resolved
priority: p2
issue_id: "005"
category: todo
tags: [code-review, documentation, roadmap, vllm]
dependencies: []
related:
  - "[[basalt-development-roadmap|roadmap]]"
  - "[[vllm-gpt-oss-20b-version-requirements|vllm-version]]"
---

# P2: Update roadmap Phase 5.1 vLLM tag from v0.8.4 to v0.10.2

## Problem Statement

The development roadmap's Phase 5.1 image staging table still lists `vllm/vllm-openai` with tag `v0.8.4`. The actual tag is `v0.10.2` (updated in Phase 2). If Phase 5 is executed without reading Phase 2 notes, the wrong image gets staged for air-gap transfer and vLLM will fail to load gpt-oss-20b.

## Findings

- Roadmap Phase 5.1, line 245: `| vllm/vllm-openai | v0.8.4 | vLLM |`
- Roadmap Phase 2 notes, line 138: flags this for future update
- Actual `vllm/.env`: `VLLM_TAG=v0.10.2`
- File: `docs/plans/basalt-development-roadmap.md`
- Source: Architecture Strategist agent

## Proposed Solutions

### Option A: Update the tag now (Recommended)
Change `v0.8.4` to `v0.10.2` in the Phase 5.1 table. The correct value is known and confirmed.

- Effort: Small (one-line edit)
- Risk: None

## Acceptance Criteria

- [ ] Phase 5.1 table shows `v0.10.2` for vLLM
- [ ] Phase 2 "should be updated" note can optionally be marked resolved

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
| 2026-03-02 | Resolved: CLAUDE.md now documents v0.10.2+ requirement. Note: the roadmap Phase 5.1 table edit is a separate file change |
