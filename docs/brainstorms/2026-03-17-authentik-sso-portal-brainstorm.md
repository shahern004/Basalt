---
title: "Authentik SSO Portal Integration"
date: 2026-03-17
status: active
category: brainstorm
tags:
  - authentik
  - sso
  - oidc
  - portal
  - open-webui
  - onyx
  - security
aliases:
  - authentik-brainstorm
  - sso-brainstorm
related:
  - "[[2026-03-17-001-feat-authentik-sso-portal-integration-plan|authentik-plan]]"
  - "[[authentik-sso-integration-log|authentik-log]]"
  - "[[basalt-development-roadmap|roadmap]]"
---

# Authentik SSO Portal Integration — Brainstorm

**Date:** 2026-03-17
**Status:** Draft
**Author:** isse + Claude
**Relates to:** Phase 6 (Track D) in `docs/plans/basalt-development-roadmap.md`

---

## What We're Building

Replace the current static nginx portal (port 443) with **Authentik** as the unified portal and authentication layer for the Basalt Stack. Authentik serves as both the **identity provider (IdP)** and the **main landing page** (application launcher) for all user-facing services.

### Scope

| Service | Integration Method | Status |
|---------|-------------------|--------|
| **Open-WebUI** (3002) | Authentik proxy provider + forward-auth headers (`X-Authentik-Email`, `X-Authentik-Name`) | Pre-coded in repo |
| **Onyx** (3000) | Native OIDC (`AUTH_TYPE=oidc` + env vars) | Supported, needs config |
| **RMF Generator** | Placeholder tile in Authentik app launcher | Web UI deferred to future phase |
| **Langfuse** (3001) | Not integrated — keeps its own NextAuth login | Out of scope |
| **LiteLLM** (8000) | Not integrated — keeps API key auth | Out of scope |

### Out of Scope

- Health dashboard (current portal's live status page) — revisit with dedicated monitoring tool later
- RMF generator web UI — future phase, placeholder tile only
- Langfuse SSO integration
- LiteLLM admin SSO
- Network segmentation (Phase 7, depends on this work)
- LDAP/Active Directory integration (local Authentik accounts sufficient for 5-25 users)

---

## Why This Approach

### Authentik as the Portal (not just the IdP)

- **Single entry point**: Users bookmark one URL (e.g., `https://<basalt-hostname>`), see all available apps
- **No extra component**: Authentik's built-in application launcher replaces the custom nginx portal — one less container to maintain
- **Consistent UX**: Login flow and app navigation happen in the same interface
- Authentik's app launcher supports custom icons, descriptions, and grouping — sufficient for our needs

### Embedded Proxy Outpost (not nginx auth_request or Traefik)

- **Simplest topology**: Authentik handles both auth AND proxying — no extra reverse proxy
- **Header injection**: The proxy outpost automatically injects `X-Authentik-Email`, `X-Authentik-Name` headers that Open-WebUI's pre-coded auth already expects
- **Single TLS termination point**: Authentik on port 443 is the only ingress

### Dual Auth Patterns

Two integration patterns are needed because the services have different capabilities:

1. **Open-WebUI → Forward-auth (proxy provider)**
   - Open-WebUI reads `X-Authentik-Email` and `X-Authentik-Name` headers
   - Code already exists in `open-webui/backend/apps/web/routers/auths.py` (lines 100, 133-135)
   - Authentik proxy outpost sits in front, authenticates, and injects headers
   - Open-WebUI auto-creates accounts on first login

2. **Onyx → Native OIDC (OAuth2 provider)**
   - Onyx has built-in OIDC support (`AUTH_TYPE=oidc`)
   - Authentik acts as the OIDC provider (issues tokens)
   - Onyx redirects to Authentik for login, receives identity via OIDC callback
   - Env vars: `OAUTH_CLIENT_ID`, `OAUTH_CLIENT_SECRET`, `OPENID_CONFIG_URL`
   - Callback URL: `{WEB_DOMAIN}/auth/oidc/callback`

### Self-Registration with Admin Approval

- Appropriate for 5-25 user deployments on a controlled network
- Users can request access without bothering an admin for every account
- Admin retains control over who gets access
- Configurable via Authentik enrollment flows

---

## Key Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Portal approach | **Authentik IS the portal** | Eliminates nginx portal, single entry point |
| 2 | Auth scope | **Onyx + Open-WebUI only** | Langfuse/LiteLLM have their own auth, keep it simple |
| 3 | Open-WebUI integration | **Forward-auth proxy** | Pre-coded header auth already in repo |
| 4 | Onyx integration | **Native OIDC** | Built-in support, cleanest path |
| 5 | Proxy architecture | **Authentik embedded proxy outpost** | Simplest — no extra reverse proxy component |
| 6 | User management | **Self-registration + admin approval** | Balanced access control for 5-25 users |
| 7 | User directory | **Local Authentik accounts** | No LDAP/AD needed at this scale |
| 8 | RMF tool access | **Placeholder tile only** | Web UI is a future phase |
| 9 | Health monitoring | **Dropped for now** | Revisit with Uptime Kuma or similar later |
| 10 | TLS | **Decide at deploy time** | Self-signed for dev, proper cert for target network |
| 11 | Authentik images | **Not yet staged** | Need image pull + save steps in plan |
| 12 | Authentik version | **Latest stable** | Research exact version; must support proxy outposts + OIDC |
| 13 | URL routing | **Subdomain** (`*.basalt.local`) | Path-based confirmed not supported by Authentik proxy — see plan |
| 14 | Header trust | **Shared-secret check** | Defense-in-depth on `X-Authentik-Email` headers |
| 15 | Bootstrap method | **Blueprint YAML files** | Version-controlled, reproducible configuration |
| 16 | Port 443 | **Stop portal, give to Authentik** | Clean cut — portal was never production-deployed |

---

## Implementation Phasing

### Phase 1 — Authentik Core

**Goal:** Authentik running and accessible, admin can log in.

- Update `basalt-stack/web/authentik/docker-compose.yaml` to match Basalt patterns:
  - Remove external `proxy` network (use `host.docker.internal` like all other stacks)
  - Add `extra_hosts: ["host.docker.internal:host-gateway"]`
  - Add health checks on server + worker services (use `127.0.0.1` not `localhost`)
  - Add log rotation (`max-size: "50m"`, `max-file: "6"`)
  - Update image tag from `2023.10.6` to a current stable release
  - Standardize image tag pattern with `.env` variables
- Fill `.env.example` with proper placeholder pattern (generate `AUTHENTIK_SECRET_KEY`)
- Disable telemetry/outbound calls (air-gap compliance):
  - `AUTHENTIK_DISABLE_UPDATE_CHECK=true`
  - `AUTHENTIK_ERROR_REPORTING__ENABLED=false`
  - `AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true`
  - Disable GeoIP (requires internet download)
- Configure enrollment flow: self-registration with admin approval
- Publish Authentik on port 443 (HTTPS)
- Document image staging steps (pull, save, transfer for air-gap)
- **Test:** Browse to Authentik, log in as admin, see empty app launcher

### Phase 2 — Open-WebUI Integration

**Goal:** Users log in via Authentik, get auto-created in Open-WebUI.

- Create an Authentik **Proxy Provider** for Open-WebUI
  - External host: `https://basalt/webui/` (or chosen path)
  - Internal host: `http://host.docker.internal:3002`
  - Forward auth headers: `X-Authentik-Email`, `X-Authentik-Name`
- Create an Authentik **Application** linked to the proxy provider
  - Name: "Open-WebUI" / "Chat"
  - Icon + description for the app launcher
- Deploy/configure the Authentik **proxy outpost** container
  - Listens on port 443
  - Routes to Open-WebUI backend
- Implement shared-secret header validation (Decision 14):
  - Configure Authentik proxy to inject a secret header (e.g., `X-Authentik-Secret`)
  - Modify Open-WebUI auth code to reject requests missing the valid secret
  - Store shared secret in both Authentik config and Open-WebUI `.env`
- Verify Open-WebUI's existing header-auth code works with Authentik's header injection
  - Check `open-webui/backend/apps/web/routers/auths.py` — sign-in reads `X-Authentik-Email`
- **Test:** Log in to Authentik → click Open-WebUI tile → auto-created account → chat works

### Phase 3 — Onyx OIDC Integration

**Goal:** Users log in via Authentik, SSO into Onyx.

- Create an Authentik **OAuth2/OIDC Provider** for Onyx
  - Client ID + Client Secret generated by Authentik
  - Redirect URI: `http://host.docker.internal:3000/auth/oidc/callback` (or proxied URL)
  - Scopes: `openid email profile`
- Create an Authentik **Application** linked to the OIDC provider
  - Name: "Onyx"
  - Icon + description for the app launcher
- Update Onyx `.env`:
  - `AUTH_TYPE=oidc`
  - `OAUTH_CLIENT_ID=<from Authentik>`
  - `OAUTH_CLIENT_SECRET=<from Authentik>`
  - `OPENID_CONFIG_URL=https://basalt/application/o/<slug>/.well-known/openid-configuration`
  - `WEB_DOMAIN=https://basalt/onyx` (or direct port URL)
- Proxy Onyx through Authentik outpost at `/onyx/` path (required for path-based routing)
- **Test:** Log in to Authentik → click Onyx tile → OIDC redirect → authenticated Onyx session

### Phase 4 — RMF Tile + Cleanup

**Goal:** All tiles visible, old portal retired, docs updated.

- Add RMF Generator as an Authentik **Application** (bookmark/link type)
  - Points to placeholder page or docs
  - Icon + description: "RMF Document Generator (Coming Soon)"
- Retire the nginx portal:
  - Stop/remove `basalt-stack/web/portal/` compose stack
  - Archive or delete portal files (or keep for reference)
- Update documentation:
  - `CLAUDE.md`: Update port table (Portal row → Authentik), startup sequence
  - `docs/basalt-system-design.md`: Update architecture diagram
  - `docs/plans/basalt-development-roadmap.md`: Mark Track D SSO items as complete
- Update `MEMORY.md`: Fix Authentik path (`web/authentik/` not `auth/authentik/`)
- **Test:** Full flow — browse to Authentik → see all tiles → SSO into each service

---

## Risks

### R1: Path-based routing may not work with Authentik's embedded proxy (HIGH)

Authentik's proxy outpost is designed for **per-application proxying**, typically using separate subdomains or distinct external URLs — not path-prefix multiplexing (`/onyx/`, `/webui/`) on a single hostname. If Authentik's proxy cannot route by path prefix, the topology breaks.

**Fallback approaches (evaluate during Phase 1):**
1. **Subdomain routing** — Use `onyx.basalt` and `webui.basalt` instead of `/onyx/` and `/webui/`. Requires hosts file entries on client machines.
2. **Direct port access** — Don't proxy at all. Authentik handles login (OIDC/forward-auth) but users access services on native ports (3000, 3002). Simplest fallback.
3. **Add nginx back** — Put nginx in front as the path-based router, use Authentik's `auth_request` pattern instead of embedded proxy. More components but proven path-routing support.

**Validation step:** Research Authentik proxy provider docs during Phase 1 before committing to path-based routing.

### R2: Open-WebUI path prefix compatibility (MEDIUM)

Open-WebUI may have hardcoded asset paths or redirects that break when served under `/webui/` instead of `/`. If so, it would need `WEBUI_URL` or a base-path config, or fall back to subdomain/port routing.

### R3: Onyx path prefix compatibility (MEDIUM)

Similar to R2 — Onyx's frontend may not handle being served under `/onyx/`. The `WEB_DOMAIN` env var may need to include the path prefix, and internal redirects/asset loading need to respect it.

---

## Air-Gap Considerations

| Concern | Mitigation |
|---------|------------|
| **Image staging** | Pull `goauthentik/server`, `goauthentik/proxy`, `postgres:16-alpine`, `redis:alpine` on connected machine → `docker save` → transfer → `docker load` |
| **Update checks** | `AUTHENTIK_DISABLE_UPDATE_CHECK=true` |
| **Error reporting** | `AUTHENTIK_ERROR_REPORTING__ENABLED=false` |
| **Analytics** | `AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true` |
| **GeoIP** | Disable GeoIP enrichment (requires MaxMind download) |
| **Blueprints** | Use local filesystem blueprints, not OCI references |
| **No CDN** | Authentik bundles its own frontend assets — no CDN dependency |
| **Fonts/icons** | Verify no external font/icon loading in Authentik's UI |

---

## Existing Code to Leverage

| What | Location | Notes |
|------|----------|-------|
| Open-WebUI Authentik headers | `open-webui/backend/apps/web/routers/auths.py` (lines ~100, ~133-135) | Reads `X-Authentik-Email` + `X-Authentik-Name`; uses `laci_` var prefix from prior project |
| Onyx OIDC env vars | `onyx/deployment/docker_compose/env.template` | All OIDC vars defined (commented out); `AUTH_TYPE` enum includes `oidc` |
| Authentik compose scaffold | `basalt-stack/web/authentik/` | Server + worker + Postgres + Redis. Needs pattern alignment (see Phase 1) |

---

## Architecture Diagram (Target State)

```
                    ┌─────────────────────────────┐
                    │      Authentik (443)         │
                    │  ┌───────────────────────┐   │
                    │  │   Application Launcher │   │
                    │  │  ┌─────┐ ┌─────────┐  │   │
                    │  │  │Onyx │ │Open-WebUI│  │   │
                    │  │  └──┬──┘ └────┬────┘  │   │
                    │  │     │         │        │   │
                    │  │  ┌──┴──┐ ┌────┴────┐  │   │
                    │  │  │ RMF │ │ (future)│  │   │
                    │  │  └─────┘ └─────────┘  │   │
                    │  └───────────────────────┘   │
                    └──────────┬───────────────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
    ┌─────────▼──────┐ ┌──────▼───────┐ ┌──────▼──────┐
    │   Onyx (3000)  │ │Open-WebUI    │ │  RMF Tool   │
    │   (OIDC flow)  │ │  (3002)      │ │ (placeholder│
    │                │ │(header auth) │ │  for now)   │
    └────────┬───────┘ └──────────────┘ └─────────────┘
             │
    ┌────────▼───────┐
    │  LiteLLM (8000)│──→ Langfuse (3001)
    └────────┬───────┘
             │
    ┌────────▼───────┐
    │   vLLM (8001)  │
    └────────────────┘
```

---

## Resolved Questions

1. **Should Authentik be the portal or guard the portal?** → Authentik IS the portal
2. **Which services get SSO?** → Onyx + Open-WebUI only
3. **Proxy architecture?** → Authentik embedded proxy (no nginx/Traefik)
4. **User management model?** → Self-registration with admin approval, local accounts
5. **Health dashboard?** → Drop for now
6. **RMF tool access?** → Placeholder tile, web UI later
7. **TLS?** → Decide at deploy time
8. **Implementation order?** → Phased: Core → Open-WebUI → Onyx → Tiles + Cleanup
9. **Authentik version?** → Latest stable release (research exact version during Phase 1)
10. **URL routing scheme?** → Path-based (`/onyx/`, `/webui/`) — no DNS changes needed
11. **Open-WebUI header trust?** → Add shared-secret header check (defense-in-depth even on air-gap)
12. **Bootstrap automation?** → Blueprint YAML files (version-controlled, reproducible)
13. **Port 443 conflict?** → Stop nginx portal, give 443 to Authentik immediately

## Open Questions

None — all questions resolved.
