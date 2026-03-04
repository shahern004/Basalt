---
status: resolved
priority: p3
issue_id: "011"
tags: [code-review, documentation, onyx, celery]
dependencies: []
---

# P3: Update stale celery_app.py reference in onyx/CLAUDE.md

## Problem Statement

onyx/CLAUDE.md line 30 references `celery_app.py` as the Primary Worker file. The actual files are now `apps/primary.py`, `apps/light.py`, etc. under `backend/onyx/background/celery/`.

## Proposed Solutions

Update line 30 to reference `apps/primary.py`.

- Effort: Small (one-line edit)
- Source: Pattern Recognition agent

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
| 2026-03-04 | Resolved: content already removed in A1 cleanup (fca8c94) |
