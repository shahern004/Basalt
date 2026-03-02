---
status: resolved
priority: p3
issue_id: "008"
tags: [code-review, documentation]
dependencies: []
---

# P3: Add container count annotations to architecture diagram

## Problem Statement

Langfuse (6 containers), LiteLLM (3), and Onyx (9+) are shown as single boxes in the architecture diagram. Developers debugging issues may not realize the actual container count.

## Proposed Solutions

Add parenthetical counts to the port table or a note below the diagram. E.g., "Langfuse runs 6 containers internally (web, worker, PostgreSQL, Redis, ClickHouse, MinIO)."

- Effort: Small
- Source: Architecture Strategist agent

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
| 2026-03-02 | Resolved: Container counts now included in roadmap Running Infrastructure table |
