---
status: pending
priority: p2
issue_id: "007"
tags: [code-review, documentation]
dependencies: []
---

# P2: Add root CLAUDE.md cross-reference to onyx/CLAUDE.md

## Problem Statement

`onyx/CLAUDE.md` never references the root CLAUDE.md. Someone reading only the Onyx file has no awareness of the vLLM/LiteLLM/Langfuse infrastructure, Docker networking, startup sequence, or air-gap deployment context.

## Findings

- Root CLAUDE.md correctly references onyx/CLAUDE.md (line 123)
- onyx/CLAUDE.md has no reciprocal reference
- Source: Pattern Recognition agent

## Proposed Solutions

### Option A: Add a brief header note (Recommended)
Add near the top of onyx/CLAUDE.md: "This file covers Onyx-specific guidance. For Basalt Stack architecture, Docker networking, and service startup, see the root `CLAUDE.md`."

- Effort: Small (one line)
- Risk: None

## Acceptance Criteria

- [ ] onyx/CLAUDE.md references root CLAUDE.md for infrastructure context

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
