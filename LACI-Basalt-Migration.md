# Basalt Stack Local Deployment Plan

## Overview

Deploy the full Basalt AI stack locally on Windows 11 with:
- **Ollama** serving **gpt-oss-20b** (already installed)
- **LiteLLM** as the LLM proxy/gateway (routes to Ollama)
- **Langfuse** for LLM observability
- **Onyx** as the main AI platform
- **Open-WebUI** as alternative chat interface
- **No Authentik** (skipped for simplicity)
- **No vLLM** (using Ollama instead for simpler setup)

**Hardware**: NVIDIA RTX 4000 ADA (20GB VRAM), Docker Desktop with WSL2

---

## Architecture Diagram

```
                          +-----------------+
                          |   Open-WebUI    |
                          |   (port 3002)   |
                          +--------+--------+
                                   |
+----------------------------------+----------------------------------+
|                            proxy network                            |
+----------------------------------+----------------------------------+
                                   |
                          +--------+--------+
                          |      Onyx       |
                          |   (port 3000)   |
                          +--------+--------+
                                   |
+----------------------------------+----------------------------------+
|                      inference-endpoint network                     |
+----------------------------------+----------------------------------+
            |                      |
   +--------+--------+    +--------+--------+    +------------------+
   |    LiteLLM      |    |    Langfuse     |    |     Ollama       |
   |   (port 8000)   |--->|   (port 3001)   |    |   (port 11434)   |
   +--------+--------+    +--------+--------+    |   gpt-oss-20b    |
            |                                    +------------------+
            +------------------------------------+    [Host System]
                                                    [RTX 4000 ADA]
```

---

## Pre-requisites Checklist

- [x] Docker Desktop running with WSL2 backend
- [x] Ollama installed with gpt-oss-20b model
- [X] At least 16GB system RAM recommended
- [X] 30GB+ free disk space for containers

---

## Phase 1: Environment Setup

- [ ] **1.1 Create Docker Networks**
```bash
docker network create proxy
docker network create inference-endpoint
```

- [ ] **1.2 Verify Ollama is Running**
```bash
ollama list
# Should show gpt-oss-20b in the list

curl http://localhost:11434/api/tags
# Should return model information
```

---

## Phase 2: Deploy Observability (Langfuse)

- [ ] **2.1 Configure Langfuse**

**File**: [basalt-stack/inference/langfuse/.env](basalt-stack/inference/langfuse/.env)

Modifications needed:
```env
# Fix image repo - remove placeholder, use Docker Hub directly
IMAGE_REPO_BASE=

# Keep existing values, generate secure keys
NEXTAUTH_SECRET=<generate: openssl rand -hex 32>
ENCRYPTION_KEY=<generate: openssl rand -hex 32>
```

- [ ] **2.2 Start Langfuse**
```bash
cd basalt-stack/inference/langfuse
docker compose up -d
```

---

## Phase 3: Deploy LiteLLM Gateway

- [ ] **3.1 Configure LiteLLM Environment**

**File**: [basalt-stack/inference/litellm/.env](basalt-stack/inference/litellm/.env)

```env
# Fix image repos
IMAGE_REPO_BASE=

LITELLM_IMAGE=ghcr.io/berriai/litellm-database
LITELLM_TAG=main-v1.41.14

REDIS_IMAGE=redis
REDIS_TAG=alpine

POSTGRES_IMAGE=postgres
POSTGRES_TAG=15.2-alpine

# Database
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=litellm
DATABASE_URL=postgres://postgres:postgres@postgres:5432/litellm

# Generate secure Redis password
REDIS_AUTH=<generate: openssl rand -hex 32>

# LiteLLM settings
LITELLM_PORT=8000
LITELLM_MASTER_KEY=sk-<generate: openssl rand -hex 32>

# Langfuse integration (match langfuse .env values)
LANGFUSE_HOST=http://langfuse-web:3000
LANGFUSE_PUBLIC_KEY=pk-examplekey
LANGFUSE_SECRET_KEY=sk-examplekey
LANGFUSE_AUTH=<base64 of pk-examplekey:sk-examplekey>
```

- [ ] **3.2 Create LiteLLM Config for Ollama**

**File**: [basalt-stack/inference/litellm/litellm-config.yaml](basalt-stack/inference/litellm/litellm-config.yaml) (CREATE NEW)

```yaml
model_list:
  - model_name: gpt-oss-20b
    litellm_params:
      model: ollama/gpt-oss-20b
      api_base: http://host.docker.internal:11434
    model_info:
      mode: chat

  # Alias for OpenAI-compatible requests
  - model_name: gpt-4
    litellm_params:
      model: ollama/gpt-oss-20b
      api_base: http://host.docker.internal:11434

litellm_settings:
  drop_params: true
  set_verbose: false

general_settings:
  master_key: sk-master-key  # Override via env var
```

- [ ] **3.3 Update LiteLLM Docker Compose**

**File**: [basalt-stack/inference/litellm/docker-compose.yaml](basalt-stack/inference/litellm/docker-compose.yaml)

Add `extra_hosts` to access Ollama on host:
```yaml
services:
  litellm:
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

- [ ] **3.4 Start LiteLLM**
```bash
cd basalt-stack/inference/litellm
docker compose up -d
```

---

## Phase 4: Deploy Onyx Platform

- [ ] **4.1 Create Onyx Environment File**

**File**: [onyx/deployment/docker_compose/.env](onyx/deployment/docker_compose/.env) (CREATE from env.template)

```env
# Basic settings
IMAGE_TAG=latest
AUTH_TYPE=disabled

# Database
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<secure-password>

# MinIO (keep defaults)
S3_ENDPOINT_URL=http://minio:9000
S3_AWS_ACCESS_KEY_ID=minioadmin
S3_AWS_SECRET_ACCESS_KEY=minioadmin

# LLM Configuration - Point to LiteLLM
# Configure in Onyx Admin UI after startup:
# - Provider: OpenAI-compatible
# - API Base: http://host.docker.internal:8000/v1
# - Model: gpt-oss-20b
```

- [ ] **4.2 Verify Onyx Docker Compose for Host Access**

**File**: [onyx/deployment/docker_compose/docker-compose.yml](onyx/deployment/docker_compose/docker-compose.yml)

Ensure `api_server` and `background` services have:
```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```
(Already present in the file)

- [ ] **4.3 Start Onyx**
```bash
cd onyx/deployment/docker_compose
docker compose up -d
```

---

## Phase 5: Deploy Open-WebUI (Optional)

- [ ] **5.1 Configure Open-WebUI**

**File**: [basalt-stack/web/open-webui/.env](basalt-stack/web/open-webui/.env) (CREATE from .env.example)

```env
DOCKER_IMAGE_REPO=
OPENWEBUI_IMAGE=ghcr.io/open-webui/open-webui:main
WEBUI_SECRET_KEY=<generate: openssl rand -hex 32>
OPEN_WEBUI_PORT_HTTP=3002  # Avoid conflict with Onyx on 3000
```

- [ ] **5.2 Update Open-WebUI Docker Compose**

Add host access for LiteLLM:
```yaml
services:
  open-webui:
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - OPENAI_API_BASE_URL=http://host.docker.internal:8000/v1
      - OPENAI_API_KEY=sk-master-key  # Match LiteLLM master key
```

- [ ] **5.3 Start Open-WebUI**
```bash
cd basalt-stack/web/open-webui
docker compose up -d
```

---

## Files to Modify/Create

| File | Action | Changes | Status |
|------|--------|---------|--------|
| [basalt-stack/inference/langfuse/.env](basalt-stack/inference/langfuse/.env) | Modify | Remove IMAGE_REPO_BASE placeholder, generate secrets | [ ] |
| [basalt-stack/inference/litellm/.env](basalt-stack/inference/litellm/.env) | Modify | Fix image paths, generate secrets, Langfuse keys | [ ] |
| [basalt-stack/inference/litellm/litellm-config.yaml](basalt-stack/inference/litellm/) | Create | Ollama routing configuration | [ ] |
| [basalt-stack/inference/litellm/docker-compose.yaml](basalt-stack/inference/litellm/docker-compose.yaml) | Modify | Add extra_hosts for Ollama access | [ ] |
| [onyx/deployment/docker_compose/.env](onyx/deployment/docker_compose/.env) | Create | Copy from env.template, configure | [ ] |
| [basalt-stack/web/open-webui/.env](basalt-stack/web/open-webui/.env) | Create | Configure port 3002, LiteLLM endpoint | [ ] |
| [basalt-stack/web/open-webui/docker-compose.yaml](basalt-stack/web/open-webui/docker-compose.yaml) | Modify | Add extra_hosts, OpenAI config | [ ] |

---

## Startup Sequence

Execute in this order:

```bash
# 1. Create networks
docker network create proxy
docker network create inference-endpoint

# 2. Start Langfuse (observability)
cd d:/BASALT/Basalt-Architecture/basalt-stack-v1.0/basalt-stack/inference/langfuse
docker compose up -d

# 3. Wait for Langfuse to be healthy (check logs)
docker compose logs -f langfuse-web

# 4. Start LiteLLM (LLM gateway)
cd d:/BASALT/Basalt-Architecture/basalt-stack-v1.0/basalt-stack/inference/litellm
docker compose up -d

# 5. Start Onyx (main platform)
cd d:/BASALT/Basalt-Architecture/basalt-stack-v1.0/onyx/deployment/docker_compose
docker compose up -d

# 6. (Optional) Start Open-WebUI
cd d:/BASALT/Basalt-Architecture/basalt-stack-v1.0/basalt-stack/web/open-webui
docker compose up -d
```

---

## Verification Steps

- [ ] **Test 1: Ollama Direct**
```bash
curl http://localhost:11434/api/generate -d '{"model": "gpt-oss-20b", "prompt": "Hello"}'
```

- [ ] **Test 2: LiteLLM Gateway**
```bash
# List models
curl http://localhost:8000/v1/models

# Test chat completion
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-master-key" \
  -d '{"model": "gpt-oss-20b", "messages": [{"role": "user", "content": "Hello"}]}'
```

- [ ] **Test 3: Langfuse Dashboard**
Open browser: http://localhost:3001
- Login with: basalt@gmail.com / password (from .env)
- Check traces after making LiteLLM requests

- [ ] **Test 4: Onyx UI**
Open browser: http://localhost:3000
- Complete initial setup
- Configure LLM in Admin > LLM settings:
  - Provider: OpenAI-compatible
  - API Base: http://host.docker.internal:8000/v1
  - API Key: sk-master-key
  - Model: gpt-oss-20b

- [ ] **Test 5: Open-WebUI** (if deployed)
Open browser: http://localhost:3002
- Configure OpenAI-compatible API in settings

---

## Port Summary

| Service | Port | URL |
|---------|------|-----|
| Ollama | 11434 | http://localhost:11434 |
| LiteLLM | 8000 | http://localhost:8000 |
| Langfuse | 3001 | http://localhost:3001 |
| Onyx | 3000 | http://localhost:3000 |
| Open-WebUI | 3002 | http://localhost:3002 |

---

## Post-Deployment Configuration

### Onyx LLM Setup (via Admin UI)
- [ ] Navigate to http://localhost:3000
- [ ] Go to Admin Settings > LLM
- [ ] Add new provider:
   - Name: gpt-oss-20b
   - Provider Type: OpenAI-compatible
   - API Base: http://host.docker.internal:8000/v1
   - API Key: sk-master-key (your LiteLLM master key)
   - Model Name: gpt-oss-20b
- [ ] Set as default model

---

## Troubleshooting

### Ollama not accessible from Docker
- Ensure Ollama is running: `ollama serve`
- Check firewall allows port 11434
- Test from Docker: `docker run --rm curlimages/curl curl http://host.docker.internal:11434/api/tags`

### LiteLLM can't reach Ollama
- Verify extra_hosts is set in docker-compose
- Check litellm-config.yaml uses `host.docker.internal:11434`

### Langfuse not showing traces
- Check LANGFUSE_HOST, LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY match between services
- Verify Langfuse containers are healthy: `docker compose ps`

---

## Rollback

To remove all containers and volumes:
```bash
# Stop all services (run from each directory)
docker compose down -v

# Remove networks
docker network rm proxy inference-endpoint
```
