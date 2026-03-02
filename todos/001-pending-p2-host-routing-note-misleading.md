---
status: pending
priority: p2
issue_id: "001"
tags: [code-review, architecture, documentation]
dependencies: []
---

# P2: Clarify host.docker.internal networking note

## Problem Statement

The root CLAUDE.md line 124 says "Use `host.docker.internal` for inter-container communication" which is technically incorrect. `host.docker.internal` is container-to-**host** routing. Within a single compose stack, services use service names directly (e.g., `redis`, `postgres`).

This can mislead developers into using `host.docker.internal` for intra-stack communication when they should use Docker service names.

## Findings

- `litellm-config.yaml` line 5: `api_base: http://host.docker.internal:8001/v1` (cross-stack, correct)
- `litellm/.env` line 40: `LANGFUSE_HOST=http://host.docker.internal:3001` (cross-stack, correct)
- Within litellm compose: Redis and Postgres accessed by service name (intra-stack, correct)
- Source: Architecture Strategist agent

## Proposed Solutions

### Option A: Reword the note (Recommended)
Replace with: "**Host-Routed Networking**: Services in different compose stacks communicate via `host.docker.internal` (e.g., LiteLLM → vLLM at port 8001). Within a single compose stack, use service names directly."

- Effort: Small
- Risk: None
- Pros: Accurate, teaches the distinction

### Option B: Add a networking reference table
Create a table showing which connections use host routing vs service names.

- Effort: Medium
- Risk: May over-document for CLAUDE.md scope

## Acceptance Criteria

- [ ] Note distinguishes host-routed (cross-stack) from service-name (intra-stack) patterns
- [ ] No developer confusion about when to use which approach

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
