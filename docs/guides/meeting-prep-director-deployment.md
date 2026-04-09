---
title: "Meeting Prep — Software Director: Basalt Stack Deployment"
date: 2026-03-19
status: completed
category: guide
tags:
  - meeting-prep
  - deployment
  - leadership
  - status-update
aliases:
  - director-meeting-prep
related:
  - "[[basalt-development-roadmap|roadmap]]"
  - "[[deployment-guide-dev|deployment-guide]]"
  - "[[basalt-system-design|system-design]]"
---

# Meeting Prep — Software Director: Basalt Stack Deployment

**Date:** 2026-03-19
**Context:** Status meeting on installing the Basalt architecture and staging containers for sandboxed (air-gapped) deployment.

---

## Director's Question 1: Active Directory Integration

**"Does the stack have the capability of tying into existing Active Directory networks for authentication?"**

### Short Answer

Yes. Authentik natively supports Active Directory and LDAP federation. It is not configured today because our current deployment targets 5-25 users on a standalone air-gapped network, where local Authentik accounts with admin-approval registration are simpler. AD integration is a configuration change, not an architecture change.

### Detail

| Capability | Authentik Support | Effort |
|-----------|-------------------|--------|
| **LDAP Source (AD bind)** | Built-in. Authentik syncs users/groups from AD on a configurable schedule. Users authenticate against AD credentials. | Config-only (Admin UI). No code changes. |
| **Kerberos / SPNEGO** | Supported via LDAP source + browser negotiation. Enables Windows single sign-on for domain-joined machines. | Config + client GPO. |
| **SAML 2.0 Federation** | Authentik can act as both SAML IdP and SP. Can federate with ADFS or Azure AD. | Config-only. |
| **SCIM Provisioning** | Supported for automated user lifecycle (create/disable/delete synced from AD). | Config + SCIM endpoint on AD side. |
| **Hybrid (local + AD)** | Authentik supports multiple authentication sources simultaneously. Local accounts and AD accounts can coexist. | Config-only. |

### Talking Points

- "We chose Authentik specifically because it supports AD/LDAP out of the box. Our current deployment uses local accounts because we're targeting a small standalone air-gapped enclave. Tying into an existing AD is a configuration change in the Authentik admin UI — we add an LDAP source pointing to the AD domain controller, map the group structure, and users authenticate with their existing AD credentials."
- "If the target network has AD, we can integrate during deployment. If it doesn't, our self-registration with admin approval workflow handles the 5-25 user scale."
- "Authentik also supports SAML federation with ADFS, so if the org already has an identity provider, we can federate rather than direct-bind."

### If Asked: "What about CAC/PIV/certificate-based auth?"

- Authentik supports client certificate authentication via its proxy provider.
- This would require mounting the DoD CA chain into the Authentik container and configuring mutual TLS.
- Not implemented today, but architecturally feasible. Flag as a Phase 7+ hardening item.

---

## Director's Question 2: Air-Gap Container Staging & Migration

**"How do we stage and migrate the containers to an offline deployment?"**

### Short Answer

We use `docker save` / `docker load` to export container images as `.tar` files on a connected machine, transfer them via approved media (USB, DVD, cross-domain solution), and import them on the air-gapped target. We have a staging script that automates this for each stack.

### The Process (3 Phases)

```
Phase A: STAGING (internet-connected machine)
─────────────────────────────────────────────
1. Pull all container images from registries
2. Export each image to a .tar file (docker save)
3. Record image digests for integrity verification
4. Package model weights (GPT-OSS:20B, ~40 GB safetensors)
5. Package Python wheels for RMF tool (pip download)

Phase B: TRANSFER (approved media)
──────────────────────────────────
6. Copy .tar files + model weights to transfer media
7. Verify file integrity (checksums / digests)
8. Transfer through approved cross-domain solution or removable media

Phase C: DEPLOYMENT (air-gapped target)
───────────────────────────────────────
9.  Import images into Docker (docker load)
10. Verify digests match staging digests
11. Deploy compose stacks (docker compose up -d)
12. No network calls — all telemetry disabled, no CDN, no update checks
```

### Image Inventory

| Stack | Images | Approx Size | Staging Script |
|-------|--------|-------------|----------------|
| **vLLM** | `vllm/vllm-openai:v0.10.2` | ~34 GB | Manual (one image) |
| **Langfuse** | langfuse, langfuse-worker, clickhouse, minio, postgres, redis | ~3 GB | Manual |
| **LiteLLM** | litellm-database, postgres, redis | ~2 GB | Manual |
| **Authentik** | server:2026.2.1, postgres:16-alpine, redis:7.4-alpine | ~1.5 GB | `stage-images.sh pull/save/load/verify` |
| **Open-WebUI** | open-webui:main | ~2 GB | Manual |
| **Onyx** | 8 images (backend, web, model-server, vespa, postgres, redis, nginx, minio) | ~10 GB | Manual |
| **Model Weights** | `openai/gpt-oss-20b` (safetensors) | ~40 GB | HuggingFace download |
| **Total** | ~15 distinct images + model weights | **~90 GB** | |

### Talking Points

- "We have a proven staging script pattern (`stage-images.sh`) with pull/save/load/verify subcommands. The Authentik stack already has this scripted. We'll extend the same pattern to cover all 6 stacks before the air-gap transfer."
- "Total transfer payload is approximately 90 GB — about 50 GB of container images plus 40 GB of model weights."
- "Every service has telemetry disabled at the configuration level. We've verified via browser DevTools that no service makes outbound network requests. This is a hard requirement for the air-gapped environment."
- "The deployment guide documents the exact startup order and verification steps. A qualified operator can bring up the full stack in about 35-40 minutes from imported images."

### If Asked: "How do we handle updates on the air-gapped network?"

- Same process in reverse: pull updated images on connected machine, stage, transfer, load, redeploy.
- Authentik update checks are disabled (`AUTHENTIK_DISABLE_UPDATE_CHECK=true`).
- All image tags are pinned (no `:latest` tags that could drift). Updates are deliberate, not automatic.
- Configuration (compose files, `.env`, blueprints) is version-controlled in this repo.

### If Asked: "What about data persistence across redeployments?"

- All services use named Docker volumes for persistent data (databases, model caches, Redis state).
- `docker compose down` preserves volumes. Only `docker compose down -v` deletes them.
- Postgres backup strategy is a Track D hardening item — not yet implemented but planned.

---

## Director's Question 3: Integrating Custom Tools (RMF Generator) into Authentik

**"How do I plan on tying in custom Basalt tools, such as the Document Generation feature, into the Authentik dashboard?"**

### Short Answer

New tools are registered in Authentik as applications. The subdomain `rmf.basalt.local` is already reserved in our hosts template. When the RMF Generator gets a web UI (planned as a FastAPI app), we create a proxy provider in Authentik pointing to it, and it appears as a tile in the application launcher — fully SSO-integrated with one click.

### Integration Path (3 Levels)

| Level | What | Effort | User Experience |
|-------|------|--------|-----------------|
| **1. Bookmark tile** (now) | Register as an Authentik application with a launch URL pointing to docs or a placeholder page | 5 minutes (Admin UI) | Tile appears in launcher, links to documentation |
| **2. Proxied web app** (after web UI built) | Deploy FastAPI app on port X, create proxy provider (`rmf.basalt.local` → `host.docker.internal:X`), bind to outpost | 30 minutes (Admin UI + compose) | SSO-protected access via `https://rmf.basalt.local`, user identity passed via headers |
| **3. Full OIDC integration** (if needed) | App handles its own OIDC flow with Authentik as provider | Hours (code change in app) | Native login redirect, token-based sessions |

### The Pattern We've Already Proven

We've integrated two applications using two different auth patterns:

| App | Auth Pattern | How It Works |
|-----|-------------|--------------|
| **Open-WebUI** | Forward-auth proxy + header injection | Authentik proxy validates session, injects `X-Authentik-Email` + shared secret. App trusts the header. |
| **Onyx** | Native OIDC | App redirects to Authentik for login, handles OAuth2 callback, manages its own session. Proxy handles routing. |

The RMF Generator would most likely use **Pattern 1** (forward-auth proxy) since it's simpler and doesn't require OIDC code in the app itself. Authentik handles authentication; the app just reads the `X-Authentik-Email` header to know who the user is.

### Talking Points

- "The subdomain `rmf.basalt.local` is already reserved in our hosts file template. When the RMF tool has a web interface, integration is a 30-minute admin UI task — not an architecture change."
- "We've proven two integration patterns: forward-auth proxy for Open-WebUI and native OIDC for Onyx. Any new tool can use either pattern depending on complexity. Simple tools use the proxy pattern — zero auth code needed in the app."
- "Today we can register the RMF tool as a bookmark tile in the Authentik launcher. Users see it alongside Open-WebUI and Onyx in the app launcher dashboard."
- "The Authentik application launcher IS our portal. Every tool we build shows up there automatically as a clickable tile. No separate portal to maintain."

---

## Anticipated Additional Questions

### Architecture & Scale

**"How many containers / services is this?"**
- 6 Docker Compose stacks, ~25 containers total on a single host.
- Services: vLLM (GPU inference), LiteLLM (API gateway), Langfuse (observability), Authentik (SSO), Open-WebUI (chat UI), Onyx (RAG platform).

**"Can this scale beyond a single host?"**
- Current architecture is single-host by design (air-gapped enclave, one GPU).
- vLLM supports `tensor_parallel_size > 1` for multi-GPU if the hardware scales.
- LiteLLM supports multiple vLLM backends for load balancing.
- Authentik and Onyx both support horizontal scaling with external Postgres/Redis.
- Scaling is a configuration change, not a rewrite.

**"What GPU do we need?"**
- **Dev box (on the bench today)**: NVIDIA RTX A4000 (20 GB VRAM). Forces 4-bit quantization, `--max-num-seqs 2`, and `--max-model-len 8192`. Single-stream development only.
- **Prod target (procurement pending)**: NVIDIA RTX A6000 (48 GB VRAM). GPT-OSS:20B at MXFP4 quantization uses ~16 GB VRAM, leaving ~32 GB for KV cache and concurrent requests.
- Minimum viable for a *production* deployment: any NVIDIA GPU with 24+ GB VRAM (RTX 4090, A5000, etc.). The A4000 dev box is below that bar — sufficient for feature work, not for the director demo.
- The 120B model variant would require multi-GPU (not in scope for MVP).

### Security & Compliance

**"What's the security posture?"**

| Layer | Status |
|-------|--------|
| **Authentication** | Authentik SSO — centralized login, admin-approval registration, 24h JWT expiry |
| **Authorization** | Role-based (admin/user) in Open-WebUI, OIDC-scoped in Onyx |
| **Transport** | TLS (self-signed wildcard `*.basalt.local`) for all user-facing traffic |
| **Secrets** | All generated via `openssl rand -hex 32`, stored in `.env` files (gitignored) |
| **Air-gap** | All telemetry disabled, no CDN dependencies, no update checks, all assets pre-staged |
| **Header spoofing** | Shared-secret validation (`hmac.compare_digest`) prevents direct-port attacks |
| **Known debt** | Internal OIDC uses HTTP (not HTTPS) between containers — Phase 7 fix. Dev secrets need rotation before production. |

**"What compliance frameworks are you targeting?"**
- Awareness: OWASP LLMSVS Level 2 + NIST COSAiS.
- Current coverage: ~4 of 13 LLMSVS categories. Full audit is a Track D item.
- The RMF Generator itself produces NIST 800-53 Rev 5 System Security Plan documents — so the tool helps with compliance documentation.

**"Is the code auditable?"**
- All configuration is version-controlled (compose files, env templates, blueprints).
- Authentik configuration can be exported as blueprint YAML for reproducibility.
- All open-source components: vLLM, LiteLLM, Langfuse, Authentik, Open-WebUI, Onyx.

### Operations & Maintenance

**"What's the operational burden?"**

| Task | Frequency | Effort |
|------|-----------|--------|
| User approval | Per request | 30 seconds (Admin UI toggle) |
| Service restart | Rare (auto-restart policy) | `docker compose restart` per stack |
| Image updates | Quarterly or as needed | Stage/transfer/load cycle (~2 hours) |
| Secret rotation | Before production + annually | `openssl rand -hex 32` per secret |
| Log management | Automated | JSON log rotation: 50 MB x 6 files per service |
| Backup | TBD (Track D) | Postgres dumps for Langfuse, LiteLLM, Authentik, Onyx |

**"What if Authentik goes down?"**
- Existing Open-WebUI JWTs remain valid for up to 24 hours (users already logged in keep working).
- Onyx sessions persist until OIDC token expiry.
- No new logins possible until Authentik recovers.
- Authentik has `unless-stopped` restart policy and persistent Redis/Postgres volumes — survives container restarts and host reboots.

**"What's the rollback plan?"**
- Each integration phase has a documented rollback procedure in the plan.
- Open-WebUI: restore `.env.pre-authentik`, `git checkout` the auth code, restart.
- Onyx: restore `.env.pre-authentik`, set `AUTH_TYPE=disabled`, restart.
- Authentik: `docker compose down`, restart the archived nginx portal if needed.
- All rollback procedures are tested and documented.

### Licensing

**"Any licensing concerns?"**

| Component | License | Commercial Use |
|-----------|---------|----------------|
| vLLM | Apache 2.0 | Yes |
| GPT-OSS:20B | Apache 2.0 (MIT for weights) | Yes |
| LiteLLM | MIT | Yes |
| Langfuse | MIT (EE features optional) | Yes |
| Authentik | MIT (Enterprise features optional) | Yes |
| Open-WebUI | MIT | Yes |
| Onyx | MIT (EE features optional) | Yes |

All components are permissively licensed. Enterprise features (where they exist) are disabled — we use only the open-source editions.

---

## Key Documents to Reference

If the director wants to see documentation:

| Document | Location | What It Shows |
|----------|----------|---------------|
| **Deployment Guide** | `docs/guides/deployment-guide-dev.md` | Step-by-step startup, 8 sections, troubleshooting |
| **Architecture Diagram** | `CLAUDE.md` (top section) | Authentik → services → inference pipeline |
| **System Design** | `docs/basalt-system-design.md` | Container inventory, GPU allocation, data models |
| **SSO Integration Plan** | `docs/plans/2026-03-17-001-feat-authentik-sso-portal-integration-plan.md` | 3-phase plan with security findings |
| **Development Roadmap** | `docs/plans/basalt-development-roadmap.md` | Tracks A-D, dependency graph, cross-cutting findings |
| **Integration Log** | `docs/logs/authentik-sso-integration-log.md` | Phase-by-phase decisions, runtime steps remaining |

---

## One-Slide Summary (if needed)

```
BASALT STACK — Self-Hosted AI Infrastructure
─────────────────────────────────────────────
WHAT:  GPT-OSS:20B LLM on air-gapped network with SSO portal
WHERE: Single host, Windows 11 + WSL2
       Dev: NVIDIA A4000 20GB (current) | Prod target: NVIDIA A6000 48GB (pending)
HOW:   6 Docker Compose stacks, ~25 containers, all open-source

        Browser → Authentik SSO (*.basalt.local)
                    ├── Open-WebUI  (chat)
                    ├── Onyx        (RAG)
                    └── RMF Tool    (doc gen, planned)
                          │
                    LiteLLM Gateway → Langfuse (traces)
                          │
                    vLLM + GPT-OSS:20B (GPU)

AUTH:   Authentik — local accounts + AD/LDAP ready
AIRGAP: docker save/load, pinned tags, telemetry off
STATUS: Code-complete, pending deployment testing
```
