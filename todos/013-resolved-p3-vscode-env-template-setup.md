---
status: resolved
priority: p3
issue_id: "013"
tags: [code-review, documentation, onyx]
dependencies: []
---

# P3: Document .vscode/.env setup from template

## Problem Statement

onyx/CLAUDE.md lines 219, 238 reference `python -m dotenv -f .vscode/.env run -- pytest ...` but `.vscode/.env` doesn't exist. Only `env_template.txt` exists. Developers need to copy the template first.

## Proposed Solutions

Add note: "Copy `.vscode/env_template.txt` to `.vscode/.env` and fill in values before running tests."

- Effort: Small
- Source: Pattern Recognition agent

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
| 2026-03-04 | Resolved: content already removed in A1 cleanup (fca8c94) |
