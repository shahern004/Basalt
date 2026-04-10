---
status: open
priority: p3
issue_id: "023"
category: todo
tags: [docs, deployment-guide, refresh, laci-alignment]
dependencies: []
related:
  - "[[deployment-guide-dev|deployment-guide-dev]]"
  - "[[basalt-development-roadmap|roadmap]]"
---

# Deployment Guide Holistic Refresh

## Problem Statement

`docs/guides/deployment-guide-dev.md` has accumulated drift since multiple structural and feature changes landed: the LACI v1.1 alignment restructure (2026-03-30) flattened the repo layout, the Authentik SSO integration replaced the nginx portal across all 3 phases, vLLM/LiteLLM/Langfuse paths and ports were validated end-to-end (C1, 2026-03-24), and various small gotchas surfaced during real deployments. The guide needs a single careful sweep rather than piecemeal edits to catch all the cross-references, stale paths, and missing platform notes at once.

A concrete recent example: section 5 only documents `bash scripts/gen-cert.sh`, which fails on Windows hosts where `bash` resolves to a non-GNU shell (BusyBox/dash) that doesn't support `set -o pipefail`. A PowerShell equivalent (`scripts/gen-cert.ps1`) now exists but is undocumented in the guide.

## Location

- **Primary**: `docs/guides/deployment-guide-dev.md`
- **Related guides** (check for cross-reference drift): `docs/guides/meeting-prep-director-deployment.md`
- **Source-of-truth references**: `CLAUDE.md`, `docs/basalt-system-design.md`, `docs/plans/basalt-development-roadmap.md`

## Checklist

- [ ] Audit all file paths in the guide against the post-LACI layout (`inference/`, `web/`, `tools/`, `builds/`)
- [ ] Verify every `cd` command lands in a directory that exists in the current tree
- [ ] Update section 5 (cert generation) to document both `gen-cert.sh` (WSL/Linux) and `gen-cert.ps1` (Windows native) with a "pick one" note
- [ ] Replace all references to the deprecated nginx portal with Authentik SSO equivalents
- [ ] Verify service URLs and ports against the current port map (vLLM 8001, LiteLLM 8000, Langfuse 3001, Onyx 3000, Open-WebUI 3002, Authentik 443)
- [ ] Add/refresh the `*.basalt.local` hosts file step (now required for Authentik subdomain routing)
- [ ] Verify the OIDC/SSO setup steps reflect the final Phase 3 configuration (Onyx `AUTH_TYPE=oidc`, internal HTTP discovery, etc.)
- [ ] Cross-check gotchas against `CLAUDE.md` § Gotchas — surface any that affect first-time deployment
- [ ] Confirm air-gap compliance notes are still accurate (no `pip install`, no `docker pull` at deploy time)
- [ ] Regenerate `docs/guides/deployment-guide-dev.pdf` from the refreshed markdown
- [ ] Walk the guide end-to-end on a clean checkout (or at least mentally) to catch ordering bugs

## Acceptance Criteria

- Every command in the guide runs successfully on a fresh Windows 11 + WSL2 + Docker Desktop host with no edits
- No stale path references to pre-LACI layout (`basalt-stack/...`, vendored `open-webui/`, vendored `onyx/`)
- No references to the archived nginx portal except where explicitly noting it was replaced
- Both bash and PowerShell paths documented for any script that has both
- PDF regenerated and matches the markdown source
- A reviewer following the guide cold can stand up the full stack without consulting CLAUDE.md or other docs for missing steps

## Pre-Found Drift Inventory

Recorded during the 2026-04-07 chapter-5 surgical patch so the holistic sweep doesn't have to rediscover these. Line numbers are post-chapter-5-patch and will drift further as edits land — use as a starting map, not a literal index.

**Stale `basalt-stack/` path prefix (LACI restructure 2026-03-30) — 35 occurrences outside chapter 5:**
- Section 1 (vLLM env): lines 169, 189
- Section 2 (vLLM start/verify): lines 212, 314
- Section 3 (Langfuse): line 249
- Section 4 (LiteLLM): line 292
- Section 6 (Open-WebUI): lines 501, 566
- Section 8 (smoke tests): lines 726-730
- Appendix B (startup quick-ref): lines 876-880
- Appendix B (shutdown quick-ref): lines 888-892
- Appendix B (compose dirs table): lines 899-903
- Appendix B (secret locations table): lines 911-917

Mechanical fix: strip the `basalt-stack/` prefix everywhere. None of these reference the post-LACI flat layout correctly.

**Other deferred items (not yet line-numbered):**
- Section 6 likely needs a Phase 2 security model summary (S1 random-password fix, S2 JWT secret fail-fast, S3 shared-secret HMAC validation, JWT_EXPIRES_IN config) — currently uncovered
- Section 7 OIDC config should reference the HTTP-internal-discovery decision (debt for Phase 7) so future readers don't "fix" it back to HTTPS
- Appendix A troubleshooting probably missing the Windows `bash`-not-GNU `pipefail` pitfall — generalize as "shell script failures on Windows hosts → use PS equivalents where available"
- Container count annotations in Appendix B (vLLM=1, Langfuse=6, etc.) should be re-verified against current compose files

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-07 | Created — triggered by section 5 `gen-cert.sh` failure on Windows; PowerShell port added but guide not yet updated | Piecemeal edits to a stale guide compound drift; one holistic sweep is cheaper than N small ones |
| 2026-04-07 | Surgical patch applied to chapter 5 only (path drift, PS script reference, brand-title hedging, cert SAN verification step) + Section 0 `ls` path fix (same-class bug at upstream prereq check). Pre-found drift inventory recorded for the rest of the guide. | Targeted fixes are OK when narrowly scoped; the discipline is recording the *rest* of the drift so the sweep has a starting point |
