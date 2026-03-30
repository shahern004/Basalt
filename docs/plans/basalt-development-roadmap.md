---
title: "Basalt Stack Development Roadmap"
type: refactor
status: active
category: plan
date: 2026-03-02
deepened: 2026-03-02
tags:
  - roadmap
  - planning
  - tracks
  - milestones
aliases:
  - roadmap
  - dev-roadmap
related:
  - "[[2026-03-17-001-feat-authentik-sso-portal-integration-plan|authentik-plan]]"
  - "[[rmf-generator-pivot-notes|rmf-pivot]]"
  - "[[basalt-system-design|system-design]]"
  - "[[deployment-guide-dev|deployment-guide]]"
  - "[[basalt-sbom|SBOM]]"
  - "[[rmf-doc-automation-stack-selection|rmf-stack-decision]]"
---
cla
# Basalt Stack Development Roadmap

## Enhancement Summary

**Deepened on:** 2026-03-02
**Agents consulted:** Architecture Strategist, Security Sentinel, Performance Oracle, Code Simplicity Reviewer, Kieran Python Reviewer, Deployment Verification Agent, Pattern Recognition Specialist, Spec Flow Analyzer, Framework Docs Researcher

### Key Improvements

1. Added **A0: Pre-Flight Fixes** — 5 immediate blockers that should be fixed before any other work
2. Merged A1+A2 into single **A1: Repo Cleanup** effort (contradictory approaches eliminated)
3. Added **research insights** to each Track B effort (docxtpl cross-run handling, `response_format` passthrough risk, Pydantic schema patterns)
4. Folded B4 (Demo Prep) into B3 as a checklist — not a separate conversation
5. Fixed C-track dependency graph — C2 and C3 are independent (both only need LiteLLM, not each other)
6. Flattened Track D from 7-phase table to bullet list (YAGNI — these are post-MVP reminders, not plans)
7. Added cross-cutting **Security**, **Performance**, and **Deployment** findings sections

### New Blockers Discovered

- **`drop_params: true`** in `litellm-config.yaml` may silently strip `response_format` before forwarding to vLLM — must test before B3
- **Onyx model servers** download HuggingFace models at startup — blocks air-gap C2 deployment
- **`MODEL_PATH=./models`** resolves to Windows filesystem via 9p bridge — 10-20x slower model loading
- **All `__init__.py` files** in rmf-generator crash on import — must fix before any Track B code runs

---

## Current State (verified 2026-03-02)

### Running Infrastructure

| Service | Status | Image | Containers |
|---------|--------|-------|------------|
| Langfuse | **Running** (3 days) | `langfuse/langfuse:3.40.0` | web, worker, redis, minio, clickhouse, postgres |
| LiteLLM | **Running** (3 days) | `ghcr.io/berriai/litellm-database:main-v1.41.14` | litellm, redis, postgres |
| vLLM | **Image pulled, NOT running** | `vllm/vllm-openai:v0.10.2` (34.2GB) | — (model weights not downloaded) |
| Onyx | **NOT running** | Not pulled (`latest` tag — pin before pulling) | — |
| Open-WebUI | **NOT running** | Not pulled (`main` tag — pin before pulling) | — |
| Authentik | **Configured** (code complete) | `ghcr.io/goauthentik/server:2026.2.1` | server, worker, postgres, redis |

### Repo Health Issues

- CLAUDE.md references 2 solution docs that don't exist
- `LACI-Basalt-Migration.md` is stale (Ollama-era, wrong GPU)
- `snips/` contains one orphan screenshot
- 9 of 15 todos are resolved but filenames still say "pending"
- `basalt-stack/inference/vllm/gpt-oss-120b/include.yaml` is a stale 4-GPU config
- `basalt-stack/inference/langfuse/.litellm` is a stale pre-pivot config file
- `basalt-stack/README` references old Docker network architecture
- Langfuse `.env` doesn't set `TELEMETRY_ENABLED=false` (compose defaults to `true`)
- All 4 `__init__.py` files in rmf-generator have broken imports

---

## Track A: Repo Cleanup

### A0: Pre-Flight Fixes

Immediate blockers that affect running infrastructure or block all Track B work. Do these first — they're 15 minutes of config edits, not a full conversation.

- [ ] Add `TELEMETRY_ENABLED=false` to `basalt-stack/inference/langfuse/.env` and restart Langfuse (`docker compose restart langfuse-web langfuse-worker`)
- [ ] Add `docxtpl>=0.18,<1.0` to `basalt-stack/tools/rmf-generator/requirements.txt` (remove `python-pptx` and `instructor` — wrong stack per decision doc)
- [ ] Fix `basalt-stack/tools/rmf-generator/models/__init__.py` — only export classes that exist in `control.py` (`FieldSource`, `ODPValue`, `ODPSet`, `NarrativeOutput`)
- [ ] Clear broken imports in `loaders/__init__.py`, `llm/__init__.py`, `generators/__init__.py` (empty the files or comment out imports for modules not yet written)
- [ ] Verify Langfuse-LiteLLM integration: open `http://localhost:3001`, log in (`basalt@gmail.com` / `password`), confirm "basalt" project exists and check for traces

**Test**: `cd basalt-stack/tools/rmf-generator && python -c "import models; import loaders; import llm; import generators"` succeeds. Langfuse telemetry disabled. Langfuse UI accessible.

### A1: Repo Cleanup & Solution Docs

Delete stale files, fix CLAUDE.md references, write the 2 missing solution docs, clean up todos. Single conversation.

**Delete stale files:**
- [ ] Delete `LACI-Basalt-Migration.md`
- [ ] Delete `snips/` directory
- [ ] Delete `basalt-stack/inference/vllm/gpt-oss-120b/` (stale 120B config)
- [ ] Delete `basalt-stack/inference/langfuse/.litellm` (pre-pivot stale config)
- [ ] Delete or update `basalt-stack/README` (references old Docker network architecture)

**Fix CLAUDE.md:**
- [ ] Update roadmap reference to point to `docs/plans/basalt-development-roadmap.md`
- [ ] Verify Gotchas links still point to solution docs (create them below)

**Create solution docs:**
- [ ] Create `docs/solutions/clickhouse-alpine-healthcheck-fix.md` — document the `127.0.0.1` vs `localhost` IPv6 issue (already fixed in compose)
- [ ] Create `docs/solutions/vllm-gpt-oss-20b-version-requirements.md` — document why v0.10.2+ is required (MoE + MXFP4 support merged via PR #17888)

**Clean up todos:**
- [ ] Rename resolved todos from `NNN-pending-*` to `NNN-resolved-*` (9 files: 001-007, 014, 015)
- [ ] Review 6 pending P3 todos (008-013) — delete any that are stale (008 is done in roadmap table, 009/011 are Onyx-specific and can wait for C2)
- [ ] Commit and push

**Test**: `grep -r "docs/solutions/clickhouse\|docs/solutions/vllm" CLAUDE.md` returns lines pointing to real files. No files named `*pending*` have `status: resolved` in frontmatter. `LACI-Basalt-Migration.md` gone.

### Research Insights (Track A)

**Pattern Recognition findings:**
- 9 stale files identified beyond what original roadmap listed (`.litellm`, `basalt-stack/README`, `litellm-config.yaml.example`, redundant inner `.gitignore`)
- Todo 004 (telemetry) is marked "resolved" but the actual `.env` fix was never applied — this is a **premature resolution** anti-pattern. A0 fixes it.
- The `docs/` 3-tier convention (brainstorms → plans → solutions) is solid ADR structure — preserve it
- Date-prefix convention: brainstorms use date prefixes (temporal), plans/solutions don't (canonical). Document this in a brief `docs/README.md` if time permits.

**Security findings relevant to A1:**
- `open-webui/.env.example` has `OPEN_WEBUI_PORT_HTTP=3000` (conflicts with Onyx) — update to `3002`

---

## Track B: RMF Document Automation (Demo: March 5)

Builds on existing code in `basalt-stack/tools/rmf-generator/` and research in `docs/solutions/research-decisions/rmf-doc-automation-stack-selection.md`.

### B1: Template + Data Layer (no LLM needed)

- [ ] Re-tag MP template placeholders from `{...}` / `[defined ...]` to Jinja2 `{{ ... }}` syntax
- [ ] **Check for cross-run XML splits**: open template in Word, select each placeholder end-to-end, re-type it in one go (forces single XML run). Use `doc.get_undeclared_template_variables()` to verify all expected variables are found.
- [ ] For table-row loops use `{%tr for ... %}` / `{%tr endfor %}` tags (docxtpl paragraph-level control)
- [ ] Copy re-tagged template to `basalt-stack/tools/rmf-generator/templates/`
- [ ] Write `fill_template.py` with hardcoded context dict
- [ ] Verify output .docx in `output/` — check formatting preservation (fonts, headers, table styles)
- [ ] Commit and push

**Test**: `python fill_template.py --template templates/MP.docx --output output/MP-filled.docx` produces valid .docx. Open in Word and visually verify formatting matches original template (fonts, headers, table borders intact).

#### Research Insights (B1)

**docxtpl cross-run handling** (from Framework Docs Researcher):
- A "run" in Word is a contiguous sequence of characters with identical formatting. If you bold a single character mid-placeholder, Word splits the XML and Jinja2 tags break silently.
- The decision doc warns 5 of 30 MP placeholders may be split across runs. Detection: `doc.get_undeclared_template_variables()` will be missing the split ones.
- Prevention: type each `{{ placeholder }}` in one continuous keystroke in Word. Don't copy-paste from formatted text.
- docxtpl does NOT auto-merge split runs — you must fix them in the template.

**docxtpl API patterns:**
```python
from docxtpl import DocxTemplate
doc = DocxTemplate("templates/MP.docx")
context = {"system_name": "MERIDIAN", "organization": "Example Agency"}
doc.render(context)
doc.save("output/MP-filled.docx")
```

**RichText for styled content** (if any ODP values need bold/color):
```python
from docxtpl import DocxTemplate, RichText
rt = RichText()
rt.add("Annually", bold=True)
context = {"review_frequency": rt}
# In template: {{r review_frequency }}
```

### B2: Context Assembly Pipeline

- [ ] Build `loaders/oscal_loader.py` — parse `nist-800-53-catalog.json` for MP control definitions + ODP list
- [ ] Build `loaders/system_loader.py` — parse `notional_system.yaml` into Pydantic `SystemDescription`
- [ ] Build `generators/context_assembler.py` — merge system data + OSCAL data into docxtpl context dict
- [ ] Wire context assembler into `fill_template.py` (replace hardcoded dict)
- [ ] Update `loaders/__init__.py` to export the actual classes built
- [ ] Commit and push

**Test**: `python fill_template.py --template templates/MP.docx` fills deterministic fields (`{{ organization }}`, `{{ system_name }}`) correctly from YAML. Also verify OSCAL loader returns the expected 22 ODP definitions for MP family.

#### Research Insights (B2)

**OSCAL catalog structure** (10MB JSON): The catalog nests controls under `groups[].controls[]`. Each control has `params[]` with `id`, `label`, and `select.choices[]` for ODPs. Filter for `mp-*` controls.

**Pydantic model alignment** (from Python Reviewer):
- `control.py` already defines `ODPValue`, `ODPSet`, `NarrativeOutput`, `FieldSource` — these are the right building blocks
- The `SystemDescription` model in `system.py` has a `placeholder_map` property that returns a flat dict suitable for docxtpl context — use it directly
- Consider adding a `ControlDefinition` model to `control.py` for OSCAL-loaded data (the import was planned but never built)

### B3: LLM Integration + Mock Fallback + Demo Prep

- [ ] Define Pydantic schema for 22 MP ODP values (extend `ODPSet` in `control.py`)
- [ ] Build `llm/synthesizer.py` — send prompt + `response_format` JSON schema to LiteLLM
- [ ] **Test `response_format` passthrough**: Before writing the full synthesizer, test directly: `curl -X POST localhost:8000/v1/chat/completions -d '{"model":"gpt-oss-20b","response_format":{"type":"json_schema","json_schema":{"name":"test","schema":{"type":"object","properties":{"x":{"type":"string"}},"required":["x"]}}},"messages":[{"role":"user","content":"Return x=hello"}]}'`. If this fails, check `drop_params: true` in `litellm-config.yaml` — may need to set to `false` or switch to `hosted_vllm/` provider prefix.
- [ ] Add `--mock` flag that loads pre-generated JSON from `data/mock-mp-odp-values.json`
- [ ] Generate mock JSON via Claude (golden sample for demo fallback)
- [ ] Wire LLM output into context assembler
- [ ] Update `llm/__init__.py` to export `NarrativeSynthesizer`
- [ ] **Demo prep**: End-to-end run with `--mock`, attempt live run if vLLM available, build talking points
- [ ] Commit and push

**Test**: `python fill_template.py --mock` produces complete MP document with all 22 ODPs filled. If vLLM is running: `python fill_template.py` calls LiteLLM and produces output with trace visible in Langfuse at `localhost:3001`.

#### Research Insights (B3)

**`response_format` through LiteLLM** (CRITICAL — from Framework Docs + Spec Flow):
- LiteLLM v1.41.14 supports `response_format` with `json_schema` type
- Your config has `drop_params: true` — this silently drops parameters LiteLLM doesn't recognize for a given provider. If `response_format` is affected, the LLM returns unstructured text and the pipeline breaks silently.
- **Mitigation**: Consider switching the model prefix from `openai/gpt-oss-20b` to `hosted_vllm/gpt-oss-20b` in `litellm-config.yaml`. The `hosted_vllm/` prefix enables vLLM-specific parameter passthrough.
- **Fallback**: If proxy passthrough fails, call vLLM direct at port 8001 (bypassing LiteLLM). Traces won't appear in Langfuse, but the demo works.

**vLLM structured output API** (from Framework Docs Researcher):
```python
from openai import OpenAI

client = OpenAI(base_url="http://localhost:8000/v1", api_key="sk-120fb1a...")
completion = client.beta.chat.completions.parse(
    model="gpt-oss-20b",
    messages=[{"role": "system", "content": "..."}, {"role": "user", "content": "..."}],
    response_format=NarrativeOutput,  # Pass Pydantic class directly
)
parsed = completion.choices[0].message.parsed  # Already a NarrativeOutput instance
```

**LiteLLM authentication**: The RMF generator runs as a Python CLI on the host. It needs the LiteLLM master key (`sk-120fb1a...` from `litellm/.env`) as an env var or config. Decide: environment variable (`LITELLM_API_KEY`) or `.env` file in rmf-generator.

**Mock JSON specification**: Store at `data/mock-mp-odp-values.json`, schema matching `ODPSet.model_json_schema()`. Generate via Claude with the actual prompt + OSCAL context as input.

---

## Track C: Full Stack Deployment

These efforts can happen anytime, independent of RMF demo. C2 and C3 are independent of each other — both only need LiteLLM (port 8000), not vLLM directly.

### C1: vLLM Model Setup — DONE (`7ddced6`, 2026-03-24)

- [x] Download `openai/gpt-oss-20b` weights (3 safetensors shards, 12.9 GB)
- [x] Model weights at `D:/BASALT/models/gpt-oss-20b` (Windows path via 9p bridge — Docker Desktop WSL2 integration not enabled for Ubuntu; native Linux FS deferred)
- [x] `MODEL_PATH=D:/BASALT/models` in `.env`, `--model /models/gpt-oss-20b` in compose
- [x] `max-model-len` bumped to 8192, `HF_HUB_OFFLINE=1` added, health check uses `/v1/models` readiness
- [x] Start vLLM: model loads successfully, ~74 tokens/s generation throughput
- [x] LiteLLM routing: both `gpt-oss-20b` and `gpt-4` alias → vLLM (200 OK)
- [x] Chat completion verified: "NIST SP 800-53 is a catalog of security and privacy controls..."
- [x] Langfuse traces captured with input/output/latency (~1-2s)
- [x] WSL2 distros (Ubuntu + docker-desktop) relocated to `D:\WSL\` to free C:/ space

**Known issues discovered:**
- `--async-scheduling` incompatible with structured output — remove for B3
- LiteLLM v1.41.14 returns `content: null` for reasoning models (direct vLLM works)
- `hosted_vllm/` provider prefix requires LiteLLM >= v1.50 (using `openai/` instead)
- Langfuse Prisma migration `20241125124029` fails on fresh DB — resolved with `prisma migrate resolve`

#### Research Insights (C1)

**Performance findings:**
- `gpu-memory-utilization 0.85` on 48GB A6000 = 40.8GB for model. gpt-oss-20b at MXFP4 needs ~16GB. This leaves 24.8GB for KV cache — generous for single-GPU. Consider lowering to 0.80 if you see OOM during long sequences.
- `max-model-len 4096` may be too short for RMF use cases (long system prompts + OSCAL context + compliance narratives). Consider 8192 if VRAM allows.
- `--async-scheduling` flag: verify this exists in v0.10.2. If the container crashes on startup, remove it first.
- `--disable-log-requests`: consider removing during initial tuning to see request/response patterns, then re-enable.

**Model path critical note:**
- `MODEL_PATH=./models` in the current `.env` resolves relative to the compose file location on Windows. Docker mounts this through the WSL2 9p filesystem bridge, which is dramatically slower than native Linux filesystems.
- Best practice: store weights at a WSL2-native path like `/home/user/models/gpt-oss-20b/` and update the volume mount in docker-compose.yaml.

### C2: Onyx Deployment

- [ ] **Pin Onyx image tag**: Change `IMAGE_TAG=latest` to a specific version in `onyx/deployment/docker_compose/.env` (determine correct tag from Onyx releases)
- [ ] **Pre-stage Onyx embedding models**: Onyx's `inference_model_server` and `indexing_model_server` download HuggingFace models at startup. Set `HF_HUB_OFFLINE=1` in the compose environment and pre-populate the `model_cache_huggingface` volume. Investigate which models are required.
- [ ] Pull all 8 Onyx images (backend, web-server, model-server, vespa, postgres, redis, nginx, minio)
- [ ] Start Onyx: `cd onyx/deployment/docker_compose && docker compose up -d`
- [ ] Complete initial setup wizard at `http://localhost:3000` (note: `AUTH_TYPE=disabled` — wizard may behave differently)
- [ ] Configure LLM provider in Admin UI: OpenAI-compatible, `http://host.docker.internal:8000/v1`, master key
- [ ] Test chat query through Onyx → LiteLLM → vLLM (or mock if vLLM not up)
- [ ] Commit any .env changes

**Test**: Onyx UI responds at `localhost:3000`. If vLLM running: chat produces response with trace in Langfuse.

#### Research Insights (C2)

**Air-gap blocker** (from Architecture Strategist + Spec Flow Analyzer):
- Onyx model servers attempt HuggingFace downloads on first run for embedding/reranking models. On air-gapped networks this silently fails, breaking all RAG functionality.
- Must investigate: what specific models does Onyx download? Can they be pre-staged in the `model_cache_huggingface` Docker volume?
- Set `HF_HUB_OFFLINE=1` in the model server environment to prevent download attempts.

**Security note**: `AUTH_TYPE=disabled` means no login required. Acceptable for dev, but must enable before production (Track D).

### C3: Open-WebUI Deployment

- [ ] **Pin Open-WebUI image tag**: Change `OPENWEBUI_IMAGE=ghcr.io/open-webui/open-webui:main` to a specific version tag in `.env`
- [ ] Pull Open-WebUI image
- [ ] Start: `cd basalt-stack/web/open-webui && docker compose up -d`
- [ ] Configure OpenAI-compatible API endpoint in settings (`http://host.docker.internal:8000/v1`)
- [ ] Test chat
- [ ] Fix `open-webui/.env.example`: change port from 3000 to 3002 (conflicts with Onyx)

**Test**: Open-WebUI responds at `localhost:3002`. Chat works through LiteLLM.

---

## Track D: Hardening (Post-MVP)

Not conversation-sized — these are milestones tracked here for planning. Prioritize based on deployment timeline.

- **Air-Gap Packaging**: `docker save` all images (21+ containers across 5 stacks), pre-stage Python wheels, create offline installer script. Depends on C1-C3 complete. Note: circular dependency with C2/C3 on air-gapped target — run C1-C3 on connected dev machine first, then package.
- **~~Authentik SSO~~**: ~~Deploy Authentik, integrate with Onyx + Open-WebUI.~~ **DONE** (branch `feat/authentik-sso-integration`): Phase 1 core deployment, Phase 2 Open-WebUI SSO + security fixes, Phase 3 Onyx OIDC + cleanup. See `docs/plans/2026-03-17-001-feat-authentik-sso-portal-integration-plan.md`.
- **Secret Rotation**: Replace all dev secrets with production-grade values. Rotate: Langfuse init password (`"password"`), Onyx Postgres (`password`), Redis auth (`myredissecret` in Langfuse), ClickHouse default password, LiteLLM master key. Use `openssl rand -hex 32` for each.
- **Network Segmentation**: Docker network policies, remove `host.docker.internal` where possible, bind ports to `127.0.0.1`. Depends on Authentik.
- **Monitoring & Backup**: Langfuse dashboards, Postgres backup strategy, add log rotation to all compose stacks (only vLLM currently has `max-size`/`max-file`), log aggregation.
- **Multi-Family RMF**: Extend RMF generator to all 20 control families. Depends on B3 complete.
- **OWASP LLMSVS L2 Audit**: Full security audit against compliance matrix. Current Track D covers ~4 of 13 LLMSVS categories — gaps in: input validation (LLM01), output handling (LLM02), supply chain (LLM05), excessive agency (LLM08). See `docs/plans/basalt-compliance-matrix.md`.

### LACI v1.1 Alignment (Deferred)

- [ ] **D2: Networking model migration** — Migrate from `host.docker.internal` (host-routed) to LACI's shared Docker network model (`proxy` and `inference` external networks). Touches every compose file. Requires: `docker network create proxy inference`, update all compose files to join external networks, remove `extra_hosts` entries, test cross-stack communication.
- [ ] **D4: Two-part image reference pattern** — Adopt LACI's `${DOCKER_IMAGE_REPO}${IMAGE}` pattern across all `.env` and compose files. Enables single-variable registry swapping between dev, Forgejo, and air-gap.
- [ ] **Version alignment** — Upgrade to LACI v1.1 component versions: vLLM v0.17.1, LiteLLM v1.82.0, Langfuse v3.155.1, Postgres 18.3-alpine, Redis 8.6.1-trixie. Test each upgrade individually.

---

## Effort Dependency Graph

```
Track A (cleanup)        Track B (RMF demo)       Track C (deployment)
─────────────────        ──────────────────       ────────────────────
A0: Pre-Flight ─────────── prerequisite for B1+
      │
A1: Repo Cleanup         B1: Template Layer       C1: vLLM Model Setup
                               │                        │
                         B2: Context Assembly     ┌─────┴──────┐
                               │                  │            │
                         B3: LLM + Demo      C2: Onyx    C3: Open-WebUI
                                                  │            │
                                            ┌─────┴────────────┘
                                            ▼
                                      Track D: Hardening
```

- **A0** before everything — fixes broken imports and telemetry
- **A1** is independent — can run in parallel with B/C tracks
- **B1 → B2 → B3**: Sequential — each builds on the last
- **C1 → C2, C1 → C3**: vLLM needed for live inference, but C2 and C3 are independent of each other
- **B3 depends on C1** for live LLM integration (but `--mock` flag works without it)
- **All tracks are otherwise independent** — cleanup, RMF, and deployment can run in parallel

---

## Cross-Cutting Findings

### Docker Compose Inconsistencies (from Pattern Recognition)

Found across all 5 compose files — not blocking, but worth standardizing in a future cleanup:

| Issue | Detail | Recommendation |
|-------|--------|----------------|
| Image tag convention | 5 different patterns (`:-default`, `:?error`, no guard, baked-in, concatenation) | Standardize on `${IMAGE:?error}:${TAG:?error}` (LiteLLM style) |
| Restart policy | Mixed `always` vs `unless-stopped` | Pick `unless-stopped` (allows manual stop) |
| Health check tools | `curl`, `wget`, `redis-cli`, some missing entirely | Acceptable (driven by container base images), but add health check to Open-WebUI |
| Volume naming | Mixed prefixed (`langfuse_postgres_data`) vs generic (`data`, `postgres_data`) | Prefix all with service name to prevent collisions |
| Logging limits | Only vLLM has `max-size`/`max-file` | Add to all stacks (critical for air-gap where disk is finite) |
| Env syntax | Mixed list (`- KEY=val`) and mapping (`KEY: val`) in same file | Pick one per file |

### Security Findings (from Security Sentinel)

| Severity | Finding | Location |
|----------|---------|----------|
| CRITICAL | Langfuse telemetry active (air-gap violation) | `langfuse/.env` — fixed in A0 |
| CRITICAL | Langfuse password is literal `"password"` | `langfuse/.env` — fix in Track D |
| CRITICAL | Onyx `AUTH_TYPE=disabled` | `onyx/.env` — acceptable for dev, fix in Track D |
| HIGH | vLLM `ipc: host` reduces container isolation | `vllm/docker-compose.yaml` — required for GPU shared memory |
| HIGH | Onyx Redis has no auth | `onyx/docker-compose.yml` — fix in Track D |
| HIGH | Default/weak secrets across all services | All `.env` files — fix in Track D (Secret Rotation) |

### Performance Findings (from Performance Oracle)

| Item | Detail | Action |
|------|--------|--------|
| `gpu-memory-utilization 0.85` | Leaves 7.2GB free on 48GB. Generous for gpt-oss-20b but thin if running other GPU workloads | Monitor during C1; lower to 0.80 if OOM |
| `max-model-len 4096` | May be too short for RMF prompts (long OSCAL context + system prompt + narrative) | Consider 8192 during C1 tuning |
| `MODEL_PATH=./models` on Windows | 9p filesystem bridge adds 10-20x I/O overhead for model loading | Move to Linux FS path in C1 |
| 21 total containers | Significant resource pressure (CPU, RAM, disk I/O) on a single machine | Monitor during C2; consider stopping unused stacks |
| MinIO health check `1s` interval | Excessive; creates unnecessary load | Change to 30s in Langfuse compose |
| LiteLLM `health_check_interval: 300` | 5 minutes is too long to detect vLLM failures | Reduce to 60s |

### Deployment Findings (from Deployment Verification)

| Item | Detail | Action |
|------|--------|--------|
| Redis health checks lack auth | `redis-cli ping` without `-a` flag — may report false positives | Add auth to Redis health checks in LiteLLM + Langfuse compose |
| `.env` shell variable interpolation | `$POSTGRES_USER` in `.env` files doesn't expand in Docker Compose | Use literal values or move to compose `environment:` block |
| No Docker health check on LiteLLM | LiteLLM container has no healthcheck defined | Add `curl -f http://localhost:4000/health || exit 1` |
| No Docker health check on Open-WebUI | Open-WebUI container has no healthcheck defined | Add health check in compose |

---

## Stale Files to Delete (Comprehensive List)

Collected from all agents — superset of what was in original A1:

| File | Reason |
|------|--------|
| `LACI-Basalt-Migration.md` | Ollama-era, wrong GPU (RTX 4000 ADA), wrong architecture |
| `snips/` directory | Orphan screenshot, no references |
| `basalt-stack/inference/vllm/gpt-oss-120b/` | 4-GPU config for hardware we don't have |
| `basalt-stack/inference/langfuse/.litellm` | Pre-host-routing config, wrong host, stale secrets |
| `basalt-stack/README` | 3 lines referencing old `docker network create proxy inference` |
| `basalt-stack/inference/litellm/litellm-config.yaml.example` | References Pixtral-12B and Docker service names (pre-pivot) |
| `basalt-stack/.gitignore` | Redundant — root `**/.env` already covers everything |

---

## References

**vLLM:**
- [Structured Outputs](https://docs.vllm.ai/en/latest/features/structured_outputs/) — `response_format` with `json_schema`
- [GPT-OSS Recipes](https://docs.vllm.ai/projects/recipes/en/latest/OpenAI/GPT-OSS.html)
- [MXFP4 MoE PR #17888](https://github.com/vllm-project/vllm/pull/17888) — why v0.10.2+ required
- `/health` is liveness-only; use `/v1/models` for readiness

**LiteLLM:**
- [vLLM Provider (`hosted_vllm/`)](https://docs.litellm.ai/docs/providers/vllm) — better parameter passthrough than `openai/`
- [JSON Mode / Structured Output](https://docs.litellm.ai/docs/completion/json_mode)
- [Langfuse Integration](https://docs.litellm.ai/docs/observability/langfuse_otel_integration)

**Langfuse:**
- [Self-Hosting Config](https://langfuse.com/self-hosting/configuration) — `TELEMETRY_ENABLED=false`
- [OTEL Trace Ingestion](https://langfuse.com/self-hosting) — `/api/public/otel` endpoint

**docxtpl:**
- [Official Docs](https://docxtpl.readthedocs.io/en/latest/) — Jinja2 in .docx
- Cross-run issue: tags split across Word XML runs break silently. Use `doc.get_undeclared_template_variables()` to detect.
