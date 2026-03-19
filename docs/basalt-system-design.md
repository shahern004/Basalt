# Basalt Stack — System Design Document

**Version:** 1.0
**Date:** 2026-03-13
**Classification:** Unclassified // FOUO
**Environment:** Air-gapped Windows 11 + WSL2, NVIDIA RTX A6000 (48 GB VRAM)

---

## 1. Container Architecture

### 1.1 Stack Topology

Basalt runs as **six independent Docker Compose stacks** on a single host. Inter-stack communication uses `host.docker.internal` (container → host loopback → container). Intra-stack services use Docker service names.

```
 ┌─────────────────────────────────────────────────────────────┐
 │                        HOST (Windows 11 + WSL2)             │
 │                                                             │
 │  ┌──────────────────────────────────────────────────────┐   │
 │  │  Authentik (SSO Portal)  :443/:80                    │   │
 │  │  auth.basalt.local → App Launcher / Login            │   │
 │  │  webui.basalt.local → Proxy → Open-WebUI :3002       │   │
 │  │  onyx.basalt.local  → Proxy + OIDC → Onyx :3000     │   │
 │  └──────────────────────────────────────────────────────┘   │
 │       │              │             │                         │
 │       └──────────────┼─────────────┘                         │
 │                      │  host.docker.internal                 │
 │              ┌───────┴────────┐                              │
 │              │    LiteLLM     │──────→ Langfuse :3001        │
 │              │    :8000       │        (traces + metrics)    │
 │              └───────┬────────┘                              │
 │                      │  host.docker.internal:8001            │
 │              ┌───────┴────────┐                              │
 │              │     vLLM       │                              │
 │              │    :8001       │                              │
 │              │  [NVIDIA GPU]  │                              │
 │              └────────────────┘                              │
 └─────────────────────────────────────────────────────────────┘
```

### 1.2 Service Inventory

| Stack | Service | Image | Published Port | Containers | Persistent Volumes |
|-------|---------|-------|---------------|------------|-------------------|
| **vLLM** | vllm | `vllm/vllm-openai:v0.10.2` | 8001 | 1 | `vllm-hf-cache`, model bind-mount |
| **LiteLLM** | litellm | `ghcr.io/berriai/litellm` | 8000 | 3 | `postgres_data`, `redis_data` |
| | redis | `redis:alpine` | — | | |
| | postgres | `postgres:16-alpine` | — | | |
| **Langfuse** | langfuse-web | `langfuse/langfuse` | 3001 | 6 | `postgres_data`, `clickhouse_data`, `clickhouse_logs`, `minio_data`, `redis_data` |
| | langfuse-worker | same | — | | |
| | clickhouse | `clickhouse-server:25.2-alpine` | — | | |
| | minio | `minio/minio` | — | | |
| | postgres | `postgres:16-alpine` | — | | |
| | redis | `redis:alpine` | — | | |
| **Onyx** | nginx | `nginx:1.23.4-alpine` | 3000 | 10 | `db_volume`, `vespa_volume`, `minio_data`, HF model caches (×2), log volumes (×4) |
| | api_server | `onyxdotapp/onyx-backend` | — | | |
| | background | same | — | | |
| | web_server | `onyxdotapp/onyx-web-server` | — | | |
| | inference_model_server | `onyxdotapp/onyx-model-server` | — | | |
| | indexing_model_server | same | — | | |
| | relational_db | `postgres:15.2-alpine` | — | | |
| | index (Vespa) | `vespaengine/vespa:8.526.15` | — | | |
| | cache | `redis:7.4-alpine` | — | | |
| | minio | `minio/minio` | — | | |
| **Open-WebUI** | open-webui | `ghcr.io/open-webui/open-webui` | 3002 | 1 | `data` |
| **Authentik** | server | `ghcr.io/goauthentik/server:2026.2.1` | 443, 80 | 4 | `data`, `certs`, PostgreSQL + Redis volumes |
| | worker | same | — | | |
| | postgres | `postgres:16-alpine` | — | | |
| | redis | `redis:7.4-alpine` | — | | |

**Total: ~25 containers across 6 stacks** (Portal archived, replaced by Authentik).

### 1.3 Networking Model

- **Inter-stack**: All compose files include `extra_hosts: host.docker.internal:host-gateway`. Services reference other stacks via `http://host.docker.internal:<port>`.
- **Intra-stack**: Standard Docker Compose DNS (service names).
- **No shared Docker network**: Each stack creates its own default bridge. This simplifies independent deployment at the cost of no direct container-to-container routing across stacks.
- **Network segmentation**: Deferred to Phase 7 hardening.

### 1.4 GPU Allocation

| Parameter | Value |
|-----------|-------|
| GPU | NVIDIA RTX A6000 (48 GB VRAM) |
| Allocation | 1× GPU exclusively to vLLM container |
| `gpu_memory_utilization` | 0.85 (40.8 GB usable) |
| `max_model_len` | 4096 tokens (may increase to 8192 for RMF) |
| `tensor_parallel_size` | 1 (single GPU) |
| IPC mode | `host` (required for CUDA shared memory) |

### 1.5 Startup Order & Dependencies

```
1. vLLM          (standalone, GPU model load ~5-10 min)
2. Langfuse      (standalone, no upstream deps)
3. LiteLLM       (depends: Langfuse for tracing, vLLM for inference)
4. Authentik     (standalone — must be up before Onyx/Open-WebUI for OIDC/SSO)
5. Onyx          (depends: LiteLLM for LLM calls, Authentik for OIDC)
6. Open-WebUI    (depends: LiteLLM for LLM calls, Authentik for SSO headers)
```

---

## 2. RMF Document Automation

### 2.1 Purpose

Automated generation of NIST 800-53 Rev 5 System Security Plan (SSP) documents. Fills `.docx` templates with system metadata and LLM-synthesized Organization-Defined Parameters (ODPs).

### 2.2 Tool & Library Stack

| Tool | Role |
|------|------|
| **docxtpl** | Jinja2-based Word document rendering |
| **jinja2** | Template engine (used by docxtpl) |
| **pydantic** | Data validation for system metadata and LLM output schemas |
| **PyYAML** | Load system description from YAML |
| **vLLM** `response_format` | Structured JSON output (constrained decoding) |
| **OSCAL catalog** (`nist-800-53-catalog.json`) | Canonical control definitions and ODP specifications |
| **LiteLLM** | LLM gateway with Langfuse tracing |

### 2.3 Module Structure

```
basalt-stack/tools/rmf-generator/
├── retag_template.py              # Stage 0: Convert Word placeholders → Jinja2
├── fill_template.py               # Stage 1: Render template with context dict
├── models/
│   ├── system.py                  # SystemDescription, PersonnelRole, SystemComponent
│   └── control.py                 # ODPValue, ODPSet, NarrativeOutput (LLM schema)
├── loaders/                       # [B2] OSCAL + system context loading
│   ├── oscal_loader.py            #   Parse nist-800-53-catalog.json
│   └── system_loader.py           #   Load + validate notional_system.yaml
├── generators/                    # [B2] Context assembly
│   └── context_assembler.py       #   Merge system data + ODP definitions → context dict
├── llm/                           # [B3] LLM integration
│   └── synthesizer.py             #   vLLM structured output → NarrativeOutput
├── data/
│   ├── nist-800-53-catalog.json   # Full OSCAL catalog (~10 MB, 1,189 controls)
│   └── notional_system.yaml       # MERIDIAN/DGIA fictional federal system
├── templates/
│   └── MP.docx                    # Re-tagged template (33 Jinja2 variables)
└── output/
    └── MP-filled.docx             # Rendered demo document
```

### 2.4 Document Generation Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│ STAGE 0 — Template Re-tagging (one-time, per control family)    │
│                                                                 │
│  rmf-plan-templates/MP-*.docx                                   │
│       │                                                         │
│       │  retag_template.py                                      │
│       │  • Merge split XML runs (collapse-to-first-run)         │
│       │  • SIMPLE_MAPPINGS (28 entries, longest-first sort)     │
│       │  • POSITIONAL_MAPPINGS (3 keys, occurrence-ordered)     │
│       │  • Handles typos and nested brackets                    │
│       ▼                                                         │
│  templates/MP.docx  →  33 {{ jinja2_variables }}                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ STAGE 1 — Context Assembly (B2)                                 │
│                                                                 │
│  notional_system.yaml ──→ system_loader.py ──→ SystemDescription│
│  nist-800-53-catalog.json → oscal_loader.py → ODP definitions  │
│                                    │                            │
│                         context_assembler.py                    │
│                                    │                            │
│                         Merged context dict                     │
│                    (system fields + ODP placeholders)            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ STAGE 2 — LLM Synthesis (B3)                                    │
│                                                                 │
│  Context dict + OSCAL ODP specs                                 │
│       │                                                         │
│       │  llm/synthesizer.py                                     │
│       │  • POST /v1/chat/completions → LiteLLM :8000            │
│       │  • response_format: NarrativeOutput JSON schema         │
│       │  • Pydantic validation + retry on malformed response    │
│       │  • --mock flag: load pre-generated JSON (no LLM needed) │
│       ▼                                                         │
│  ODPSet (validated ODP values with source tracking)             │
│       │                                                         │
│       │  Trace → Langfuse :3001                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ STAGE 3 — Document Rendering                                    │
│                                                                 │
│  fill_template.py                                               │
│  • Flat context dict (system metadata + ODP values)             │
│  • SSTI sanitization (strips {{ }}, {% %}, {# #} from values)  │
│  • docxtpl.DocxTemplate.render(context)                         │
│       ▼                                                         │
│  output/MP-filled.docx  (production-ready SSP section)          │
└─────────────────────────────────────────────────────────────────┘
```

### 2.5 Data Models

**SystemDescription** (deterministic, from YAML):
- Organization info, system name/acronym/version, eMASS number
- CIA impact levels (`Low` / `Moderate` / `High`)
- Authorization boundary, mission statement
- Personnel roles (AO, ISSM) with name/title/org
- System components list

**NarrativeOutput** (LLM response schema):
- `odp_values: list[ODPValue]` — each has `placeholder`, `value`, `source` (enum: `DETERMINISTIC` / `LLM_SYNTHESIZED` / `USER_PROVIDED`)
- `reasoning: Optional[str]` — LLM chain-of-thought (logged, not rendered)

### 2.6 Security Controls

| Control | Implementation |
|---------|---------------|
| SSTI prevention | All template values sanitized before Jinja2 rendering |
| Input validation | Pydantic models enforce schema on YAML and LLM output |
| Source tracking | Every ODP value tagged with `FieldSource` enum for audit trail |
| Mock mode | `--mock` flag bypasses LLM entirely for deterministic testing |
| Air-gap safe | No network calls except to local LiteLLM/vLLM containers |

---

## 3. Air-Gap Design Constraints

### 3.1 Pre-Staging Requirements

| Asset | Pre-stage Method | Storage Location |
|-------|-----------------|-----------------|
| Docker images | `docker save` / `docker load` | Local image store |
| Python wheels | `pip download` on connected machine | `requirements.txt` + local wheelhouse |
| vLLM model weights | Manual download (safetensors) | Linux filesystem (not 9p mount) |
| Onyx HF models | Pre-download + `HF_HUB_OFFLINE=1` | Docker volumes |
| OSCAL catalog | Committed to repo | `data/nist-800-53-catalog.json` |
| Word templates | Committed to repo | `rmf-plan-templates/` (20 families) |

### 3.2 Telemetry Disabled

| Service | Mechanism |
|---------|-----------|
| vLLM | `VLLM_NO_USAGE_STATS=1` |
| Open-WebUI | `SCARF_NO_ANALYTICS=true`, `DO_NOT_TRACK=true`, `ANONYMIZED_TELEMETRY=false` |
| Langfuse | `TELEMETRY_ENABLED=false` |
| LiteLLM | No outbound telemetry by default |
| Authentik | `AUTHENTIK_DISABLE_UPDATE_CHECK=true`, `AUTHENTIK_ERROR_REPORTING__ENABLED=false`, `AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true`, `AUTHENTIK_AVATARS=initials` |

---

## 4. Known Constraints & Mitigations

| Issue | Impact | Mitigation |
|-------|--------|------------|
| `drop_params: true` in LiteLLM | May strip `response_format` for structured output | Switch model prefix to `hosted_vllm/` before B3 |
| `MODEL_PATH=./models` on Windows | 9p filesystem bridge = 10-20× model load overhead | Use Linux FS path (`/mnt/wsl/` or ext4 VHD) |
| ClickHouse Alpine IPv6 | Health check fails with `localhost` (resolves `::1`) | Use `127.0.0.1` in health check URL |
| `max_model_len=4096` | May truncate long RMF control narratives | Increase to 8192 after VRAM testing |
| Onyx HF model download at startup | Breaks air-gap if models not pre-staged | Pre-download models + set `HF_HUB_OFFLINE=1` |

---

## 5. Development Status

| Track | Step | Status | Deliverable |
|-------|------|--------|-------------|
| A | A0 Pre-flight | **Done** | Import fixes, telemetry, deps |
| A | A1 Cleanup | **Done** | Stale files, docs, todo renames |
| B | B1 Template + Data | **Done** | `retag_template.py`, `fill_template.py`, MP.docx |
| B | B2 Context Assembly | **Next** | `oscal_loader`, `system_loader`, `context_assembler` |
| B | B3 LLM Integration | Blocked (B2) | `synthesizer.py`, `--mock` flag |
| C | C1 vLLM Model Setup | Pending | Model weights on Linux FS |
| C | C2 Onyx Deploy | Blocked (C1) | Image pin, HF pre-stage |
| C | C3 Open-WebUI Deploy | Blocked (C1) | Image pin, API config |
| D | Hardening | **Authentik SSO DONE** | Secrets rotation, network segmentation remaining |
