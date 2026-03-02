# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Golden Directive

**Always ask the user for additional information pertaining to the subject at hand before filling the gap with assumptions.**

## Overview

**Basalt Stack** is a multi-project repository containing an integrated AI infrastructure:

- **basalt-stack/** - Orchestration and inference infrastructure (LiteLLM, Langfuse)
- **onyx/** - Main AI platform with RAG, agents, and 40+ connectors (see `onyx/CLAUDE.md` for detailed guidance)
- **open-webui/** - Alternative self-hosted chat interface (Svelte/Python)

## Architecture

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
   |    LiteLLM      |    |    Langfuse     |    |      vLLM        |
   |   (port 8000)   |--->|   (port 3001)   |    |   (port 8001)    |
   +--------+--------+    +-----------------+    +------------------+
            |                                         [Docker/GPU]
            +--------------------------------------------+
```

| Service | Port | Description |
|---------|------|-------------|
| vLLM | 8001 | LLM inference engine (gpt-oss-20b) |
| LiteLLM | 8000 | LLM gateway/proxy |
| Langfuse | 3001 | LLM observability |
| Onyx | 3000 | Main AI platform |
| Open-WebUI | 3002 | Alternative chat UI |

## Networking

All inter-service communication uses **host-routed networking** via `host.docker.internal`. Each compose stack publishes ports to the host; other stacks reach them through the host network. No Docker overlay networks are required.

> **Note**: The architecture diagram shows logical tiers (`proxy`, `inference-endpoint`), not Docker networks. Network segmentation is a Phase 7 hardening item.

## Startup Sequence

```bash
# 1. Start vLLM (first run downloads model, ~2-5 min load)
cd basalt-stack/inference/vllm && docker compose up -d
# Verify: curl http://localhost:8001/v1/models

# 2. Start Langfuse (observability)
cd basalt-stack/inference/langfuse && docker compose up -d

# 3. Start LiteLLM (LLM gateway)
cd basalt-stack/inference/litellm && docker compose up -d

# 4. Start Onyx (main platform)
cd onyx/deployment/docker_compose && docker compose up -d

# 5. (Optional) Start Open-WebUI
cd basalt-stack/web/open-webui && docker compose up -d
```

## Commands Quick Reference

### Onyx Backend (Python)
```bash
cd onyx/backend
source .venv/bin/activate              # Activate venv (or .venv\Scripts\activate on Windows)
pre-commit run --all-files             # Linting and formatting
pytest -xv tests/unit                  # Unit tests
pytest tests/integration               # Integration tests
alembic upgrade head                   # Database migrations
```

### Onyx Frontend (Next.js)
```bash
cd onyx/web
npm install && npm run dev             # Development server on :3000
npm run build                          # Production build
npm run lint                           # ESLint
npx playwright test                    # E2E tests
```

### Open-WebUI
```bash
cd basalt-stack/web/open-webui
docker compose up -d                   # Production
docker compose -f docker-compose.dev.yaml up -d  # Development

# Source code dev (from repo root):
cd open-webui
npm install && npm run dev             # Frontend dev server
npm run lint && npm run format         # Lint and format
```

### LiteLLM Verification
```bash
curl http://localhost:8000/v1/models
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{"model": "gpt-oss-20b", "messages": [{"role": "user", "content": "Hello"}]}'
```

## Key Notes

- **Onyx Details**: See `onyx/CLAUDE.md` for comprehensive Onyx-specific guidance (Celery workers, testing strategy, API patterns, database operations)
- **Docker-to-Host**: Use `host.docker.internal` for inter-container communication (e.g., LiteLLM → vLLM)
- **API Calls**: Route through frontend (`http://localhost:3000/api/*`) not directly to backend
- **DB Operations**: Onyx DB queries must go through `onyx/backend/onyx/db/` or `onyx/backend/ee/onyx/db/`
- **Postgres Access**: `docker exec -it onyx-relational_db-1 psql -U postgres -c "<SQL>"`
- **Logs**: Check `onyx/backend/log/<service_name>_debug.log` for service logs
- **Test Login**: Playwright tests use `a@test.com` / `a` at `http://localhost:3000`
- **Strict Typing**: All code must be strictly typed (Python and TypeScript)

## Technology Stack

| Project | Backend | Frontend |
|---------|---------|----------|
| Onyx | Python 3.11, FastAPI, SQLAlchemy, Celery | Next.js 15+, React 18, TypeScript, Tailwind |
| Open-WebUI | Python, FastAPI | Svelte 4, SvelteKit, Vite, TypeScript |
| LiteLLM | Python | - |
| Langfuse | - | Next.js |

## Environment Configuration

Key environment files to configure:
- `basalt-stack/inference/langfuse/.env` - Langfuse secrets
- `basalt-stack/inference/litellm/.env` - LiteLLM config and Langfuse integration
- `basalt-stack/inference/litellm/litellm-config.yaml` - Model routing to vLLM
- `onyx/deployment/docker_compose/.env` - Onyx configuration
- `basalt-stack/web/open-webui/.env` - Open-WebUI settings
- `basalt-stack/inference/vllm/.env` - vLLM image tag, port, model path

See `docs/plans/basalt-development-roadmap.md` for phased deployment plan.
