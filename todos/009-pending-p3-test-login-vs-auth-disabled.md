---
status: pending
priority: p3
issue_id: "009"
tags: [code-review, documentation, onyx]
dependencies: []
---

# P3: Clarify test login note vs AUTH_TYPE=disabled

## Problem Statement

Root CLAUDE.md line 129 says "Playwright tests use `a@test.com` / `a`" but Onyx `.env` has `AUTH_TYPE=disabled`, meaning there is no login screen. The note is inherited from upstream Onyx and applies only when auth is enabled.

## Proposed Solutions

Add "(when `AUTH_TYPE=basic` is enabled)" after the test login note, or move it to onyx/CLAUDE.md only.

- Effort: Small
- Source: Architecture Strategist agent

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
