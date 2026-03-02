---
status: resolved
priority: p3
issue_id: "014"
tags: [code-review, simplification]
dependencies: ["006"]
---

# P3: Consider removing Technology Stack table from root CLAUDE.md

## Problem Statement

The Technology Stack table (lines 132-139) largely duplicates the Overview section and onyx/CLAUDE.md. Claude discovers tech stacks from package.json, pyproject.toml, etc.

## Proposed Solutions

Remove the table. The Overview section already names key technologies per subproject. Best addressed together with todo #006 (duplication cleanup).

- Effort: Small
- Source: Simplicity Reviewer agent

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
| 2026-03-02 | Resolved: Technology Stack table removed from root CLAUDE.md |
