---
title: "Basalt Stack Architecture Review - Research Findings"
date: 2026-02-16
tags: [architecture, vllm, docker, air-gap, wsl2, litellm, langfuse]
status: research-complete
next-step: review-user-constraints-document
---

# Architecture Review Research Summary

## Context

Full architecture review of the Basalt Stack - a containerized self-hosted LLM platform
targeting fully air-gapped isolated networks. Review covered all Docker Compose files,
environment configs, and the LACI-Basalt-Migration.md deployment plan.

## Key Documents

| Document | Location | Purpose |
|----------|----------|---------|
| Architecture Review (full) | `docs/plans/2026-02-16-review-basalt-stack-architecture-and-migration-plan.md` | 24-item prioritized fix list, architecture feedback, vLLM config |
| Migration Plan (original) | `LACI-Basalt-Migration.md` | Deployment checklist (needs rewrite for vLLM + air-gap) |
| Project Guide | `CLAUDE.md` | Architecture diagram, startup sequence (needs vLLM update) |

## Confirmed Architecture Decisions

1. **vLLM replaces Ollama** - Docker container at `basalt-stack/inference/vllm/`, port 8001
2. **Host-routed networking** - All inter-stack via `host.docker.internal`, no Docker networks
3. **Fully air-gapped** - No internet. Pre-stage: images, models, HF cache, NVIDIA toolkit
4. **NVIDIA RTX A6000** - 48GB VRAM, no contention concerns
5. **Model format TBD** - safetensors recommended for vLLM, GGUF experimental/slow

## Critical Findings (7 blockers)

1. Broken YAML in LiteLLM compose (`depends_on` missing)
2. Missing `LITELLM_MASTER_KEY` in .env
3. `IMAGE_REPO_BASE` placeholder breaks image pulls (both langfuse + litellm)
4. `POSTGRES_IMAGE` variable never defined (assigned to POSTGRES_TAG instead)
5. `litellm-config.yaml` doesn't exist (volume-mounted but missing)
6. API keys marked required but unnecessary for vLLM
7. vLLM compose/config files don't exist yet (need creation)

## Research Sources Used

- vLLM official Docker documentation
- LiteLLM vLLM provider docs
- NVIDIA Container Toolkit WSL2 guide
- Docker Compose GPU access patterns
- Air-gapped deployment patterns (HuggingFace offline mode)

## Open Questions (For Next Session)

1. **gpt-oss-20b model format** - safetensors, AWQ, GPTQ, or GGUF?
2. **User constraints document** - User is creating a document with:
   - System and operational environment constraints
   - User flow requirements
   - Security requirements
3. **Plan approval** - Review pending until constraints document is incorporated

## Lessons Learned

- Always verify compose files against their .env files - variable name mismatches are common
- Air-gapped deployment has a "hidden dependency tree" beyond just Docker images (ML models, HF cache, toolkit packages)
- WSL2 GPU passthrough works but needs lower memory utilization (~0.80 vs 0.90)
- vLLM GGUF support is experimental and significantly underperforms safetensors
- Host-routing via `host.docker.internal` is simpler than Docker networks for multi-compose-file stacks
