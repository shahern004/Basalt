---
status: resolved
priority: p3
issue_id: "015"
tags: [code-review, simplification, onyx]
dependencies: []
---

# P3: Remove generic advice sections from onyx/CLAUDE.md

## Problem Statement

onyx/CLAUDE.md lines 283-305 contain "Security Considerations", "AI/LLM Integration", and "UI/UX Patterns" sections. These are generic best practices (e.g., "Never commit API keys", "Use parameterized queries") that Claude already knows. They add ~23 lines of low-value content.

## Proposed Solutions

Remove all three sections. They don't contain project-specific information.

- Effort: Small
- Risk: Low — this is an upstream file from the Onyx project; changes may be overwritten on update
- Source: Simplicity Reviewer agent

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
| 2026-03-02 | Resolved: onyx/CLAUDE.md replaced with deploy-only stub; all generic sections removed |
