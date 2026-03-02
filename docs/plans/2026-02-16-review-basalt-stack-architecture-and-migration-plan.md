---
title: "Review: Basalt Stack Architecture & Migration Plan"
type: review
status: active
date: 2026-02-16
---

# Basalt Stack Architecture & Migration Plan Review

## Overview

This document reviews the Basalt Stack architecture and `LACI-Basalt-Migration.md` deployment plan for a **fully air-gapped**, containerized self-hosted LLM platform. Target hardware is Windows 11 with an **NVIDIA RTX A6000 (48GB VRAM)**, Docker Desktop with WSL2.

The stack consists of 5 services: **vLLM** (containerized LLM inference server), **LiteLLM** (proxy/gateway), **Langfuse** (observability), **Onyx** (RAG platform), and **Open-WebUI** (chat interface), orchestrated via Docker Compose.

### Architecture Decisions (Confirmed)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **LLM inference engine** | vLLM (Docker container) | Higher throughput via continuous batching, native OpenAI-compatible API, better for multi-consumer workloads. Replaces Ollama. |
| **vLLM compose location** | `basalt-stack/inference/vllm/` | Follows existing `inference/<service>/` pattern. GPU config isolated from other services. Independent lifecycle from LiteLLM. |
| **Inter-service networking** | Host-routed (`host.docker.internal`) | Simpler, matches migration plan, each service exposes ports on host |
| **Network isolation** | Fully air-gapped | No internet access at any point. Requires private registry, pre-loaded images, pre-downloaded models |
| **GPU** | NVIDIA RTX A6000 (48GB VRAM) | Ample VRAM for gpt-oss-20b + Onyx embedding models simultaneously |
| **Model format** | TBD (HuggingFace safetensors recommended) | vLLM works best with safetensors. GGUF support is experimental and slow in vLLM. AWQ/GPTQ for quantized models. |

---

## Severity Legend

- **CRITICAL** - Will prevent deployment or cause runtime failures
- **HIGH** - Significant functionality or security issue
- **MEDIUM** - Should be fixed but won't block deployment
- **LOW** - Improvement / best practice suggestion

---

## 1. CRITICAL: Broken YAML in LiteLLM Docker Compose

**File**: `basalt-stack/inference/litellm/docker-compose.yaml:11-12`

The `depends_on` key is **missing entirely**. Lines 11-12 are orphaned YAML keys that Docker Compose will either reject or silently ignore:

```yaml
# CURRENT (broken)
services:
  litellm:
    ...
    command: --port ${LITELLM_PORT:?error} --config config.yaml
    postgres:                          # <-- Not under depends_on!
      condition: service_healthy       # <-- Orphaned condition
    environment:
      ...
```

**Fix**:
```yaml
    command: --port 8000 --config config.yaml
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      ...
```

**Impact**: LiteLLM starts before Postgres is ready, causing database connection failures on first boot.

---

## 2. CRITICAL: Missing `LITELLM_MASTER_KEY` in .env

**File**: `basalt-stack/inference/litellm/.env`

The compose file references `${LITELLM_MASTER_KEY:?error}` (line 16), but **this variable is never defined** in the `.env` file. Docker Compose will refuse to start with an error.

The migration plan (Phase 3.1) correctly says to add it:
```env
LITELLM_MASTER_KEY=sk-<generate: openssl rand -hex 32>
```

But the actual file is missing it entirely.

---

## 3. CRITICAL: `IMAGE_REPO_BASE` Placeholder Breaks All Image Pulls

**Files**: Both `langfuse/.env:5` and `litellm/.env:5`

```env
IMAGE_REPO_BASE="{INSERT PUBLIC REPO HERE}"
```

This causes image names like `{INSERT PUBLIC REPO HERE}langfuse/langfuse:3.40.0`, which Docker will fail to pull.

**Fix** (for local deployment): Set to empty string:
```env
IMAGE_REPO_BASE=
```

**For isolated/air-gapped networks**: Set to your private registry prefix:
```env
IMAGE_REPO_BASE=registry.internal.corp:5000/
```

> **Note for isolated networks**: The migration plan doesn't address the need for a **private Docker registry** to serve images when internet access is unavailable. This is a fundamental prerequisite for air-gapped deployment.

---

## 4. CRITICAL: `POSTGRES_IMAGE` Variable Never Defined

**Files**: Both `langfuse/.env:19` and `litellm/.env:13`

```env
POSTGRES_TAG="${IMAGE_REPO_BASE}postgres"    # <-- Bug: sets POSTGRES_TAG, not POSTGRES_IMAGE
POSTGRES_TAG="15.2-alpine"                   # <-- Overrides the line above
```

The compose files reference `${POSTGRES_IMAGE}:${POSTGRES_TAG}`, but `POSTGRES_IMAGE` is never defined. The first line sets `POSTGRES_TAG` (not `POSTGRES_IMAGE`) to the repo string, then the second line overwrites it with the actual tag.

**Fix**:
```env
POSTGRES_IMAGE=postgres
POSTGRES_TAG=15.2-alpine
```

---

## 5. CRITICAL: `litellm-config.yaml` Does Not Exist

The LiteLLM compose file mounts `./litellm-config.yaml:/app/config.yaml` (line 9), but **this file does not exist** on disk. Docker Compose will either create an empty directory mount or fail.

The migration plan (Phase 3.2) correctly documents creating this file, but it hasn't been done yet.

---

## 6. CRITICAL: Required API Keys Will Block LiteLLM Startup

**File**: `basalt-stack/inference/litellm/docker-compose.yaml:14-15`

```yaml
OPENAI_API_KEY: ${OPENAI_API_KEY:?error}
COHERE_API_KEY: ${COHERE_API_KEY:?error}
```

Both are marked `?error` (required), but for a vLLM-only deployment, neither OpenAI nor Cohere keys are needed. The `.env` file has dummy values (`sk-examplekey`) which will fail validation if LiteLLM tries to use them.

**Fix**: Change to optional with empty defaults:
```yaml
OPENAI_API_KEY: ${OPENAI_API_KEY:-}
COHERE_API_KEY: ${COHERE_API_KEY:-}
```

---

## 7. HIGH: Docker Networks Declared But Not Connected to Services

### Langfuse (`langfuse/docker-compose.yaml:160-165`)

Both `proxy` and `inference-endpoint` networks are declared as external, but **no service** has a `networks:` key. All Langfuse services run only on the default compose network, making them unreachable from LiteLLM or Onyx via the shared networks.

**Fix**: Add network attachments:
```yaml
services:
  langfuse-web:
    networks:
      - default
      - inference-endpoint    # So LiteLLM can reach it
```

### LiteLLM (`litellm/docker-compose.yaml:67-71`)

`proxy` network is declared but unused. Only `litellm` service connects to `inference-endpoint` (line 30). Redis and Postgres stay on default (which is correct).

### Onyx (`onyx/deployment/docker_compose/docker-compose.yml`)

**No external networks declared at all.** The architecture diagram shows Onyx connecting to both `proxy` and `inference-endpoint`, but the compose file has no network configuration for cross-stack communication.

### Impact & Resolution

**Decision**: Use **host-routing** (approach B). Services communicate via `host.docker.internal` with ports exposed on the host. This is simpler and matches the migration plan's intent.

**Action items**:
1. Remove unused `proxy` and `inference-endpoint` network declarations from compose files (or keep for future use but don't rely on them)
2. Ensure all services that need cross-stack communication have `extra_hosts: ["host.docker.internal:host-gateway"]`
3. Update the architecture diagram in `CLAUDE.md` to show host-routed topology instead of Docker networks
4. The `docker network create proxy` and `docker network create inference-endpoint` commands in the startup sequence become optional (only needed if Open-WebUI uses the proxy network)

---

## 8. HIGH: Langfuse Typos Will Cause Container Failures

**File**: `basalt-stack/inference/langfuse/docker-compose.yaml`

| Line | Current | Correct | Impact |
|------|---------|---------|--------|
| 5 | `restart: alway` | `restart: always` | Redis won't auto-restart on crash |
| 33 | `${LANGFUS_WORKER_TAG}` | `${LANGFUSE_WORKER_TAG}` | Worker image tag resolves to empty, pulling `:` which fails |
| 87 | `${LANGFUS_WEB_TAG}` | `${LANGFUSE_WEB_TAG}` | Web image tag same issue |

The `.env` file defines `LANGFUSE_WORKER_TAG` (correct spelling), so the misspelled compose references will resolve to empty strings.

---

## 9. HIGH: Missing `REDIS_AUTH` in LiteLLM .env

**File**: `basalt-stack/inference/litellm/.env:25`

```env
REDIS_AUTH="" # openssl rand -hex 32
```

Empty string, but compose has `REDIS_AUTH:?error` (required). This will fail with "error" on `docker compose up`.

---

## 10. HIGH: Missing `NEXTAUTH_SECRET` and `ENCRYPTION_KEY` in Langfuse .env

**File**: `basalt-stack/inference/langfuse/.env`

The compose file requires both (`?error`), but the `.env` file doesn't define either. The migration plan correctly identifies this but these secrets haven't been generated.

---

## 11. HIGH: Open-WebUI Port Conflict

**File**: `basalt-stack/web/open-webui/.env.example:15`

```env
OPEN_WEBUI_PORT_HTTP=3000
```

This conflicts with **Onyx** (also port 3000). The migration plan says to change this to 3002, but the `.env.example` still shows 3000.

Additionally, Open-WebUI's `.env.example` has two more placeholders:
```env
DOCKER_IMAGE_REPO="{INSERT PUBLIC IMAGE REPO HERE}"
OPENWEBUI_IMAGE="{INSERT PUBLIC IMAGE HERE}"
```

The correct values should be:
```env
DOCKER_IMAGE_REPO=
OPENWEBUI_IMAGE=ghcr.io/open-webui/open-webui:main
```

---

## 12. HIGH: LiteLLM Command Port Mismatch Risk

**File**: `basalt-stack/inference/litellm/docker-compose.yaml:10`

```yaml
command: --port ${LITELLM_PORT:?error} --config config.yaml
```

The internal port is set dynamically to `${LITELLM_PORT}` (8000), but the container port mapping is `${LITELLM_PORT}:8000` (hardcoded 8000 on the container side). If someone changes `LITELLM_PORT` to something other than 8000, LiteLLM will listen on a different port than what's mapped.

**Fix**: Hardcode the internal port:
```yaml
command: --port 8000 --config config.yaml
ports:
  - ${LITELLM_PORT:?error}:8000
```

---

## 13. MEDIUM: Security Concerns

### Hardcoded/Default Credentials Across Stack

| Service | Credential | Value | File |
|---------|-----------|-------|------|
| Langfuse Postgres | password | `postgres` | langfuse/.env:27 |
| Langfuse MinIO | password | `miniosecret` | langfuse/docker-compose.yaml:138 |
| Langfuse ClickHouse | password | `clickhouse` | langfuse/docker-compose.yaml:119 |
| Langfuse User | password | `password` | langfuse/.env:46 |
| Langfuse API Keys | public/secret | `pk-examplekey`/`sk-examplekey` | langfuse/.env:42-43 |
| LiteLLM Postgres | password | `postgres` | litellm/.env:21 |
| LiteLLM API Keys | OpenAI/Cohere | `sk-examplekey` | litellm/.env:33-34 |
| Onyx Postgres | password | `password` | env.template:42 |
| Onyx MinIO | password | `minioadmin` | env.template:59 |

For local development, this is acceptable. For isolated network deployment, **all passwords should be rotated to generated values** before deployment, especially if the network has other users.

### Missing `ENCRYPTION_KEY_SECRET` in Onyx

`env.template:18` has a comment "Recommend to set this for security" but it's commented out. This should be set for any non-trivial deployment.

---

## 14. RESOLVED: VRAM - No Longer a Concern

**Updated**: Target hardware is now NVIDIA RTX A6000 with **48GB VRAM** (up from RTX 4000 ADA 20GB).

This comfortably accommodates:
- **vLLM** with `gpt-oss-20b` (estimated 10-20GB FP16, ~5-10GB quantized AWQ/GPTQ)
- **Onyx inference_model_server** (embedding models, ~500MB-2GB)
- **Onyx indexing_model_server** (same embedding models)
- Potential for a **second fallback model** served by vLLM (recommended for air-gapped resilience)

No VRAM mitigation needed. Set `--gpu-memory-utilization 0.80` on vLLM (WSL2 headroom), leaving plenty for Onyx model servers.

> **WSL2 note**: Reduce `--gpu-memory-utilization` by 5-10% vs bare-metal Linux to account for Windows display driver VRAM overhead. `0.80` is recommended for WSL2 vs the typical `0.90` on Linux.

---

## 15. MEDIUM: Migration Plan / Actual File Drift

The `LACI-Basalt-Migration.md` migration plan has several discrepancies with the actual files:

| Topic | Migration Plan Says | Actual State |
|-------|-------------------|--------------|
| Langfuse `.env` changes | "Remove IMAGE_REPO_BASE placeholder" | Placeholder still present |
| Langfuse secrets | "Generate NEXTAUTH_SECRET, ENCRYPTION_KEY" | Not present in .env at all |
| LiteLLM image | `ghcr.io/berriai/litellm-database` | `.env` has `litellm/litellm-database` with TODO |
| LiteLLM extra_hosts | Add `host.docker.internal:host-gateway` | Not present in compose |
| LiteLLM config | Create `litellm-config.yaml` | File doesn't exist |
| Open-WebUI port | 3002 | `.env.example` says 3000 |
| Open-WebUI extra_hosts | Add to compose | Currently commented out |
| Onyx `.env` | Create from `env.template` | Not created yet |

The plan is a good guide, but none of Phase 1-5 has actually been executed yet.

---

## 16. MEDIUM: `version: '3'` Deprecated in Docker Compose

**Files**: Both `langfuse/docker-compose.yaml:1` and `litellm/docker-compose.yaml:1`

The `version` key is [deprecated since Docker Compose v2](https://docs.docker.com/compose/compose-file/04-version-and-name/). It can be safely removed. Onyx's compose file correctly omits it and uses the `name:` key instead.

---

## 17. LOW: Langfuse DATABASE_URL Comment is Misleading

**File**: `langfuse/docker-compose.yaml:45`

```yaml
DATABASE_URL: ${LANGFUSE_DATABASE_URL:-postgres://user:password@postgres:5432} # should be http:// ?
```

The comment suggests using `http://` but `postgres://` is correct for PostgreSQL connection strings. The comment should be removed to avoid confusion.

---

## 18. LOW: Missing `LANGFUSE_INIT_*` Variables for Automatic Setup

Langfuse supports auto-initialization of org, project, and user on first boot. The `.env` file has these configured (lines 38-46), which is great for a seamless first-start experience. However, the `LANGFUSE_AUTH` in the LiteLLM `.env` must match the base64 encoding of the public:secret key pair defined in Langfuse's `.env`.

Currently:
- Langfuse defines: `pk-examplekey` / `sk-examplekey`
- LiteLLM has: `c2stZXhhbXBsZWtleTpzay1leGFtcGxla2V5` (which is `sk-examplekey:sk-examplekey` base64-encoded)

The LiteLLM base64 value should be `pk-examplekey:sk-examplekey` encoded:
```bash
echo -n "pk-examplekey:sk-examplekey" | base64
# cGstZXhhbXBsZWtleTpzay1leGFtcGxla2V5
```

The current value decodes to `sk-examplekey:sk-examplekey` (uses secret key for both), which won't authenticate correctly.

---

## 19. CRITICAL: Air-Gapped Deployment Strategy (New Section)

Since the target is **fully air-gapped** (no internet at any point), this is a fundamental architectural concern that the current migration plan does not address. Every external dependency must be pre-staged.

### a) Private Docker Registry (Required)

All compose files pull from public registries (Docker Hub, ghcr.io). You need a local registry.

**Recommended approach**: Docker's official `registry:2` container (simplest for single-host):

```bash
# On a machine WITH internet access:

# 1. Pull the registry image itself
docker pull registry:2
docker save registry:2 -o registry.tar

# 2. Pull ALL images needed by the stack
docker pull langfuse/langfuse:3.40.0
docker pull langfuse/langfuse-worker:3.40.0
docker pull ghcr.io/berriai/litellm-database:main-v1.41.14
docker pull redis:alpine
docker pull postgres:15.2-alpine
docker pull clickhouse/clickhouse-server:25.2.1.3085-alpine
docker pull minio/minio:RELEASE.2025-02-28T09-55-16Z
docker pull onyxdotapp/onyx-backend:latest
docker pull onyxdotapp/onyx-web-server:latest
docker pull onyxdotapp/onyx-model-server:latest
docker pull vespaengine/vespa:8.526.15
docker pull nginx:1.23.4-alpine
docker pull ghcr.io/open-webui/open-webui:main
docker pull vllm/vllm-openai:v0.8.4    # vLLM inference server

# 3. Save to transportable archive
docker save \
  langfuse/langfuse:3.40.0 \
  langfuse/langfuse-worker:3.40.0 \
  ghcr.io/berriai/litellm-database:main-v1.41.14 \
  redis:alpine \
  postgres:15.2-alpine \
  clickhouse/clickhouse-server:25.2.1.3085-alpine \
  minio/minio:RELEASE.2025-02-28T09-55-16Z \
  onyxdotapp/onyx-backend:latest \
  onyxdotapp/onyx-web-server:latest \
  onyxdotapp/onyx-model-server:latest \
  vespaengine/vespa:8.526.15 \
  nginx:1.23.4-alpine \
  ghcr.io/open-webui/open-webui:main \
  vllm/vllm-openai:v0.8.4 \
  -o basalt-images.tar

# Transfer registry.tar and basalt-images.tar to air-gapped host
```

```bash
# On the AIR-GAPPED host:

# Option A: Direct load (simplest, no registry needed)
docker load -i basalt-images.tar

# Option B: Run local registry (better for multi-host or updates)
docker load -i registry.tar
docker run -d -p 5000:5000 --restart=always --name registry registry:2
# Then re-tag and push each image to localhost:5000/...
# Then set IMAGE_REPO_BASE=localhost:5000/ in .env files
```

**Recommendation**: For a single-host deployment, **Option A (direct load)** is simplest. Set `IMAGE_REPO_BASE=` (empty) and `DOCKER_REPO_OVERRIDE=` (empty) so compose files use the locally loaded images. Only use Option B if you plan to deploy to multiple hosts.

### b) vLLM Model Pre-Download (Required)

vLLM loads models from HuggingFace format (safetensors). Models must be pre-downloaded for air-gapped deployment.

```bash
# On a machine WITH internet:
pip install huggingface-hub

# Download the primary model (adjust model ID to match your gpt-oss-20b source)
huggingface-cli download <org>/gpt-oss-20b \
  --local-dir /models/gpt-oss-20b

# Optional: download a small fallback model
huggingface-cli download meta-llama/Llama-3.2-3B-Instruct \
  --local-dir /models/llama-3.2-3b

# Transfer the /models/ directory to the air-gapped host
# Store on WSL2 filesystem (NOT /mnt/c/) for best I/O performance
```

**Important model format note**: vLLM works best with **safetensors** (HuggingFace native) or quantized **AWQ/GPTQ** formats. If `gpt-oss-20b` is only available as GGUF (Ollama format), vLLM's GGUF support is experimental and significantly slower. In that case, consider:
1. Finding a safetensors version of the model
2. Converting GGUF to safetensors (complex, not always lossless)
3. Using AWQ/GPTQ quantized variant if available (recommended for VRAM efficiency)

### c) Onyx HuggingFace Model Cache (Required)

Onyx's `inference_model_server` and `indexing_model_server` download embedding models from HuggingFace on first boot. On an air-gapped network, this will fail silently and Onyx won't be able to embed documents.

**Solution**: Pre-populate the Docker volume or mount a pre-cached directory:

```bash
# On a machine WITH internet, run Onyx once to download models:
docker compose up inference_model_server
# Wait for model download to complete, then:
docker compose down

# Export the volume:
docker run --rm -v onyx_model_cache_huggingface:/data -v $(pwd):/backup \
  alpine tar czf /backup/hf-cache.tar.gz -C /data .

# Transfer hf-cache.tar.gz to air-gapped host and import
```

### d) Onyx Connector Limitations

On an isolated network, most of Onyx's 40+ connectors won't work. Available connectors:
- **File upload** (direct document upload via UI)
- **Local file system** (mount local directories)
- **Internal services** accessible on the isolated network (internal Confluence, GitLab, etc.)
- **Web scraper** (for intranet sites)

### e) Fallback Model Strategy

With 48GB VRAM on the A6000, vLLM can serve multiple models. Configure fallback in `litellm-config.yaml`:

```yaml
model_list:
  - model_name: gpt-oss-20b
    litellm_params:
      model: openai/gpt-oss-20b
      api_base: http://host.docker.internal:8001/v1

  - model_name: gpt-oss-20b
    litellm_params:
      model: openai/llama-3.2-3b         # Fallback (smaller model)
      api_base: http://host.docker.internal:8001/v1

  - model_name: gpt-4                     # OpenAI-compat alias
    litellm_params:
      model: openai/gpt-oss-20b
      api_base: http://host.docker.internal:8001/v1
```

LiteLLM will automatically failover to the second model if the primary is unavailable.

> **Note**: For vLLM to serve multiple models simultaneously, you can either:
> 1. Run a single vLLM instance with `--served-model-name` for the primary model (simpler, single model at a time)
> 2. Run two vLLM instances on different ports (true fallback, more VRAM needed)
> Option 1 is sufficient for most deployments since vLLM is very stable once loaded.

### f) Update Migration Plan

The `LACI-Basalt-Migration.md` should add a **Phase 0: Air-Gap Preparation** covering:
- Docker image export/import (including vLLM image)
- vLLM model weight transfer (HuggingFace safetensors format)
- HuggingFace cache pre-population for Onyx embedding models
- Private registry setup (if multi-host)
- NVIDIA Container Toolkit installation on air-gapped host
- Verification that all dependencies are available offline

---

## 20. NEW: vLLM Deployment Configuration

### Architecture Change: Ollama -> vLLM

vLLM replaces Ollama as the LLM inference engine. Key differences:

| Aspect | Ollama (old) | vLLM (new) |
|--------|-------------|------------|
| Deployment | Host-native | Docker container |
| API | Custom + OpenAI-compat | Native OpenAI-compatible |
| Model format | GGUF (quantized) | HuggingFace safetensors (recommended), AWQ, GPTQ |
| LiteLLM prefix | `ollama/model-name` | `openai/model-name` |
| GPU access | Direct (host) | NVIDIA Container Toolkit |
| Port | 11434 | 8001 (avoiding LiteLLM's 8000) |
| Concurrency | Limited | Continuous batching, high throughput |
| Model management | `ollama pull` | `huggingface-cli download` or local path |

### Proposed vLLM Docker Compose

**File**: `basalt-stack/inference/vllm/docker-compose.yaml` (CREATE NEW)

```yaml
services:
  vllm:
    image: ${VLLM_IMAGE:-vllm/vllm-openai}:${VLLM_TAG:-v0.8.4}
    restart: unless-stopped
    ipc: host
    ports:
      - "${VLLM_PORT:-8001}:8000"
    volumes:
      - ${MODEL_PATH:-./models}:/models
    environment:
      - HF_HUB_OFFLINE=1              # Required for air-gapped
      - TRANSFORMERS_OFFLINE=1         # Required for air-gapped
      - VLLM_NO_USAGE_STATS=1         # Disable telemetry
      - NVIDIA_VISIBLE_DEVICES=all
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    command: >
      --model /models/gpt-oss-20b
      --served-model-name gpt-oss-20b
      --host 0.0.0.0
      --port 8000
      --dtype auto
      --gpu-memory-utilization 0.80
      --max-model-len 4096
      --max-num-seqs 128
      --tensor-parallel-size 1
      --enable-prefix-caching
      --disable-log-requests
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 300s              # Models take minutes to load
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "6"
```

### Proposed vLLM .env

**File**: `basalt-stack/inference/vllm/.env` (CREATE NEW)

```env
#####################################################################
## vLLM Image Settings
#####################################################################
VLLM_IMAGE=vllm/vllm-openai
VLLM_TAG=v0.8.4
VLLM_PORT=8001

#####################################################################
## Model Configuration
#####################################################################
# Path to pre-downloaded model weights on host
MODEL_PATH=./models
```

### Updated LiteLLM Config for vLLM

**File**: `basalt-stack/inference/litellm/litellm-config.yaml` (updated from Ollama version)

```yaml
model_list:
  - model_name: gpt-oss-20b
    litellm_params:
      model: openai/gpt-oss-20b          # vLLM serves OpenAI-compatible API
      api_base: http://host.docker.internal:8001/v1
    model_info:
      mode: chat

  # Alias for OpenAI-compatible requests
  - model_name: gpt-4
    litellm_params:
      model: openai/gpt-oss-20b
      api_base: http://host.docker.internal:8001/v1

litellm_settings:
  drop_params: true
  set_verbose: false

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  background_health_checks: true
  health_check_interval: 300
```

### Updated Startup Sequence

```bash
# 1. Create networks (optional, for future use)
docker network create proxy 2>/dev/null || true
docker network create inference-endpoint 2>/dev/null || true

# 2. Start vLLM (takes 2-5 min to load model)
cd basalt-stack/inference/vllm
docker compose up -d

# 3. Start Langfuse (observability)
cd basalt-stack/inference/langfuse
docker compose up -d

# 4. Wait for vLLM health check to pass
docker compose -f basalt-stack/inference/vllm/docker-compose.yaml logs -f vllm
# Look for: "Uvicorn running on http://0.0.0.0:8000"

# 5. Start LiteLLM (LLM gateway)
cd basalt-stack/inference/litellm
docker compose up -d

# 6. Start Onyx (main platform)
cd onyx/deployment/docker_compose
docker compose up -d

# 7. (Optional) Start Open-WebUI
cd basalt-stack/web/open-webui
docker compose up -d
```

### Updated Verification

```bash
# Test vLLM directly
curl http://localhost:8001/v1/models
curl -X POST http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-oss-20b", "messages": [{"role": "user", "content": "Hello"}]}'

# Test via LiteLLM gateway (same as before)
curl http://localhost:8000/v1/models
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{"model": "gpt-oss-20b", "messages": [{"role": "user", "content": "Hello"}]}'
```

### WSL2 GPU Prerequisites

Before vLLM can access the GPU in Docker on Windows/WSL2:

1. **Windows NVIDIA GPU driver** must be installed on the Windows host (NOT inside WSL2)
2. **Docker Desktop** must have WSL2 backend enabled with GPU support
3. **NVIDIA Container Toolkit** must be installed inside WSL2:
   ```bash
   # Inside WSL2:
   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
     | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
   curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
     | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
     | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
   sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
   sudo nvidia-ctk runtime configure --runtime=docker
   sudo systemctl restart docker
   ```
4. Verify GPU access: `docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi`

> **Air-gap note**: The NVIDIA Container Toolkit packages must also be pre-downloaded for air-gapped installation. Use `apt-get download` on a connected machine and transfer the `.deb` files.

---

## 21. Architecture Feedback: Positive Observations

Several things are well-designed:

1. **LiteLLM as gateway**: Centralizes LLM access, provides OpenAI-compatible API, enables observability via Langfuse. This is the standard pattern for multi-consumer LLM deployments.

2. **Langfuse for observability**: Critical for understanding model behavior, debugging, and cost tracking. Auto-init configuration simplifies first boot.

3. **vLLM for inference**: Excellent choice for a multi-consumer platform (Onyx + Open-WebUI + direct API). Continuous batching handles concurrent requests far better than Ollama. Native OpenAI-compatible API simplifies LiteLLM integration.

4. **Auth disabled for local**: Correct choice for initial deployment. Can be layered on later.

5. **`extra_hosts` pattern in Onyx**: Already configured in the Onyx compose file, showing Docker-to-host communication was considered.

6. **Containerized vLLM**: Running vLLM in Docker (not host-native) means consistent deployment, easy versioning, and reproducible behavior across environments.

---

## Prioritized Fix List

### Must Fix Before First `docker compose up`

| # | Severity | Issue | File(s) |
|---|----------|-------|---------|
| 1 | CRITICAL | Fix `IMAGE_REPO_BASE` placeholder | langfuse/.env, litellm/.env |
| 2 | CRITICAL | Fix `POSTGRES_IMAGE` / `POSTGRES_TAG` double-assign | langfuse/.env, litellm/.env |
| 3 | CRITICAL | Fix broken `depends_on` YAML | litellm/docker-compose.yaml |
| 4 | CRITICAL | Add missing `LITELLM_MASTER_KEY` | litellm/.env |
| 5 | CRITICAL | Create `litellm-config.yaml` (vLLM routing) | litellm/ |
| 6 | CRITICAL | Make `OPENAI_API_KEY`/`COHERE_API_KEY` optional | litellm/docker-compose.yaml |
| 7 | CRITICAL | Create vLLM docker-compose.yaml and .env | vllm/ (NEW) |
| 8 | HIGH | Fix `LANGFUS_` typos (2 places) | langfuse/docker-compose.yaml |
| 9 | HIGH | Fix `restart: alway` typo | langfuse/docker-compose.yaml |
| 10 | HIGH | Generate `NEXTAUTH_SECRET`, `ENCRYPTION_KEY` | langfuse/.env |
| 11 | HIGH | Generate `REDIS_AUTH` | litellm/.env |
| 12 | HIGH | Fix `LANGFUSE_AUTH` base64 value | litellm/.env |
| 13 | HIGH | Add `extra_hosts` to LiteLLM compose | litellm/docker-compose.yaml |
| 14 | HIGH | Create Onyx `.env` from template | onyx/.env |
| 15 | HIGH | Create Open-WebUI `.env` with port 3002 | open-webui/.env |

### Should Fix Before Production Use

| # | Severity | Issue | File(s) |
|---|----------|-------|---------|
| 16 | HIGH | Implement air-gap Phase 0 (images, vLLM models, HF cache, NVIDIA toolkit) | New Phase 0 |
| 17 | HIGH | Clean up unused Docker network declarations | All compose files |
| 18 | HIGH | Determine gpt-oss-20b model format (safetensors vs GGUF vs AWQ) | Model files |
| 19 | MEDIUM | Rotate all default passwords | All .env files |
| 20 | MEDIUM | Remove deprecated `version: '3'` | langfuse, litellm compose |
| 21 | MEDIUM | Remove misleading DATABASE_URL comment | langfuse/docker-compose.yaml |
| 22 | MEDIUM | Add fallback model config | litellm-config.yaml |
| 23 | LOW | Fix port mismatch risk in LiteLLM command | litellm/docker-compose.yaml |
| 24 | LOW | Update CLAUDE.md and LACI-Basalt-Migration.md for vLLM + host-routing | Project docs |

---

## Revised Architecture Diagram (Host-Routed, vLLM)

```
              [Host Machine - Windows 11 + WSL2]
              [NVIDIA RTX A6000 - 48GB VRAM]
              [NVIDIA Container Toolkit]
                          |
                   +------+------+
                   | Docker Desktop
                   |   (WSL2)    |
                   +------+------+
                          |
                   Host Port Routing
                          |
    +------+------+------+------+------+
    |      |      |      |      |      |
    v      v      v      v      v      v
 +------+------+------+------+------+------+
 | vLLM | Lite | Lang | Onyx | Open | Onyx |
 |      | LLM  | fuse |      | WebUI| Model|
 | :8001| :8000| :3001| :3000| :3002| Srvrs|
 | [GPU]|      |      |      |      |      |
 +------+------+------+------+------+------+

Traffic via host.docker.internal:<port>:
  Onyx -----> LiteLLM :8000 -----> vLLM :8001
  Open-WebUI -> LiteLLM :8000 ---> vLLM :8001
  LiteLLM ---------> Langfuse :3001 (traces)
```

| Service | Port | Image | GPU |
|---------|------|-------|-----|
| vLLM | 8001 | vllm/vllm-openai:v0.8.4 | Yes (A6000) |
| LiteLLM | 8000 | ghcr.io/berriai/litellm-database | No |
| Langfuse | 3001 | langfuse/langfuse:3.40.0 | No |
| Onyx | 3000 | onyxdotapp/onyx-backend:latest | No |
| Open-WebUI | 3002 | ghcr.io/open-webui/open-webui:main | No |
| Onyx Model Servers | internal | onyxdotapp/onyx-model-server:latest | Optional |

**Traffic flows**:
- Onyx -> LiteLLM: `http://host.docker.internal:8000/v1`
- Open-WebUI -> LiteLLM: `http://host.docker.internal:8000/v1`
- LiteLLM -> vLLM: `http://host.docker.internal:8001/v1`
- LiteLLM -> Langfuse: `http://host.docker.internal:3001` (OTEL traces)

---

## Next Steps

This review is ready. Recommended execution order:

1. **Determine model format** (item 18) - Must know if gpt-oss-20b is safetensors/AWQ/GPTQ/GGUF before configuring vLLM
2. **Implement all CRITICAL fixes** (items 1-7) - without these, nothing starts. Includes creating vLLM compose.
3. **Implement HIGH fixes** (items 8-15) - needed for functional deployment
4. **Plan air-gap preparation** (item 16) - required before deployment to isolated network
5. **Clean up networking** (item 17) - simplify compose files to match host-routing decision
6. **Address MEDIUM/LOW items** (19-24) - polish, production readiness, update project docs

### Open Question

**Model format for gpt-oss-20b**: Before implementing the vLLM configuration, you need to determine what format `gpt-oss-20b` is available in:
- **safetensors** (ideal for vLLM) - use as-is with `--model /models/gpt-oss-20b`
- **AWQ/GPTQ** (quantized, also good) - add `--quantization awq` or `--quantization gptq`
- **GGUF** (Ollama format) - **not recommended for vLLM** (experimental, slow). Consider converting or finding a safetensors version.

This decision affects the vLLM `command:` args, VRAM usage, and inference performance.
