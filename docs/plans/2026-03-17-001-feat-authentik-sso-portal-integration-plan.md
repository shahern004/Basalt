---
title: "feat: Authentik SSO Portal Integration"
type: feat
status: active
date: 2026-03-17
origin: docs/brainstorms/2026-03-17-authentik-sso-portal-brainstorm.md
---

# Authentik SSO Portal Integration

## Enhancement Summary

**Deepened on:** 2026-03-17
**Agents used:** architecture-strategist, security-sentinel, deployment-verification-agent, code-simplicity-reviewer, performance-oracle, pattern-recognition-specialist, best-practices-researcher (7 total)

### Key Improvements from Deepening

1. **Health checks corrected:** `wget`/`curl` are NOT in the Authentik image — use `python3 urllib` instead
2. **Volume mount corrected:** Use `./data:/data` (not `media:/media`) — breaking change in 2025.12+
3. **`shm_size: 512mb`** required on server and worker (official compose requirement)
4. **Security blockers identified:** Replace email-as-password with random password, remove `t0p-s3cr3t` JWT fallback, use `hmac.compare_digest()` for shared-secret
5. **Blueprints simplified:** Configure via admin UI first, export later if needed (YAGNI for sole contributor)
6. **Phase 4 dissolved:** Cleanup tasks merged into Phases 1-3 (reduce to 3 phases)
7. **Wildcard SAN:** Use `*.basalt.local` in TLS cert to avoid regeneration for future subdomains
8. **Open-WebUI native trusted headers:** Upstream now supports `WEBUI_AUTH_TRUSTED_EMAIL_HEADER` — evaluate vs custom fork code
9. **Onyx may not need proxy provider:** If OIDC handles auth, outpost routing may be the only proxy needed — investigate during Phase 3
10. **Memory limits added:** server: 1.5G, worker: 1G, postgres: 512M, redis: 256M
11. **WebSocket verification:** Must confirm embedded outpost handles `Upgrade: websocket` for Open-WebUI streaming
12. **Deployment checklist:** Pre-deployment gates, per-phase rollback procedures, 24-hour monitoring plan added
13. **Pin Redis tag:** Use `redis:7.4-alpine` (not floating `redis:alpine`)

### Security Findings (Pre-Deployment Blockers)

| # | Severity | Finding | Remediation |
|---|----------|---------|-------------|
| S1 | **CRITICAL** | Open-WebUI uses email as password — anyone on port 3002 can auth as any user | Use `secrets.token_urlsafe(32)` as password during signup |
| S2 | **CRITICAL** | JWT secret defaults to `t0p-s3cr3t` if env missing | Remove default, use `:?error` |
| S3 | **HIGH** | Shared-secret comparison vulnerable to timing attack | Use `hmac.compare_digest()` |
| S4 | **HIGH** | Blueprint YAML may contain plaintext secrets | Use `!Env` tags for all secrets |
| S5 | **HIGH** | HTTP for internal OIDC leaks tokens on Docker bridge | Document as known debt; prefer HTTPS with cert patch |

---

## Overview

Replace the static nginx portal (port 443) with **Authentik** as the unified identity provider, reverse proxy, and application launcher for the Basalt Stack. Authentik handles authentication for **Onyx** (OIDC) and **Open-WebUI** (forward-auth header injection) via **subdomain routing** on the `basalt.local` domain.

**Target state:** Users browse to `https://auth.basalt.local`, log in once, and access all services through Authentik's application launcher tiles — each service on its own subdomain, proxied through Authentik's embedded outpost.

| Subdomain | Backend | Auth Method |
|-----------|---------|-------------|
| `auth.basalt.local` | Authentik server (9443) | Login page + app launcher |
| `webui.basalt.local` | Open-WebUI (3002) | Proxy provider + `X-Authentik-*` headers |
| `onyx.basalt.local` | Onyx (3000) | Proxy provider + native OIDC |
| `rmf.basalt.local` | Placeholder | Bookmark tile (future) |

---

## Problem Statement

The Basalt Stack currently has:
- **No unified authentication** — each service has its own login (or none)
- **No single entry point** — users must know individual service ports
- **A static portal** that was never deployed to production (todo 022 still open)
- **Authentik scaffold** that is outdated (2023.10.6) and misaligned with Basalt compose patterns

Users need a single URL they can bookmark, one login that grants access to all services, and admins need centralized user management with approval-based registration.

---

## Proposed Solution

Deploy Authentik 2026.2 as the central identity provider and reverse proxy:

1. **Authentik as portal** — Application launcher replaces the nginx portal
2. **Subdomain routing** — Each service gets its own subdomain (`*.basalt.local`) with a dedicated Authentik proxy provider
3. **Embedded outpost** — No extra proxy container; Authentik's built-in outpost handles TLS termination, authentication, and reverse proxying
4. **Dual auth patterns** — Open-WebUI uses forward-auth headers; Onyx uses native OIDC
5. **Blueprint YAML** — Version-controlled, reproducible Authentik configuration
6. **Self-registration + admin approval** — Users request accounts; admins approve

### Architecture (Target State)

```
  Client (browser)
    │
    │  DNS/hosts: *.basalt.local → <host-ip>
    │
    ▼
  ┌──────────────────────────────────────────────┐
  │         Authentik (port 443 / 9443)          │
  │                                              │
  │  auth.basalt.local → App Launcher / Login    │
  │  webui.basalt.local → Proxy Provider ────────┼──→ Open-WebUI (3002)
  │  onyx.basalt.local  → Proxy Provider ────────┼──→ Onyx (3000)
  │                                              │    ↕ OIDC callback
  │  Embedded Outpost (proxy mode)               │
  │  Injects: X-Authentik-Email, Name, Secret    │
  └──────────────────────────────────────────────┘
                        │
                        │ host.docker.internal
                        ▼
              ┌─────────────────┐
              │  LiteLLM (8000) │──→ Langfuse (3001)
              └────────┬────────┘
                       │
              ┌────────▼────────┐
              │   vLLM (8001)   │
              └─────────────────┘
```

---

## Technical Approach

### Key Technical Decisions

| # | Decision | Choice | Source |
|---|----------|--------|--------|
| 1 | Portal approach | Authentik IS the portal | Brainstorm D1 |
| 2 | Routing | **Subdomain** (`*.basalt.local`) | Research: path-based not supported by Authentik proxy |
| 3 | Auth scope | Onyx + Open-WebUI only | Brainstorm D2 |
| 4 | Open-WebUI auth | Forward-auth proxy + header injection | Brainstorm D3 |
| 5 | Onyx auth | Native OIDC | Brainstorm D4 |
| 6 | Proxy architecture | Embedded outpost (no extra container) | Brainstorm D5, confirmed by docs |
| 7 | User management | Self-registration + admin approval | Brainstorm D6 |
| 8 | Header trust | Shared-secret `X-Authentik-Secret` via `additionalHeaders` | Brainstorm D14, confirmed feasible |
| 9 | Bootstrap | Blueprint YAML files | Brainstorm D15 |
| 10 | Authentik version | **2026.2** (`ghcr.io/goauthentik/server:2026.2`) | Research |
| 11 | PostgreSQL | **16-alpine** (Authentik requires 14+) | Research |
| 12 | Domain | `basalt.local` | User choice |
| 13 | Open-WebUI JWT | **24h expiry** (was `-1` / never) | SpecFlow gap: deprovisioning |
| 14 | Port protection | Shared-secret header (127.0.0.1 binding breaks host-routed arch) | SpecFlow + constraint analysis |
| 15 | Admin bootstrap | Admin seeds Open-WebUI account before enabling proxy | SpecFlow gap: first-user race |
| 16 | Open-WebUI role | `DEFAULT_USER_ROLE=user` (not default `pending`) | SpecFlow gap: double-approval |

### Why Subdomain Routing (not path-based)

The brainstorm originally chose path-based routing (`/onyx/`, `/webui/`). External research confirmed this is **not supported** by Authentik's proxy provider — each provider maps to one external host (subdomain), not path prefixes on a shared hostname. Additionally, neither Open-WebUI nor Onyx support configurable base paths, so path-prefix routing would break frontend asset loading.

**Subdomain routing** is Authentik's native pattern:
- Each service = one proxy provider = one subdomain
- No URL rewriting, no base-path issues
- Requires hosts file entries on client machines (5-25 users, manageable)

### Why Not Bind Ports to 127.0.0.1

The Basalt architecture uses `host.docker.internal` for inter-stack communication. Docker containers connect through the bridge gateway IP, not the loopback interface. Binding backend ports to `127.0.0.1` would make them unreachable from the Authentik proxy outpost container.

**Primary defense:** Shared-secret header (`X-Authentik-Secret`) — Open-WebUI rejects requests without the valid secret, even if someone accesses port 3002 directly.

**Future hardening:** Phase 7 network segmentation will use Docker network policies and firewall rules to restrict port access.

---

## Implementation Phases

### Phase 1 — Authentik Core Deployment

**Goal:** Authentik running on port 443, admin can log in, air-gap compliant.

**Estimated effort:** Medium (compose rewrite + env config + TLS + blueprint scaffolding)

#### Tasks

- [x] **1.1 Rewrite `basalt-stack/web/authentik/docker-compose.yaml`**
  - Remove `proxy` external network (anti-pattern — Basalt uses host-routed networking)
  - Add `extra_hosts: ["host.docker.internal:host-gateway"]` to BOTH `server` and `worker` services
  - Update image to `ghcr.io/goauthentik/server:2026.2.1` using `${AUTHENTIK_IMAGE:-ghcr.io/goauthentik/server}:${AUTHENTIK_TAG:?error}` pattern
  - **Add `shm_size: 512mb`** to both server and worker (official requirement, prevents OOM)
  - Add health checks using **`python3 urllib`** (NOT wget/curl — they are not in the Authentik image):
    ```yaml
    # Server health check
    healthcheck:
      test: ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9000/-/health/live/')"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    # Worker health check
    healthcheck:
      test: ["CMD", "ak", "healthcheck"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    ```
  - Add log rotation via YAML anchor: `&default-logging` with `json-file`, `max-size: "50m"`, `max-file: "6"`
  - Publish ports with env vars: `${AUTHENTIK_PORT_HTTPS:-443}:9443` and `${AUTHENTIK_PORT_HTTP:-80}:9000`
  - Use `depends_on` with `condition: service_healthy` (not bare list) for startup ordering
  - Keep YAML anchors (`&authentik-env`, `&authentik-vols`) for DRY config
  - Mount volumes: `./data:/data`, `./custom-templates:/templates`, `./certs:/certs`, `./blueprints/custom:/blueprints/custom` on both `server` and `worker`
  - Add memory limits: server 1.5G, worker 1G, postgres 512M, redis 256M
  - Do NOT mount Docker socket (not needed for embedded outpost, security risk)

- [x] **1.2 Upgrade `basalt-stack/web/authentik/db/include.yaml`**
  - Upgrade PostgreSQL from `12-alpine` to `16-alpine` (Authentik 2026.2 requires 14+)
  - **Pin Redis to `redis:7.4-alpine`** (not floating `redis:alpine`)
  - Keep existing health checks (they already use proper patterns)
  - Remove hardcoded `PG_PASS:-authentik` default — use `${POSTGRES_PASSWORD:?error}` (fail loudly)
  - Add `--requirepass` to Redis with `REDIS_PASSWORD` env var
  - Add log rotation to `postgres` and `redis` services

- [x] **1.3 Create `basalt-stack/web/authentik/.env.example`** (rewrite from scratch)
  Use `.env.example` banner format (matching Open-WebUI/Portal convention):
  ```env
  #####################################################################
  ## Authentik Image
  #####################################################################
  AUTHENTIK_IMAGE=ghcr.io/goauthentik/server
  AUTHENTIK_TAG=2026.2.1

  #####################################################################
  ## Authentik Secrets (generate each: openssl rand -hex 32)
  #####################################################################
  AUTHENTIK_SECRET_KEY=<generate>
  AUTHENTIK_BOOTSTRAP_PASSWORD=<generate>
  AUTHENTIK_BOOTSTRAP_EMAIL=admin@basalt.local

  #####################################################################
  ## PostgreSQL (passwords max 99 chars — use openssl rand -hex 32)
  #####################################################################
  PG_USER=authentik
  PG_PASS=<generate>
  PG_DB=authentik

  #####################################################################
  ## Redis
  #####################################################################
  REDIS_PASSWORD=<generate>

  #####################################################################
  ## Air-Gap (all mandatory — do not remove)
  #####################################################################
  AUTHENTIK_DISABLE_UPDATE_CHECK=true
  AUTHENTIK_ERROR_REPORTING__ENABLED=false
  AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true
  AUTHENTIK_AVATARS=initials

  #####################################################################
  ## Ports
  #####################################################################
  AUTHENTIK_PORT_HTTPS=443
  AUTHENTIK_PORT_HTTP=80
  ```

- [x] **1.4 Create TLS certificate**
  - Adapt portal's `scripts/gen-cert.sh` for Authentik
  - **Use wildcard SAN**: `*.basalt.local`, `basalt.local`, `host.docker.internal`, `127.0.0.1`, `localhost`
  - Wildcard eliminates certificate regeneration when adding future subdomains
  - RSA 4096, 10-year validity (matches portal pattern)
  - Drop cert files into `./certs/` directory — Authentik worker auto-discovers and imports PEM files
  - Naming: `basalt.local.pem` (fullchain) + `basalt.local-key.pem` (private key)
  - After first boot, assign cert to brand in Admin UI (System > Brands > web certificate)
  - Set `authentik_host_insecure: true` on embedded outpost config (self-signed TLS)

- [x] **1.5 Create minimal blueprint** in `basalt-stack/web/authentik/blueprints/custom/`
  - `00-system-settings.yaml` only — set avatar to `initials`, brand title to "Basalt Stack"
  - All other configuration (providers, applications, enrollment flow) done via **admin UI** — export as blueprints later if reproducibility needed (YAGNI for sole contributor one-time setup)
  - Configure enrollment flow in admin UI: Prompt stage → UserWrite stage (`create_users_as_inactive: true`) → Deny stage ("pending approval" message)
  - **First-boot URL**: Navigate to `https://auth.basalt.local/if/flow/initial-setup/` to set up admin account

- [x] **1.6 Stage images** for air-gap transfer
  - `ghcr.io/goauthentik/server:2026.2.1` (server + worker)
  - `docker.io/library/postgres:16-alpine`
  - `docker.io/library/redis:7.4-alpine` (pinned, not floating `alpine`)
  - No `ghcr.io/goauthentik/proxy` needed (using embedded outpost)
  - Record image digests: `docker image inspect --format '{{.Id}}'` for verification after transfer
  - Script: `docker save -o <name>.tar` → transfer → `docker load -i <name>.tar`

- [x] **1.7 Create hosts file template** for client machines
  ```
  # Basalt Stack — add to C:\Windows\System32\drivers\etc\hosts
  <host-ip>  auth.basalt.local
  <host-ip>  webui.basalt.local
  <host-ip>  onyx.basalt.local
  <host-ip>  rmf.basalt.local
  ```

- [ ] **1.8 Stop nginx portal** — `docker compose down` in `basalt-stack/web/portal/`
  - Keep portal files archived (do not delete yet — rollback safety)

#### Success Criteria

- [ ] `docker compose up -d` starts Authentik without errors
- [ ] All 4 containers healthy (server, worker, postgres, redis)
- [ ] Browse to `https://auth.basalt.local` → Authentik login page loads
- [ ] Admin can log in with bootstrap credentials (first-boot URL: `/if/flow/initial-setup/`)
- [ ] No outbound network requests (verify with browser DevTools Network tab for 60 seconds)
- [ ] Enrollment flow with admin approval is configured and tested
- [ ] **Embedded outpost subdomain validation**: configure a test proxy provider for `webui.basalt.local` pointing to `http://host.docker.internal:3002`, verify that browsing to `https://webui.basalt.local` routes through Authentik (redirects to login). This validates subdomain routing works before committing to Phase 2.
- [ ] **WebSocket verification**: confirm embedded outpost handles `Upgrade: websocket` header (test by logging in and opening Open-WebUI chat — streaming must work)

#### Rollback

If Authentik fails to start:
```bash
cd basalt-stack/web/authentik && docker compose down
cd basalt-stack/web/portal && docker compose up -d
# Remove hosts file entry for auth.basalt.local
```
Portal files are preserved for this purpose (do not delete until Phase 3 complete).

---

### Phase 2 — Open-WebUI SSO Integration

**Goal:** Users log in via Authentik, get auto-created in Open-WebUI with `user` role.

**Estimated effort:** Medium (proxy provider + header validation + env vars + admin bootstrap)

**Prerequisite:** Phase 1 complete. Open-WebUI stack running.

#### Tasks

- [ ] **2.1 Bootstrap Open-WebUI admin account**
  - Before enabling Authentik proxy, access Open-WebUI directly at `http://localhost:3002`
  - Create the admin account manually (first account = admin role)
  - This prevents the first-user race condition (SpecFlow Gap 5)

- [ ] **2.2 Create Authentik Proxy Provider** (via admin UI, not blueprint)
  - Admin UI: Applications > Providers > Create Proxy Provider
  - Name: `openwebui-proxy`
  - Mode: `Proxy`
  - External host: `https://webui.basalt.local`
  - Internal host: `http://host.docker.internal:3002`
  - Access token validity: `hours=24`
  - Authorization flow: `default-provider-authorization-implicit-consent`
  - Create Application: name "Open-WebUI", slug `openwebui`, group "AI Services"
  - Bind provider to embedded outpost (Outposts → authentik Embedded Outpost → select openwebui-proxy)

- [ ] **2.3 Configure shared-secret header** (Defense-in-depth, Decision 14)
  - Create a group `basalt-users` in Authentik with `additionalHeaders` attribute:
    ```json
    {"additionalHeaders": {"X-Authentik-Secret": "<generated-shared-secret>"}}
    ```
  - **Important:** scope mapping names must NOT contain spaces (known Authentik bug #4094)
  - Add all users (including admin) to this group
  - Configure the enrollment flow to auto-assign this group on approval

- [x] **2.4 Modify Open-WebUI auth code** — `open-webui/backend/apps/web/routers/auths.py`
  - **SECURITY BLOCKER (S1):** Replace email-as-password with random password:
    ```python
    # In /signup handler, replace:
    #   hashed = get_password_hash(laci_email)
    # With:
    import secrets
    hashed = get_password_hash(secrets.token_urlsafe(32))
    ```
  - **SECURITY BLOCKER (S3):** Add shared-secret validation using constant-time comparison:
    ```python
    import hmac
    expected_secret = os.environ.get("AUTHENTIK_SHARED_SECRET", "")
    if expected_secret:
        request_secret = request.headers.get("X-Authentik-Secret", "")
        if not hmac.compare_digest(request_secret, expected_secret):
            raise HTTPException(403, "Invalid authentication source")
    ```
  - Add null-check: `if not laci_email: raise HTTPException(400, "Missing identity header")`
  - Place these checks at the TOP of both `/signin` and `/signup` endpoints
  - **Alternative (evaluate):** Upstream Open-WebUI now supports native trusted headers via `WEBUI_AUTH_TRUSTED_EMAIL_HEADER` env var. If this works with current codebase version, it may be cleaner than maintaining the custom `laci_` fork code. Test during implementation.

- [x] **2.4b Fix Open-WebUI JWT secret fallback** (SECURITY BLOCKER S2)
  - In `open-webui/backend/config.py` (~line 304): remove `"t0p-s3cr3t"` default
  - Change to: `WEBUI_SECRET_KEY = os.environ.get("WEBUI_SECRET_KEY", os.environ.get("WEBUI_JWT_SECRET_KEY"))` — fail if not set

- [x] **2.5 Back up and update Open-WebUI environment** — `basalt-stack/web/open-webui/.env`
  - Back up first: `cp .env .env.pre-authentik`
  - Add/update:
    ```env
    ENABLE_SIGNUP=True
    DEFAULT_USER_ROLE=user
    JWT_EXPIRES_IN=24h
    AUTHENTIK_SHARED_SECRET=<same-secret-as-in-authentik-group>
    ```
  - `DEFAULT_USER_ROLE=user` prevents double-approval (SpecFlow Gap 4)
  - `JWT_EXPIRES_IN=24h` ensures deprovisioned users lose access within 24 hours (SpecFlow Gap 16)

- [ ] **2.6 Rebuild and restart Open-WebUI** (code changes require container rebuild)

- [ ] **2.7 Add `webui.basalt.local` to hosts file** on the dev machine (if not already done in Phase 1 test)

#### Success Criteria

- [ ] Browse to `https://webui.basalt.local` → redirects to Authentik login
- [ ] Log in with admin account → auto-authenticated in Open-WebUI (existing account)
- [ ] Chat streaming works via WebSocket through the proxy
- [ ] Create a test user in Authentik → approve → add to `basalt-users` group → test user logs in → auto-created in Open-WebUI with `user` role
- [ ] Direct access to `http://localhost:3002` with spoofed `X-Authentik-Email` header → rejected (403)
- [ ] Spoofed header with wrong `X-Authentik-Secret` → rejected (403)
- [ ] Deactivate test user in Authentik → within 24h, test user cannot access Open-WebUI

#### Rollback

```bash
cp basalt-stack/web/open-webui/.env.pre-authentik basalt-stack/web/open-webui/.env
git checkout -- open-webui/backend/apps/web/routers/auths.py
git checkout -- open-webui/backend/config.py
cd basalt-stack/web/open-webui && docker compose down && docker compose up -d
# Remove openwebui-proxy from embedded outpost in Authentik admin UI
```

---

### Phase 3 — Onyx OIDC Integration

**Goal:** Users log in via Authentik, SSO into Onyx via OIDC.

**Estimated effort:** Medium (OIDC provider + cert trust + env vars)

**Prerequisite:** Phase 1 complete. Onyx stack running.

#### Tasks

- [ ] **3.1 Create Authentik OAuth2/OIDC Provider** (via admin UI)
  - Admin UI: Applications > Providers > Create OAuth2/OIDC Provider
  - Name: `onyx-oidc`
  - Client type: confidential
  - Generate client ID + secret (record for Onyx `.env`)
  - Redirect URIs: `https://onyx.basalt.local/auth/oidc/callback`
  - Scopes: `openid email profile`
  - Signing key: "authentik Self-signed Certificate"
  - Create Application: name "Onyx", slug `onyx`, group "AI Services"

- [ ] **3.2 Create Authentik Proxy Provider for Onyx** (via admin UI)
  - **Investigate first:** Can Onyx work with OIDC provider alone (no proxy provider)? If Onyx handles its own OIDC redirects, the outpost only needs to route traffic, not manage auth sessions. Test by:
    1. Creating just the OIDC provider + application
    2. Setting the application's launch URL to `https://onyx.basalt.local`
    3. If Onyx's native OIDC redirect flow works without proxy-level session management, skip the proxy provider
  - If proxy provider IS needed: `external_host=https://onyx.basalt.local`, `internal_host=http://host.docker.internal:3000`, bind to embedded outpost
  - **Clarify session governance:** proxy session (cookie-based) vs OIDC session (token-based) — which controls access?

- [x] **3.3 Configure TLS trust for Onyx → Authentik OIDC discovery**
  - Onyx's OIDC client calls Authentik's `.well-known/openid-configuration` endpoint
  - If Authentik uses a self-signed cert, this call fails with SSL verification error
  - Review and apply `onyx/deployment/docker_compose/custom_cert_oauth_client.patch`
  - Mount the Authentik CA certificate into the Onyx container
  - Alternative: set `OPENID_CONFIG_URL` to use HTTP (`http://host.docker.internal:9000/...`) for the internal OIDC discovery call, keeping HTTPS only for user-facing traffic
  - **Decision: using HTTP for internal OIDC discovery. Patch deferred to Phase 7.**

- [x] **3.4 Back up and update Onyx environment** — `onyx/deployment/docker_compose/.env`
  - Back up first: `cp .env .env.pre-authentik`
  - Update:
  ```env
  AUTH_TYPE=oidc
  OAUTH_CLIENT_ID=<from-authentik-provider>
  OAUTH_CLIENT_SECRET=<from-authentik-provider>
  OPENID_CONFIG_URL=http://host.docker.internal:9000/application/o/onyx/.well-known/openid-configuration
  WEB_DOMAIN=https://onyx.basalt.local
  ```
  - Using HTTP for internal OIDC discovery avoids self-signed cert trust issue (document as known security debt — upgrade to HTTPS in Phase 7 using `custom_cert_oauth_client.patch`)
  - `WEB_DOMAIN` must match the redirect URI registered in Authentik exactly

- [ ] **3.5 Restart Onyx stack** with new auth configuration

- [ ] **3.6 Add `onyx.basalt.local` to hosts file** on the dev machine

- [x] **3.7 Cleanup tasks** (formerly Phase 4)
  - Archive portal: `git mv basalt-stack/web/portal basalt-stack/web/portal-archived`
  - Update `CLAUDE.md`: port table, architecture diagram, startup sequence, fix Authentik path
  - Update `docs/basalt-system-design.md` and roadmap
  - Close todo 022 as "superseded by Authentik"
  - Create hosts file template at `basalt-stack/web/authentik/hosts-template.txt` (done in Phase 1)

#### Success Criteria

- [ ] Browse to `https://onyx.basalt.local` → redirects to Authentik login
- [ ] Log in → OIDC callback → authenticated Onyx session
- [ ] User created in Onyx with correct email from Authentik
- [ ] Cross-app SSO: already logged into Authentik → click Onyx tile → no re-login needed
- [ ] `OPENID_CONFIG_URL` resolves and returns valid OIDC configuration JSON
- [ ] Full end-to-end: login → app launcher → SSO into Open-WebUI and Onyx without re-login
- [ ] Documentation updated (CLAUDE.md, system design, roadmap)

#### Rollback

```bash
cp onyx/deployment/docker_compose/.env.pre-authentik onyx/deployment/docker_compose/.env
cd onyx/deployment/docker_compose && docker compose down && docker compose up -d
# AUTH_TYPE=disabled restores unauthenticated access
```

---

---

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| **Path-based routing** (`/onyx/`, `/webui/`) | Authentik proxy providers don't support path-prefix multiplexing. Neither Open-WebUI nor Onyx support configurable base paths. |
| **Authentik embedded proxy (original plan)** | Works for subdomain routing but not path-based. Evolved into the current subdomain approach. |
| **nginx + auth_request** | Adds nginx back as an extra component. Authentik's native proxy mode with subdomains is cleaner and eliminates the extra container. |
| **Direct port access** | Simplest but breaks Open-WebUI header auth (no proxy = no header injection). Users would see different ports — not a unified portal experience. |
| **Traefik middleware** | Adds Traefik as a new dependency. Overkill for a single-host deployment. |

---

## System-Wide Impact

### Interaction Graph

1. User → `auth.basalt.local` (Authentik) → login flow → session cookie set
2. User → `webui.basalt.local` → Authentik embedded outpost intercepts → validates session → injects `X-Authentik-Email`, `X-Authentik-Name`, `X-Authentik-Secret` headers → proxies to Open-WebUI (3002)
3. Open-WebUI `/signin` → reads `X-Authentik-Email` header → validates `X-Authentik-Secret` → authenticates user → returns JWT
4. User → `onyx.basalt.local` → Authentik embedded outpost intercepts → validates session → proxies to Onyx (3000) → Onyx redirects to Authentik OIDC → authorization code flow → callback → Onyx session created
5. Onyx backend → `host.docker.internal:9000` → Authentik OIDC discovery + token exchange (HTTP, internal)
6. LiteLLM, Langfuse, vLLM — **unaffected** (keep existing auth mechanisms)

### Error Propagation

| Error | Source | Effect | Handling |
|-------|--------|--------|----------|
| Authentik down | Container crash/restart | All SSO blocked, no new logins. Existing Open-WebUI JWTs valid for up to 24h. Onyx sessions persist until expiry. | Redis + Postgres persist sessions across restarts. `unless-stopped` restart policy. |
| Open-WebUI down | Container crash | Authentik proxy returns 502. Other services unaffected. | Default Authentik error page. |
| Onyx down | Container crash | Same as Open-WebUI. | Same. |
| Invalid shared secret | Misconfigured env | Open-WebUI rejects all Authentik-proxied requests (400). | Verify secrets match in Authentik group `additionalHeaders` and Open-WebUI `AUTHENTIK_SHARED_SECRET`. |
| OIDC discovery fails | Authentik unreachable from Onyx | Onyx fails to start with `AUTH_TYPE=oidc`. | Check `OPENID_CONFIG_URL` is reachable via `host.docker.internal:9000`. |
| Self-signed cert untrusted | Browser or Onyx | Browser warnings (expected). Onyx OIDC may fail. | Use HTTP for internal OIDC discovery. Distribute CA cert to users if needed. |

### State Lifecycle Risks

| Risk | Mitigation |
|------|------------|
| Open-WebUI user created but Authentik user deprovisioned | JWT expires in 24h, forcing re-auth through Authentik (which blocks). No orphan cleanup needed — Open-WebUI account just becomes inaccessible. |
| Authentik Redis data loss | Sessions lost, mass re-login required. Redis volume must be persistent (already configured with `--save 60 1`). |
| Blueprint applied twice | Blueprints use `state: present` (idempotent create-or-update). Safe to re-apply. |
| Wrong user becomes Open-WebUI admin | Admin seeds account in Phase 2.1 before enabling proxy. |

### API Surface Parity

| Interface | Auth Method | Change Needed |
|-----------|-------------|---------------|
| Open-WebUI browser UI | Authentik proxy + header injection | Shared-secret validation added |
| Open-WebUI API (`/api/v1/*`) | JWT from header-auth flow | JWT expiry changed to 24h |
| Onyx browser UI | OIDC redirect to Authentik | `AUTH_TYPE=oidc` + env vars |
| Onyx API | OIDC session | Same OIDC flow |
| LiteLLM API | API key (`LITELLM_MASTER_KEY`) | No change |
| Langfuse UI | NextAuth (built-in) | No change |
| vLLM API | None (internal only) | No change |

### Integration Test Scenarios

1. **Cross-app SSO**: Log in to Authentik → open Open-WebUI in tab A → open Onyx in tab B → neither requires re-login
2. **Deprovisioning**: Deactivate user in Authentik → user can access Open-WebUI for up to 24h (JWT) → after expiry, blocked → Onyx immediately blocked on next OIDC check
3. **Restart resilience**: Restart Authentik containers → existing sessions persist → user refreshes page → still logged in
4. **Spoofing defense**: `curl -H "X-Authentik-Email: admin@basalt.local" http://localhost:3002/api/v1/auths/signin` → rejected (missing `X-Authentik-Secret`)
5. **New user flow**: User registers in Authentik → pending → admin approves → user clicks Open-WebUI tile → account auto-created with `user` role (not `pending`)

---

## Acceptance Criteria

### Functional Requirements

- [ ] Authentik accessible at `https://auth.basalt.local`
- [ ] Application launcher shows tiles for Open-WebUI, Onyx, and RMF placeholder
- [ ] Open-WebUI SSO via forward-auth proxy with `X-Authentik-*` headers
- [ ] Onyx SSO via native OIDC with Authentik as provider
- [ ] Cross-app SSO works (single Authentik login, access all services)
- [ ] Self-registration with admin approval enrollment flow
- [ ] User deprovisioning in Authentik blocks access to all services (within 24h for Open-WebUI)
- [ ] Shared-secret header blocks direct port access with spoofed headers
- [ ] Blueprint YAML files define all providers, applications, and flows

### Non-Functional Requirements

- [ ] All Authentik telemetry disabled (no outbound network requests)
- [ ] All images pre-staged for air-gap deployment
- [ ] Health checks on all Authentik services (using `127.0.0.1`, not `localhost`)
- [ ] Log rotation on all containers
- [ ] Compose patterns aligned with Basalt conventions (extra_hosts, image tagging, restart policy)
- [ ] Self-signed TLS with SAN covering all subdomains

### Quality Gates

- [ ] `docker compose up -d` starts all services cleanly
- [ ] All 5 integration test scenarios pass
- [ ] Documentation updated (CLAUDE.md, system design, roadmap)
- [ ] Solution doc written (`docs/solutions/authentik-sso-integration.md`)
- [ ] Hosts file template ready for user distribution

---

## Dependencies & Prerequisites

| Dependency | Status | Notes |
|------------|--------|-------|
| Open-WebUI stack running | Required for Phase 2 | `basalt-stack/web/open-webui/` |
| Onyx stack running | Required for Phase 3 | `onyx/deployment/docker_compose/` |
| Docker Desktop with WSL2 | Required | Already in place |
| Port 443 available | Required for Phase 1 | Stop nginx portal first |
| Authentik images staged | Required for air-gap | Phase 1.6 |
| Hosts file entries | Required for subdomain routing | Phase 1.7 |

---

## Risk Analysis & Mitigation

| Risk | Severity | Likelihood | Mitigation |
|------|----------|-----------|------------|
| **Subdomain routing requires hosts file on every client** | Medium | Certain | Create distribution template + instructions. Only 5-25 users. |
| **Self-signed TLS browser warnings** | Low | Certain | Expected on air-gap. Distribute CA cert to client machines, or accept warnings. |
| **Onyx OIDC fails with self-signed cert** | High | Likely | Use HTTP for internal OIDC discovery URL (`host.docker.internal:9000`). Review `custom_cert_oauth_client.patch`. |
| **Open-WebUI `email-as-password` vulnerability** | High | Low (air-gap) | Shared-secret header blocks spoofed requests. Phase 7 firewall rules for port-level protection. |
| **Blueprint YAML authoring complexity** | Medium | Moderate | Start with admin UI configuration, export as blueprints. Authentik blueprints auto-refresh every 60 minutes. |
| **Authentik embedded outpost doesn't serve subdomains correctly** | Medium | Low | Verify during Phase 1 with a test provider before committing to Phases 2-3. Fall back to standalone outpost if needed. |
| **Authentik version 2026.2 unavailable for staging** | Low | Low | Fall back to 2025.12 (also supported). |

---

## Air-Gap Compliance Checklist

| Item | Config | Verified |
|------|--------|----------|
| Update checks disabled | `AUTHENTIK_DISABLE_UPDATE_CHECK=true` | [ ] |
| Error reporting disabled | `AUTHENTIK_ERROR_REPORTING__ENABLED=false` | [ ] |
| Startup analytics disabled | `AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true` | [ ] |
| Avatars set to initials | `AUTHENTIK_AVATARS=initials` (not Gravatar) | [ ] |
| GeoIP disabled | No config needed — fails silently without internet | [ ] |
| No CDN dependencies | Authentik bundles frontend assets | [ ] Verify in browser dev tools |
| No external fonts | Check network tab for font requests | [ ] Verify in browser dev tools |
| All images staged | server:2026.2, postgres:16-alpine, redis:alpine | [ ] |
| Blueprints local only | Mounted from `./blueprints/custom/`, no OCI references | [ ] |

---

## Files Changed

### New Files

| File | Purpose |
|------|---------|
| `basalt-stack/web/authentik/docker-compose.yaml` | Rewritten compose (replaces scaffold) |
| `basalt-stack/web/authentik/db/include.yaml` | Updated Postgres 16 + Redis 7.4 |
| `basalt-stack/web/authentik/.env.example` | Rewritten env template (banner format) |
| `basalt-stack/web/authentik/scripts/gen-cert.sh` | TLS cert generation (wildcard `*.basalt.local` SAN) |
| `basalt-stack/web/authentik/hosts-template.txt` | Client hosts file template |
| `basalt-stack/web/authentik/blueprints/custom/00-system-settings.yaml` | Avatar + brand config (only blueprint — all else via admin UI) |

### Modified Files

| File | Change |
|------|--------|
| `open-webui/backend/apps/web/routers/auths.py` | Add shared-secret validation (`hmac.compare_digest`), replace email-as-password with random password, add null-check for `X-Authentik-Email` |
| `open-webui/backend/config.py` | Remove `t0p-s3cr3t` JWT secret fallback |
| `basalt-stack/web/open-webui/.env` | Add `DEFAULT_USER_ROLE`, `JWT_EXPIRES_IN`, `AUTHENTIK_SHARED_SECRET`, `ENABLE_SIGNUP` |
| `onyx/deployment/docker_compose/.env` | Set `AUTH_TYPE=oidc` + OIDC env vars |
| `CLAUDE.md` | Update port table, architecture diagram, startup sequence, fix Authentik path |
| `docs/basalt-system-design.md` | Update architecture diagram, remove Phase 6 deferred tag |
| `docs/plans/basalt-development-roadmap.md` | Mark Track D SSO items complete |

### Archived Files

| File | Reason |
|------|--------|
| `basalt-stack/web/portal/*` → `basalt-stack/web/portal-archived/` | Replaced by Authentik |
| `todos/022-open-p2-portal-deployment-verification.md` | Superseded by Authentik |

---

## Next After This

- **Phase 7: Network segmentation** — firewall rules to restrict backend port access (primary defense, replacing shared-secret workaround)
- **HTTPS for Onyx OIDC** — apply `custom_cert_oauth_client.patch`, mount CA cert, switch `OPENID_CONFIG_URL` to HTTPS
- **RMF Generator web UI** — build FastAPI app, register as Authentik application, replace placeholder tile

---

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-03-17-authentik-sso-portal-brainstorm.md](../brainstorms/2026-03-17-authentik-sso-portal-brainstorm.md) — Key decisions carried forward: Authentik IS the portal (D1), embedded outpost (D5), self-registration + approval (D6), blueprint YAML (D15). Routing changed from path-based (D13) to subdomain-based after research confirmed path routing not supported.

### Internal References

- Existing Authentik scaffold: `basalt-stack/web/authentik/docker-compose.yaml`
- Open-WebUI header auth: `open-webui/backend/apps/web/routers/auths.py:98-174`
- Onyx OIDC config: `onyx/deployment/docker_compose/env.template:121-136`
- Onyx custom cert patch: `onyx/deployment/docker_compose/custom_cert_oauth_client.patch`
- Onyx auth types: `onyx/backend/onyx/configs/constants.py:252-260`
- Alpine health check fix: `docs/solutions/clickhouse-alpine-healthcheck-fix.md`
- Portal compose (being replaced): `basalt-stack/web/portal/docker-compose.yaml`

### External References

- Authentik proxy provider docs: `https://docs.goauthentik.io/add-secure-apps/providers/proxy/`
- Authentik embedded outpost: `https://docs.goauthentik.io/add-secure-apps/outposts/embedded/`
- Authentik air-gap guide: `https://docs.goauthentik.io/install-config/air-gapped`
- Authentik blueprint structure: `https://docs.goauthentik.io/customize/blueprints/v1/structure/`
- Authentik custom headers: `https://docs.goauthentik.io/add-secure-apps/providers/proxy/custom_headers`
- Authentik 2026.2 release notes: `https://docs.goauthentik.io/releases/2026.2/`
