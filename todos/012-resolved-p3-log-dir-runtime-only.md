---
status: resolved
priority: p3
issue_id: "012"
tags: [code-review, documentation]
dependencies: []
---

# P3: Note that backend/log/ directory is created at runtime

## Problem Statement

Both CLAUDE.md files reference `backend/log/<service_name>_debug.log` but this directory doesn't exist until services are running. Developers may think the path is wrong.

## Proposed Solutions

Add "(created at runtime)" to the log path notes in both files.

- Effort: Small
- Source: Pattern Recognition agent

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
| 2026-03-04 | Resolved: added "(created at runtime)" to onyx/CLAUDE.md log path; root CLAUDE.md reference already removed in A1 |
