---
title: "vLLM Version Requirements for gpt-oss-20b"
module: vllm
date: 2026-02-17
problem_type: runtime-errors
category: solution
component: vllm-inference
symptoms:
  - vLLM fails during model initialization with gpt-oss-20b
  - MoE architecture not supported in older versions
  - MXFP4 quantization kernels missing
root_cause: "gpt-oss-20b requires MoE + MXFP4 support only available in vLLM v0.10.2+"
severity: critical
tags:
  - vllm
  - gpt-oss-20b
  - moe
  - mxfp4
  - version-pinning
services: [vllm]
aliases:
  - vllm-version
  - gpt-oss-20b-requirements
related:
  - "[[basalt-system-design|system-design]]"
  - "[[deployment-guide-dev|deployment-guide]]"
  - "[[basalt-development-roadmap|roadmap]]"
---

# Problem

The initial Basalt Stack configuration specified vLLM `v0.8.4` for serving the `gpt-oss-20b` model. This version cannot load or serve gpt-oss-20b, failing during model initialization.

# Root Cause

gpt-oss-20b is a **Mixture-of-Experts (MoE)** model with **MXFP4 quantization** (Microscaling FP4). These features require specific vLLM support:

| Feature | Minimum vLLM Version | Notes |
|---------|---------------------|-------|
| MoE architecture support | v0.9.x+ | Expert-parallel scheduling, proper MoE kernel dispatch |
| MXFP4 quantization | v0.10.0+ | Microscaling FP4 dequantization kernels |
| `--async-scheduling` flag | v0.10.0+ | Recommended for MoE models to overlap expert computation with scheduling |

vLLM `v0.8.4` predates all of these features and will fail to load the model weights.

# Solution

Updated the vLLM image tag from `v0.8.4` to **`v0.10.2`** in the Basalt Stack configuration.

## Configuration Changes

**`basalt-stack/inference/vllm/.env`**:
```
VLLM_TAG=v0.10.2
```

**`basalt-stack/inference/vllm/docker-compose.yaml`** additional changes for gpt-oss-20b compatibility:

| Setting | Old Value | New Value | Reason |
|---------|-----------|-----------|--------|
| Model source | Local path | `openai/gpt-oss-20b` (HuggingFace) | Auto-download for dev; revert to local path for air-gap in Phase 5 |
| `HF_HUB_OFFLINE` | `1` | Removed | Enable HuggingFace download in dev; re-enable for Phase 5 |
| `TRANSFORMERS_OFFLINE` | `1` | Removed | Same as above |
| `--async-scheduling` | Not set | Added | Recommended for MoE inference performance |
| `--max-num-seqs` | `128` | `64` | Fits within 20GB VRAM (RTX 4000 ADA dev hardware) |
| `--gpu-memory-utilization` | Not set | `0.85` | Conservative for 20GB VRAM; can increase to 0.90+ on A6000 (48GB) |
| `start_period` | `300s` | `600s` | Allows time for first-run model download from HuggingFace |
| HF cache volume | Not set | `vllm-hf-cache` named volume | Persist downloaded model across container restarts |

## Model Characteristics

For reference, the key gpt-oss-20b specifications that drive these requirements:

| Property | Value |
|----------|-------|
| Architecture | Mixture-of-Experts (MoE) |
| Total parameters | 21B |
| Active parameters per token | 3.6B |
| Quantization | MXFP4 (Microscaling FP4) |
| Approximate VRAM usage | ~14GB |
| Minimum GPU | 16GB VRAM (with reduced batch size) |
| Target GPU (production) | NVIDIA RTX A6000, 48GB VRAM |
| Dev GPU (Phase 2) | NVIDIA RTX 4000 ADA, 20GB VRAM |

# Files Changed

| File | Change |
|------|--------|
| `basalt-stack/inference/vllm/.env` | `VLLM_TAG` updated from `v0.8.4` to `v0.10.2` |
| `basalt-stack/inference/vllm/docker-compose.yaml` | Model source, scheduling flags, memory settings, health check timing, HF cache volume |

# Phase 5 Impact

When preparing for air-gapped deployment (Phase 5), the following must be reverted or adjusted:

1. **Re-enable offline mode**: Add back `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1` environment variables
2. **Switch to local model path**: Change model from `openai/gpt-oss-20b` to a local volume-mounted path (e.g., `/models/gpt-oss-20b`)
3. **Update image staging list**: Section 5.1 of the roadmap lists `vllm/vllm-openai:v0.8.4` -- this must be updated to `v0.10.2`
4. **Adjust VRAM settings**: On the A6000 (48GB), `--gpu-memory-utilization` can be increased to `0.90` and `--max-num-seqs` can be raised back to `128`
