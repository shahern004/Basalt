---
status: pending
priority: p3
issue_id: "010"
tags: [code-review, documentation, onyx]
dependencies: []
---

# P3: Fix integration test example path in onyx/CLAUDE.md

## Problem Statement

onyx/CLAUDE.md line 253 references `backend/tests/integration/dev_apis/test_simple_chat_api.py` but the actual path is `backend/tests/integration/tests/dev_apis/test_simple_chat_api.py` (missing `tests/` subdirectory).

## Proposed Solutions

Update the path to include the `tests/` subdirectory.

- Effort: Small (one-line edit)
- Source: Pattern Recognition agent

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
