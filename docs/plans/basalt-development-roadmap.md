---
title: "Basalt Development Roadmap"
type: roadmap
status: active
date: 2026-02-17
model-target: gpt-oss:20b (MVP)
hardware: NVIDIA RTX A6000, 48GB VRAM
---

# Basalt Development Roadmap

**PURPOSE**: Phased plan from current state to production-ready air-gapped LLM platform.

**MODEL**: `gpt-oss:20b` for MVP. `gpt-oss:120b` requires multi-GPU hardware (does not fit single A6000).

**MVP GOAL**: User opens Onyx or Open-WebUI, asks a question, gets a response from vLLM via LiteLLM, with observability in Langfuse.

**CONTEXT**: Phases 1-4 execute on a development machine with internet access. Phase 5 stages artifacts for transfer to the air-gapped target. Phases 6-7 enhance the deployed stack.

---

## Phase Overview

```
DEVELOPMENT (connected machine)
  Phase 1 → Phase 2 → Phase 3 → Phase 4
  Fix Bugs   Inference   App Layer  MVP Test
                                      |
                                 ── MVP LINE ──
                                      |
DEPLOYMENT (air-gapped target)
  Phase 5 → Phase 6 → Phase 7
  Air-Gap    Authentik   Hardening
  Staging    SSO
```

---

## Phase 1: Fix Critical Infrastructure Bugs

**Goal**: All compose files parse and start without errors.

**Reference**: Architecture review items #1-6, #8-12

### 1.1 Langfuse Fixes

| Fix | File |
|-----|------|
| Set `IMAGE_REPO_BASE=` (empty) | `langfuse/.env` |
| Add `POSTGRES_IMAGE=postgres` | `langfuse/.env` |
| Fix duplicate `POSTGRES_TAG` assignment | `langfuse/.env` |
| Fix `restart: alway` → `restart: always` | `langfuse/docker-compose.yaml` |
| Fix `LANGFUS_WORKER_TAG` → `LANGFUSE_WORKER_TAG` | `langfuse/docker-compose.yaml` |
| Fix `LANGFUS_WEB_TAG` → `LANGFUSE_WEB_TAG` | `langfuse/docker-compose.yaml` |
| Generate and add `NEXTAUTH_SECRET` | `langfuse/.env` |
| Generate and add `ENCRYPTION_KEY` | `langfuse/.env` |
| Remove misleading `# should be http://` comment | `langfuse/docker-compose.yaml` |
| Remove deprecated `version: '3'` | `langfuse/docker-compose.yaml` |

### 1.2 LiteLLM Fixes

| Fix | File |
|-----|------|
| Set `IMAGE_REPO_BASE=` (empty) | `litellm/.env` |
| Add `POSTGRES_IMAGE=postgres` | `litellm/.env` |
| Fix duplicate `POSTGRES_TAG` assignment | `litellm/.env` |
| Fix broken `depends_on` YAML structure | `litellm/docker-compose.yaml` |
| Generate and add `LITELLM_MASTER_KEY` | `litellm/.env` |
| Generate and add `REDIS_AUTH` | `litellm/.env` |
| Make `OPENAI_API_KEY`/`COHERE_API_KEY` optional (`:-`) | `litellm/docker-compose.yaml` |
| Fix `LANGFUSE_AUTH` base64 (use `pk:sk` not `sk:sk`) | `litellm/.env` |
| Add `extra_hosts: ["host.docker.internal:host-gateway"]` | `litellm/docker-compose.yaml` |
| Hardcode internal port in command (`--port 8000`) | `litellm/docker-compose.yaml` |
| Remove deprecated `version: '3'` | `litellm/docker-compose.yaml` |

### 1.3 Create Missing Files

| File | Contents |
|------|----------|
| `litellm/litellm-config.yaml` | vLLM model routing via `host.docker.internal:8001` |
| `vllm/docker-compose.yaml` | vLLM service with GPU, health check, air-gap env vars |
| `vllm/.env` | Image tag, port, model path |
| `onyx/.env` | From `env.template`, configured for local deployment |
| `open-webui/.env` | From `.env.example`, port 3002, fix image placeholders |

---

## Phase 2: Core Inference Pipeline

**Goal**: `curl` to LiteLLM returns a chat completion from vLLM. Trace visible in Langfuse.

### 2.1 Start Services

```bash
# Start vLLM (2-5 min model load)
cd basalt-stack/inference/vllm && docker compose up -d
# Verify: curl http://localhost:8001/v1/models

# Start Langfuse
cd basalt-stack/inference/langfuse && docker compose up -d
# Verify: http://localhost:3001

# Start LiteLLM (after vLLM healthy)
cd basalt-stack/inference/litellm && docker compose up -d
# Verify: curl http://localhost:8000/v1/models
```

### 2.2 Validate

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{"model": "gpt-oss-20b", "messages": [{"role": "user", "content": "Hello"}]}'
# Confirm trace appears in Langfuse at http://localhost:3001
```

**Done when**: LiteLLM returns a valid completion and the trace is in Langfuse.

### Phase 2 Notes (2026-02-17) — In Progress

#### Hardware Adaptation

The roadmap targets an NVIDIA RTX A6000 (48GB VRAM), but Phase 2 development is executing on an **NVIDIA RTX 4000 ADA** (20GB VRAM). This works because gpt-oss-20b is a Mixture-of-Experts model (21B total parameters, 3.6B active) with MXFP4 quantization, requiring approximately 14GB VRAM at runtime. The `--gpu-memory-utilization` is set to `0.85` and `--max-num-seqs` reduced from 128 to 64 to fit comfortably within the 20GB budget.

This adaptation is development-only. Phase 5 deployment targets the A6000 as planned.

#### vLLM Version Update

The original roadmap specified vLLM `v0.8.4`. gpt-oss-20b requires **vLLM v0.10.2+** for MoE architecture and MXFP4 quantization support. The `VLLM_TAG` in `basalt-stack/inference/vllm/.env` has been updated accordingly.

Additional vLLM changes:
- Model source switched to HuggingFace auto-download (`openai/gpt-oss-20b`) for development convenience. Air-gap mode (offline env vars) will be re-enabled in Phase 5.
- Added `--async-scheduling` flag (recommended for gpt-oss-20b MoE inference).
- Added `vllm-hf-cache` named volume for persistent model cache across container restarts.
- Increased health check `start_period` from 300s to 600s (first-run model download).

> **Phase 5 impact**: The image tag in Section 5.1 should be updated from `v0.8.4` to `v0.10.2` when Phase 5 planning begins.

#### Langfuse Infrastructure Fixes

Two bugs were discovered and fixed during Langfuse bring-up:
1. **Alpine IPv6 resolution**: ClickHouse health check used `localhost`, which Alpine resolves to `::1` (IPv6) first. IPv6 is disabled in Docker containers, so the health check failed. Fixed by using `127.0.0.1` explicitly.
2. **ClickHouse entrypoint dual-start bug**: The Alpine ClickHouse entrypoint starts a temporary server to provision users/databases via environment variables, then starts the main server. On fast systems the port is still held by the temporary process. Fixed by provisioning the ClickHouse user via an XML config file (`clickhouse-users.xml`) mounted to `/etc/clickhouse-server/users.d/` instead.

See `docs/solutions/clickhouse-alpine-healthcheck-fix.md` for full details.

#### LiteLLM Langfuse Integration

The `litellm-config.yaml` was missing `callbacks: ["langfuse"]` in `litellm_settings`, which meant no traces were being sent to Langfuse. This has been added.

#### Current Status (2026-02-17 EOD)

| Component | Status |
|-----------|--------|
| Docker networks (proxy, inference-endpoint) | Created |
| NVIDIA Container Toolkit | Configured in Docker Desktop |
| Langfuse (6 containers) | Running and healthy |
| LiteLLM | Image downloading (near complete) |
| vLLM (v0.10.2) | Image downloading (~15GB) |
| gpt-oss-20b model weights | Pending (auto-download on vLLM first start) |

---

## Phase 3: Application Layer

**Goal**: Users chat via Onyx and Open-WebUI, routed through the inference pipeline.

### 3.1 Start Onyx

```bash
cd onyx/deployment/docker_compose && docker compose up -d
# Verify: http://localhost:3000
```

Configure LLM connection (Onyx Admin UI → LLM settings after first login):
- API base: `http://host.docker.internal:8000/v1`
- Model: `gpt-oss-20b`
- API key: value of `$LITELLM_MASTER_KEY`

### 3.2 Start Open-WebUI

```bash
cd basalt-stack/web/open-webui && docker compose up -d
# Verify: http://localhost:3002
```

Configure LLM connection (Open-WebUI Admin → Settings → Connections):
- OpenAI API base: `http://host.docker.internal:8000/v1`
- API key: value of `$LITELLM_MASTER_KEY`

### 3.3 Validate

- Chat in Open-WebUI → response → trace in Langfuse
- Chat in Onyx → response → trace in Langfuse
- Upload document in Onyx → RAG query → augmented response

**Done when**: Both UIs produce LLM responses through the inference pipeline.

---

## Phase 4: MVP Validation

**Goal**: Prove the stack works end-to-end. Document baseline performance.

### 4.1 Functional Tests

| Test | Expected Result |
|------|----------------|
| Open-WebUI chat | Response from gpt-oss-20b |
| Onyx chat | Response from gpt-oss-20b |
| Onyx document upload + query | RAG-augmented response |
| Langfuse traces | All interactions logged |
| vLLM health check | `/health` returns 200 |
| LiteLLM model list | Returns `gpt-oss-20b` |
| Service restart recovery | All services restart cleanly |

### 4.2 Resource Baseline

Document GPU VRAM usage, CPU/RAM per service, disk usage, and response latency (time to first token, total generation time).

**Done when**: Stack demonstrated end-to-end on development machine.

---

## ── MVP LINE ──────────────────────────────────────────────

Above: the stack proves air-gapped LLM inference with RAG, observability, and dual UIs.
Below: deployment to target hardware, access control, and production hardening.

---

## Phase 5: Air-Gap Preparation & Deployment

**Goal**: Stage all external dependencies and deploy to the air-gapped target host.

**Prerequisites**: Phases 1-4 validated on development machine.

### 5.1 Stage Docker Images

Pull and save all images. Include Authentik images for Phase 6 — once air-gapped, no new images can be pulled.

| Image | Tag | Service |
|-------|-----|---------|
| `vllm/vllm-openai` | `v0.8.4` | vLLM |
| `ghcr.io/berriai/litellm-database` | `main-v1.41.14` | LiteLLM |
| `langfuse/langfuse` | `3.40.0` | Langfuse web |
| `langfuse/langfuse-worker` | `3.40.0` | Langfuse worker |
| `redis` | `alpine` | Cache (multiple services) |
| `postgres` | `15.2-alpine` | Database (multiple services) |
| `clickhouse/clickhouse-server` | `25.2.1.3085-alpine` | Langfuse analytics |
| `minio/minio` | `RELEASE.2025-02-28T09-55-16Z` | Langfuse storage |
| `onyxdotapp/onyx-backend` | `latest` | Onyx |
| `onyxdotapp/onyx-web-server` | `latest` | Onyx |
| `onyxdotapp/onyx-model-server` | `latest` | Onyx embeddings |
| `vespaengine/vespa` | `8.526.15` | Onyx search |
| `nginx` | `1.23.4-alpine` | Onyx proxy |
| `ghcr.io/open-webui/open-webui` | `main` | Open-WebUI |
| `ghcr.io/goauthentik/server` | TBD | Authentik (Phase 6) |
| `ghcr.io/goauthentik/proxy` | TBD | Authentik outpost (Phase 6) |

```bash
docker save [all images] -o basalt-images.tar
```

### 5.2 Stage Model Weights

```bash
huggingface-cli download <org>/gpt-oss-20b --local-dir /models/gpt-oss-20b
```

**Open item**: Confirm gpt-oss-20b is available in safetensors format.

### 5.3 Stage Onyx Embedding Cache

Run Onyx model servers once on connected machine to cache HuggingFace embedding models. Export the Docker volume.

### 5.4 Stage NVIDIA Container Toolkit

Pre-download `nvidia-container-toolkit` and `libnvidia-container1` `.deb` packages for offline WSL2 installation.

### 5.5 Transfer & Deploy

Transfer to air-gapped host:
- `basalt-images.tar` → `docker load -i basalt-images.tar`
- `/models/` directory (store on WSL2 filesystem, NOT `/mnt/c/`)
- Onyx HuggingFace cache volume
- NVIDIA toolkit `.deb` packages
- The `basalt-stack-v1.0` repository

Re-run Phases 2-4 validation on target hardware.

**Done when**: Full stack operational on air-gapped target.

---

## Phase 6: Authentik SSO Integration

**Goal**: Centralized authentication and reverse proxy via Authentik.

### Why Post-MVP

| Reason | Detail |
|--------|--------|
| **MVP proves inference first** | Core value is "LLM works air-gapped." Auth is not part of that proof. |
| **Auth masks infra bugs** | SSO failures are indistinguishable from service failures during debugging. |
| **Services have built-in auth** | Onyx, Open-WebUI, Langfuse all work standalone for dev/demo. |
| **Own dependencies** | Authentik needs PostgreSQL + Redis + container. More surface area. |

### Why Inevitable

| Reason | Detail |
|--------|--------|
| **Federal compliance** | NIST AC family requires centralized identity management. |
| **System description mandates it** | "User logs into Authentik unified interface dashboard." |
| **User experience** | Single login across all Basalt applications. |
| **TLS termination** | HTTPS for all services via one certificate. |

Detailed integration planning (compose config, OIDC setup, reverse proxy routes) happens at Phase 6 start.

---

## Phase 7: Production Hardening

**Goal**: Security compliance and production-grade configuration.

### 7.1 Credential Rotation

Rotate all default passwords: Postgres, Redis, MinIO, API keys, Langfuse secrets, LiteLLM master key. Use `openssl rand -hex 32`.

### 7.2 Encryption

- TLS on Authentik reverse proxy (self-signed or internal CA)
- Evaluate disk encryption for model weights and database volumes
- MinIO server-side encryption

### 7.3 Compliance Audit

Walk through `basalt-compliance-matrix.md`. Address all DEFERRED items.

### 7.4 Monitoring

Health check dashboards, Langfuse analytics, container resource monitoring, disk space alerts.

### 7.5 Backup

Database backup procedures, model weight integrity verification, config backup to portable media.
