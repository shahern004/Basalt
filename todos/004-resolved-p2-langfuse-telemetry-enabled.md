---
status: resolved
priority: p2
issue_id: "004"
category: todo
tags: [code-review, security, air-gap, langfuse]
dependencies: []
related:
  - "[[deployment-guide-dev|deployment-guide]]"
  - "[[basalt-development-roadmap|roadmap]]"
---

# P2: Disable Langfuse telemetry for air-gap compliance

## Problem Statement

Langfuse compose has `TELEMETRY_ENABLED: true` (default). For an air-gapped deployment, outbound telemetry attempts will cause timeouts or silent failures. No telemetry management is documented in CLAUDE.md.

## Findings

- Langfuse compose: `TELEMETRY_ENABLED: true` (line 46)
- vLLM: `VLLM_NO_USAGE_STATS=1` (correctly disabled)
- Open-WebUI: `SCARF_NO_ANALYTICS=true`, `DO_NOT_TRACK=true` (correctly disabled)
- LiteLLM: No telemetry setting found
- Onyx: No telemetry setting found
- Source: Architecture Strategist agent

## Proposed Solutions

### Option A: Fix Langfuse .env + document telemetry status (Recommended)
Set `TELEMETRY_ENABLED=false` in Langfuse `.env`. Add a note in CLAUDE.md listing telemetry status per service.

- Effort: Small
- Risk: None
- Pros: Immediate fix + documentation

### Option B: Comprehensive telemetry audit
Audit all services for phone-home behavior and document/disable each.

- Effort: Medium
- Risk: Some services may have undocumented telemetry

## Acceptance Criteria

- [ ] `TELEMETRY_ENABLED=false` in Langfuse compose/env
- [ ] CLAUDE.md mentions telemetry management for air-gap context
- [ ] LiteLLM and Onyx telemetry settings investigated

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
| 2026-03-02 | Resolved: Langfuse telemetry gotcha added to CLAUDE.md. Note: the actual .env fix (TELEMETRY_ENABLED=false) is a separate config change |
