---
status: superseded
priority: p2
issue_id: "022"
category: todo
tags: [portal, deployment, verification]
dependencies: []
superseded_by: "Authentik SSO portal (feat/authentik-sso-integration)"
related:
  - "[[2026-03-17-001-feat-authentik-sso-portal-integration-plan|authentik-plan]]"
  - "[[2026-03-17-authentik-sso-portal-brainstorm|authentik-brainstorm]]"
---

# Portal Deployment Verification

> **SUPERSEDED**: The nginx portal has been replaced by Authentik SSO (see `docs/plans/2026-03-17-001-feat-authentik-sso-portal-integration-plan.md`). Portal files archived to `basalt-stack/web/portal-archived/`.

## Problem Statement

The Basalt Portal (landing page + health dashboard) has been implemented but not yet deployed or verified. The portal needs cert generation, container startup, and end-to-end validation of all health proxy routes before it can be considered production-ready.

## Location

- **Compose**: `basalt-stack/web/portal/docker-compose.yaml`
- **Config**: `basalt-stack/web/portal/nginx/portal.conf`
- **UI**: `basalt-stack/web/portal/html/index.html`
- **Cert script**: `basalt-stack/web/portal/scripts/gen-cert.sh`

## Checklist

- [ ] Run `bash basalt-stack/web/portal/scripts/gen-cert.sh` — verify `certs/portal.{crt,key}` created
- [ ] Copy `.env.example` to `.env`
- [ ] Run `docker compose up -d` — verify container starts healthy
- [ ] `curl -k https://localhost/` — returns portal HTML
- [ ] `curl -v http://localhost/` — returns `301` redirect to HTTPS
- [ ] `curl -k https://localhost/health/litellm` — returns health JSON or `503 {"status":"down"}`
- [ ] `curl -k https://localhost/health/vllm` — returns health JSON or `503 {"status":"down"}`
- [ ] `curl -k https://localhost/health/langfuse` — returns health JSON or `503 {"status":"down"}`
- [ ] `curl -k https://localhost/health/onyx` — returns response or `503 {"status":"down"}`
- [ ] `curl -k https://localhost/health/open-webui` — returns response or `503 {"status":"down"}`
- [ ] Open `https://localhost` in browser — accept self-signed cert, verify cards render
- [ ] Confirm health dots update after ~15s (amber → green/red depending on running services)
- [ ] Verify no external network requests (DevTools → Network tab, air-gap compliant)

## Acceptance Criteria

- Portal container starts and passes Docker health check
- HTTP→HTTPS redirect works
- All 5 health proxy routes return valid responses (JSON health or 503 fallback)
- Browser renders dark-themed dashboard with service cards and live status dots
- No outbound network requests (fonts, CDN, telemetry)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-04 | Created — portal implementation complete, needs deployment test | |
