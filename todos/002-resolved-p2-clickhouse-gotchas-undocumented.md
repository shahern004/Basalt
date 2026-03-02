---
status: resolved
priority: p2
issue_id: "002"
tags: [code-review, documentation, langfuse, gotchas]
dependencies: []
---

# P2: Surface ClickHouse/Langfuse gotchas in CLAUDE.md

## Problem Statement

Two critical operational issues were fixed and documented in `docs/solutions/clickhouse-alpine-healthcheck-fix.md` but are not mentioned in the root CLAUDE.md. New developers hitting these issues will waste significant debugging time without the gotcha warnings.

## Findings

**Issue 1 - Alpine IPv6 resolution**: ClickHouse health check used `localhost`, which Alpine resolves to `::1` (IPv6). IPv6 is disabled in Docker containers, causing health checks to fail indefinitely. Fix: use `127.0.0.1` explicitly.

**Issue 2 - Dual-start race condition**: Alpine ClickHouse entrypoint starts a temporary server for provisioning, then starts the main server. On fast systems (NVMe), the port is still held. Fix: provision via XML config file instead of env vars.

- Source: Learnings Researcher agent
- Solution doc: `docs/solutions/clickhouse-alpine-healthcheck-fix.md`

## Proposed Solutions

### Option A: Add Gotchas section to CLAUDE.md (Recommended)
Add a "Gotchas" section after Key Notes with brief descriptions and links to the solution docs.

- Effort: Small
- Risk: None
- Pros: Prevents repeat debugging; links to details

### Option B: Reference solutions directory in Key Notes
Add a single bullet: "See `docs/solutions/` for known issues and fixes."

- Effort: Small
- Risk: May be too vague; developer won't know what to look for
- Pros: Minimal CLAUDE.md growth

## Acceptance Criteria

- [ ] Alpine IPv6 health check gotcha mentioned in CLAUDE.md
- [ ] ClickHouse dual-start race condition mentioned
- [ ] Link to solution doc for full details

## Work Log

| Date | Action |
|------|--------|
| 2026-03-02 | Created from code review finding |
| 2026-03-02 | Resolved: Added Gotchas section in root CLAUDE.md with ClickHouse Alpine IPv6 entry and link to solution doc |
