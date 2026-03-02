# CLAUDE.md

## Golden Directive

**Always ask the user for additional information pertaining to the subject at hand before filling the gap with assumptions.**

## Overview

**Basalt Stack** is a **fully air-gapped** multi-project repository for self-hosted AI infrastructure on Windows 11 + WSL2 with NVIDIA GPU.

- **basalt-stack/** — Orchestration and inference (vLLM, LiteLLM, Langfuse)
- **basalt-stack/tools/rmf-generator/** — RMF document automation (docxtpl + vLLM structured output)
- **onyx/** — AI platform with RAG, deployed as-is (see `onyx/CLAUDE.md` for deploy-only reference)
- **open-webui/** — Alternative chat interface (Svelte/Python)
- **rmf-plan-templates/** — 20 NIST 800-53 Rev5 control family .docx templates
- **docs/** — Plans, solutions, brainstorms, and decision records
- **todos/** — Tracked issues with status/priority frontmatter

## Air-Gap Constraints

This stack runs on isolated networks with **no internet access at any point**:
- No `pip install`, `npm install`, `docker pull`, or CDN fetches at runtime
- All images, wheels, and assets must be pre-staged (see Phase 5 in roadmap)
- Telemetry must be disabled in every service (vLLM, Langfuse, Open-WebUI already done)

## Architecture

```
                          +-----------------+
                          |   Open-WebUI    |
                          |   (port 3002)   |
                          +--------+--------+
                                   |
                          +--------+--------+
                          |      Onyx       |
                          |   (port 3000)   |
                          +--------+--------+
                                   |
            +----------------------+----------------------+
            |                      |                      |
   +--------+--------+    +-------+-------+    +---------+---------+
   |    LiteLLM      |    |   Langfuse    |    |       vLLM        |
   |   (port 8000)   +--->|  (port 3001)  |    |    (port 8001)    |
   +--------+--------+    +---------------+    +-------------------+
            |                                        [Docker/GPU]
            +----------------------------------------+
```

| Service | Port | Compose Location |
|---------|------|-----------------|
| vLLM | 8001 | `basalt-stack/inference/vllm/` |
| LiteLLM | 8000 | `basalt-stack/inference/litellm/` |
| Langfuse | 3001 | `basalt-stack/inference/langfuse/` |
| Onyx | 3000 | `onyx/deployment/docker_compose/` |
| Open-WebUI | 3002 | `basalt-stack/web/open-webui/` |

## Networking

Services in **different compose stacks** communicate via `host.docker.internal` (container → host → container). Each stack publishes ports to the host; other stacks reach them through those published ports.

Within a **single compose stack**, services use Docker service names directly (e.g., `redis`, `postgres`).

> The architecture diagram shows logical tiers, not Docker networks. Network segmentation is a Phase 7 hardening item.

## Startup Sequence

```bash
# 1. Start vLLM (requires v0.10.2+ for gpt-oss-20b MoE support)
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

### LiteLLM Verification
```bash
curl http://localhost:8000/v1/models
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{"model": "gpt-oss-20b", "messages": [{"role": "user", "content": "Hello"}]}'
```

### RMF Generator
```bash
cd basalt-stack/tools/rmf-generator
pip install -r requirements.txt  # pre-staged wheels only (air-gap)
```
**Module structure**: `models/` (Pydantic: `control.py`, `system.py`), `loaders/`, `generators/`, `llm/` — loaders/generators/llm are stubs (TBD).
**Data**: `data/notional_system.yaml` (system context), `data/nist-800-53-catalog.json` (OSCAL controls)
**Stack**: docxtpl + vLLM `response_format` + OSCAL catalog + YAML system context
**Decision doc**: `docs/solutions/research-decisions/rmf-doc-automation-stack-selection.md`

## Gotchas

- **ClickHouse Alpine IPv6**: Health checks fail if using `localhost` (resolves to `::1`). Use `127.0.0.1`. See `docs/solutions/clickhouse-alpine-healthcheck-fix.md`
- **Langfuse telemetry**: Must set `TELEMETRY_ENABLED=false` for air-gap. Check `basalt-stack/inference/langfuse/.env`
- **vLLM version**: gpt-oss-20b requires **v0.10.2+** (MoE + MXFP4). See `docs/solutions/vllm-gpt-oss-20b-version-requirements.md`
- **`gpt-4` alias**: `litellm-config.yaml` maps `gpt-4` → `gpt-oss-20b` so OpenAI-compatible clients work without reconfiguration

## Environment Configuration

Key environment files:
- `basalt-stack/inference/vllm/.env` — vLLM image tag, port, model path
- `basalt-stack/inference/litellm/.env` — LiteLLM config and Langfuse integration
- `basalt-stack/inference/litellm/litellm-config.yaml` — Model routing to vLLM
- `basalt-stack/inference/langfuse/.env` — Langfuse secrets
- `onyx/deployment/docker_compose/.env` — Onyx configuration
- `basalt-stack/web/open-webui/.env` — Open-WebUI settings

See `docs/plans/basalt-development-roadmap.md` for phased deployment plan.
