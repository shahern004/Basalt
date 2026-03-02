---
status: pending
priority: p2
issue_id: "006"
tags: [code-review, documentation, simplification]
dependencies: []
---

# P2: Reduce duplication between root and onyx CLAUDE.md

## Problem Statement

6 items in root CLAUDE.md's "Key Notes" are duplicated from `onyx/CLAUDE.md`. This creates maintenance burden (changes must be made in two places) and wastes context window tokens when both files are loaded.

## Findings

Duplicated items (root → onyx):

| Topic | Root Line | Onyx Line |
|-------|-----------|-----------|
| API routing rule | 125 | 16 |
| DB operations restriction | 126 | 17 |
| Postgres access command | 127 | 14-15 |
| Log file location | 128 | 279 |
| Test login credentials | 129 | 11 |
| Strict typing requirement | 130 | 152 |

Additionally, Onyx backend/frontend commands (root lines 83-100) duplicate onyx/CLAUDE.md.
Technology Stack table (root lines 132-139) also largely duplicates onyx/CLAUDE.md.

- Source: Pattern Recognition + Simplicity agents

## Proposed Solutions

### Option A: Trim root to navigation hub (Recommended)
Keep only 2 unique Key Notes bullets (Onyx pointer, Docker-to-Host). Remove duplicated Onyx commands and tech stack table. Root becomes an infrastructure reference + navigation hub.

- Effort: Medium
- Risk: Low — onyx/CLAUDE.md has the authoritative versions

### Option B: Keep duplicates but mark source of truth
Add "(see onyx/CLAUDE.md)" after each duplicated item.

- Effort: Small
- Risk: Still has maintenance burden

## Acceptance Criteria

- [ ] No content duplicated between root and onyx CLAUDE.md
- [ ] Root CLAUDE.md clearly points to onyx/CLAUDE.md for Onyx-specific guidance
- [ ] All unique infrastructure info preserved in root

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
