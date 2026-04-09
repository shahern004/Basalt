---
title: "WSL2 + Portainer Pivot — Design Spec"
date: 2026-04-09
status: draft
category: spec
branch: feat/wsl2-portainer-pivot
tags:
  - infrastructure
  - wsl2
  - portainer
  - docker
  - laci-alignment
  - air-gap
related:
  - "[[basalt-development-roadmap|roadmap]]"
  - "[[2026-04-07-laci-updater-tool-design|laci-updater]]"
  - "[[2026-03-26-open-webui-custom-image-build-design|openwebui-build]]"
  - "[[authentik-sso-integration-log|authentik-log]]"
---

# WSL2 + Portainer Pivot — Design Spec

## Problem

Basalt currently runs on Docker Desktop (Windows), with cross-stack traffic flowing over `host.docker.internal` and model weights mounted through the 9p filesystem bridge from `D:\BASALT\models\`. This topology has accumulated problems that are no longer worth patching around:

- **Docker Desktop is a licensed, GUI-centric product** that does not cleanly map to the 25% of targets running bare-metal Linux — two topologies must be maintained, documented, and supported
- **`host.docker.internal` is a Docker Desktop convenience**, not a portable contract. The same compose files fail on bare Linux without rewrite
- **9p bridge-mounted model weights** cost 2–5 minutes per vLLM cold start. Disk I/O on model load is the dominant startup cost
- **`.wslconfig` mirrored-networking is unvalidated on the dev box.** It works on one personal machine, but the enabling steps were never captured and the Basalt deployment guide has no prerequisites section that reflects this
- **Day-2 operators do not have a GUI.** Users who are uncomfortable with `docker compose logs` and `docker exec` have no path to inspect a running stack, restart a container, or read a health check result. Per the user: *"having users dig into WSL2 basalt instance and using Docker CLI commands is complex for our skillset"*
- **LACI alignment drift is growing.** LACI v1.1 publishes stacks over a shared external `proxy` network; Basalt uses published-port hops through `host.docker.internal`. The further Basalt drifts structurally from LACI, the harder leadership buy-in becomes: *"From a corporate standpoint, the further we drift from LACI on our initial reveal demo, the more hesitation our leadership has to fund Basalt."*

This pivot removes Docker Desktop from the official runtime story, moves Docker into a dedicated WSL2 distro, adopts LACI's shared-network topology, and adds Portainer CE as a Day-2 ops GUI that does not replace compose files or the LACI Updater Tool as deployment sources of truth.

## Goals

1. **Docker Desktop removed from Basalt's runtime story.** Docker Engine runs natively inside a dedicated WSL2 distro (`basalt-host`). All `docker` commands work from `wsl -d basalt-host` and from Windows via WSL interop
2. **Single topology for Windows+WSL2 and bare Linux targets.** The Windows host becomes a thin outer layer whose only job is hosting a WSL2 distro; bare Linux targets skip the outer layer. Compose files, bootstrap script, and deployment guide are identical past that point
3. **LACI-aligned networking.** All six service stacks attach to a shared external Docker network named `proxy`. Cross-stack traffic uses Docker DNS service names. `host.docker.internal` disappears from Basalt compose files
4. **Portainer CE as the Day-2 ops GUI.** Single-host standalone deployment, adopts existing stacks via compose labels, reached through the Authentik front door. Deployment remains compose-first and LACI-Updater-driven — Portainer is not the source of truth
5. **Model weights on ext4, not 9p.** Gemma 4 weights live at `/opt/basalt/models/` inside the `basalt-host` distro. vLLM cold start under 60 seconds
6. **Gemma 4 26B-A4B (AWQ 4-bit) replaces gpt-oss-20b on this branch.** American-produced, Apache 2.0, LACI-allowlisted, fits in 20 GB A4000 VRAM with vision disabled
7. **Air-gap safe.** The entire pivot is shippable as a `wsl --export basalt-host` tarball plus the existing Basalt repo. No new internet dependencies at deploy time
8. **LACI structural-alignment diff pass.** Every service is walked against its LACI counterpart; trivial deltas fixed inline, non-trivial deltas flagged as follow-ups

## Out-of-Scope

- ❌ **§5f custom enrollment flow.** Parked. Default Authentik enrollment is MORE LACI-aligned, not less — LACI ships zero Authentik customization (48-line compose, 13-line README, no blueprints). Federal controls (AC/IA/AU/SC) are satisfied by vanilla Authentik without §5f
- ❌ **Upgrading Authentik to match LACI's 2023.10.6 pin.** Version drift is allowlisted; Basalt keeps its newer Authentik
- ❌ **Benchmarking gpt-oss-20b against Gemma 4 26B-A4B.** Recorded as future work on a different branch
- ❌ **Renaming the shared network to `basalt-net`** or any non-LACI name. `proxy` is the locked LACI-aligned name
- ❌ **Network segmentation hardening.** Remains a Phase 7 concern; this branch establishes the single `proxy` network, not a multi-network security posture
- ❌ **Co-tenant migration beyond Forgejo.** Forgejo is the only non-Basalt container on the dev box per user confirmation. Forgejo migration is a §4.6 **prerequisite**, not a scope addition
- ❌ **Portainer Business Edition or multi-host orchestration.** Single-host CE only
- ❌ **Replacing compose files or the LACI Updater as deployment sources of truth.** Portainer adopts what compose+LACI deploy; it does not deploy
- ❌ **Auto-relocation of files during a future LACI structural reorg** (LACI v2.0 hypothetical). Delegated to the LACI Updater Tool's diff report
- ❌ **Mirrored-networking firewall-rule debugging.** User confirmed firewalls are not the issue on their home PC; closed topic
- ❌ **HTTP endpoint probes and end-to-end tracing in smoke tests.** Section 5 smoke = containers healthy + one chat trace end-to-end. Broader probing is deferred

## User Experience

### Operator (day-2, most common)

```
Browser → https://auth.basalt.local
  → Authentik login
  → App Launcher shows: Onyx, Open-WebUI, Portainer
  → Click "Portainer"
  → Stacks view: 6 adopted stacks with health indicators
  → Drill into container → Logs / Console / Restart
```

Operators never touch `wsl`, `docker`, or service URLs directly.

### Developer / maintainer (deployment, rare)

```bash
# Windows PowerShell
wsl -d basalt-host

# Inside basalt-host
cd /opt/basalt/basalt-stack-v1.0
docker network create proxy    # one-time per host
cd inference/vllm && docker compose up -d && cd -
cd inference/langfuse && docker compose up -d && cd -
cd inference/litellm && docker compose up -d && cd -
cd web/authentik && docker compose up -d && cd -
cd web/onyx && docker compose up -d && cd -
cd web/open-webui && docker compose up -d && cd -
cd ops/portainer && docker compose up -d && cd -
```

The startup sequence in `CLAUDE.md` stays textually identical; only the invocation context (`wsl -d basalt-host` instead of Docker Desktop's WSL integration) changes.

### First-time host bootstrap (once per machine)

```powershell
# Windows PowerShell (host prereq check)
.\scripts\check-host-prereqs.ps1
```

```bash
# Inside basalt-host (one-time bring-up)
./scripts/bootstrap-basalt-host.sh
```

The bootstrap script is canonical; the deployment guide explains the script with a dated footer: `Last synced with bootstrap-basalt-host.sh: <commit-hash>`.

## Target Architecture

### Host layer

```
┌───────────────────────────────────────────────────────────────┐
│ Windows 11 host                                               │
│                                                               │
│  WSL2 subsystem                                               │
│  ┌─────────────────────────┐    ┌─────────────────────────┐   │
│  │ Ubuntu (existing)       │    │ basalt-host (new)       │   │
│  │ D:\WSL\Ubuntu\          │    │ D:\WSL\basalt-host\     │   │
│  │ untouched; user shell   │    │ Ubuntu 24.04            │   │
│  └─────────────────────────┘    │ Docker Engine (native)  │   │
│                                 │ nvidia-container-toolkit│   │
│                                 │ /opt/basalt/models/     │   │
│                                 │ /opt/basalt/basalt-     │   │
│                                 │   stack-v1.0/           │   │
│                                 │ /opt/dev/forgejo/       │   │
│                                 └─────────────────────────┘   │
│                                                               │
│  .wslconfig (user profile) — mirrored networking enabled      │
└───────────────────────────────────────────────────────────────┘
```

Bare-Linux targets collapse the outer box; the `basalt-host` contents map 1:1 onto the Linux root filesystem.

### Docker network topology

```
        ┌─────────────── Docker network: proxy (external) ──────────────┐
        │                                                               │
        │   ┌──────────┐  ┌──────────┐  ┌──────────┐                    │
        │   │  vLLM    │  │ LiteLLM  │  │ Langfuse │                    │
        │   └──────────┘  └──────────┘  └──────────┘                    │
        │                                                               │
        │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐   │
        │   │Authentik │  │   Onyx   │  │Open-WebUI│  │  Portainer  │   │
        │   └──────────┘  └──────────┘  └──────────┘  └─────────────┘   │
        │                                                               │
        └───────────────────────────────────────────────────────────────┘
                                  │
                                  │ published ports (only what MUST escape the network)
                                  │
                     ┌────────────┼────────────┐
                     ▼            ▼            ▼
                  :443 (ATK)  :9000 (Prt)  :8001/:8000 (dev only)
```

Rules:

- **Every stack declares `proxy` as an external network.** Cross-stack traffic uses service names (`vllm:8001`, `litellm:4000`, `langfuse-web:3000`)
- **`host.docker.internal` is removed from all Basalt compose files**
- **Published ports shrink** to only what must be reachable from outside the stack runtime. Rule of thumb: published iff the browser, an IDE, or an external tool needs it. Everything else stays on the network
- **Intra-stack traffic still uses in-stack service names** (`redis`, `postgres`) unchanged

### Published-port table (target state)

| Service         | Port | Published? | Reason                                                 |
|-----------------|------|------------|--------------------------------------------------------|
| Authentik HTTPS | 443  | ✅         | Front door; browser-reachable                          |
| Authentik HTTP  | 9000 | ✅         | Internal OIDC discovery (Phase 7 will remove)          |
| Portainer HTTPS | 9443 | ✅ dev     | Fallback admin path; prod goes through Authentik proxy |
| vLLM            | 8001 | ✅ dev     | Direct smoke tests; removed in prod bundle             |
| LiteLLM         | 8000 | ✅ dev     | Direct smoke tests; removed in prod bundle             |
| Langfuse web    | 3001 | ⚠️ dev only | Removed once Authentik proxies Langfuse               |
| Onyx            | 3000 | ❌         | Reached through Authentik proxy provider              |
| Open-WebUI      | 3002 | ❌         | Reached through Authentik proxy provider             |

"dev only" means the `docker-compose.dev.yaml` override publishes the port; the base compose does not.

### User flows

**Chat flow (unchanged intent, new plumbing):**
```
Browser → auth.basalt.local → Authentik login
  → onyx.basalt.local → Authentik proxy provider → onyx:3000
  → onyx → litellm:<internal-port> (by service name, NOT host.docker.internal)
  → litellm → vllm:<internal-port> (by service name)
  → vllm → Gemma 4 26B-A4B (AWQ 4-bit)
  → trace → langfuse-web:<internal-port> (by service name)
```

**Ops flow (new):**
```
Browser → auth.basalt.local → Authentik login
  → portainer.basalt.local → Authentik proxy provider → portainer:9000
  → Portainer adopts /var/run/docker.sock, shows all 6 stacks as "external"
  → Operator views logs / restarts containers / inspects health
```

## Compose File Refactor Pattern

### Canonical per-stack pattern

Every compose file gains the same network stanza:

```yaml
networks:
  default:
    name: <stack>_internal    # keeps intra-stack traffic private
  proxy:
    external: true            # CRITICAL: must be `true`, see R3 below
```

Services that need to be reachable cross-stack attach to both:

```yaml
services:
  vllm:
    networks:
      - default
      - proxy
```

Services that only talk within their own stack (databases, redis, worker queues) attach only to `default`.

### Cross-stack attachment table

| Stack       | Services on `proxy` network                         | Reason                                        |
|-------------|-----------------------------------------------------|-----------------------------------------------|
| vllm        | `vllm`                                              | LiteLLM reaches it by name                    |
| litellm     | `litellm`                                           | Onyx / Open-WebUI reach it by name            |
| langfuse    | `langfuse-web`                                      | LiteLLM posts traces by name                  |
| authentik   | `authentik-server`                                  | All web UIs reach it for OIDC                 |
| onyx        | `web_server` (or LACI-aligned name)                 | Authentik proxy provider forwards to it      |
| open-webui  | `open-webui`                                        | Authentik proxy provider forwards to it      |
| portainer   | `portainer`                                         | Authentik proxy provider forwards to it      |

### Migration diff template

Each compose file follows the same mechanical diff:

```diff
-    extra_hosts:
-      - "host.docker.internal:host-gateway"
+    networks:
+      - default
+      - proxy
-    environment:
-      LITELLM_URL: http://host.docker.internal:8000
+    environment:
+      LITELLM_URL: http://litellm:4000

 networks:
+  default:
+    name: <stack>_internal
+  proxy:
+    external: true
```

`.env` files lose all `host.docker.internal` occurrences; URLs collapse to `http://<service-name>:<internal-port>`.

### Dev override pattern

`docker-compose.dev.yaml` per stack adds back the published ports that were removed from the base compose:

```yaml
# docker-compose.dev.yaml (example: vllm)
services:
  vllm:
    ports:
      - "8001:8001"
```

Usage: `docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d`. Deployment guide documents when to use the override (active development / smoke tests) versus the base compose (operator use).

### Bootstrap compose (Portainer stack)

`ops/portainer/docker-compose.yaml` is a new compose file that brings up Portainer CE as a single container, attached to `proxy`, binding `/var/run/docker.sock` read-only where possible. No publishing of port 9443 in the base compose; the dev override publishes it for first-run setup.

## Host Prep & Distro Lifecycle

### Prerequisites (Windows host)

1. Windows 11, WSL2 enabled, `wsl --version` returns 2.0+
2. NVIDIA driver installed on the Windows host (WSL CUDA passes through the host driver)
3. `.wslconfig` at `$env:USERPROFILE\.wslconfig` with mirrored networking enabled — enabling steps are TBD (U4: user recovers from home PC in Phase 0)
4. `scripts/check-host-prereqs.ps1` runs and returns green on all checks (WSL version, driver version, `.wslconfig` presence, distro name not taken)

### Creating `basalt-host`

1. Start from Ubuntu 24.04 rootfs tarball (pre-staged, not downloaded at deploy time)
2. `wsl --import basalt-host D:\WSL\basalt-host\ <rootfs.tar> --version 2`
3. `wsl -d basalt-host` → run `scripts/bootstrap-basalt-host.sh`

`bootstrap-basalt-host.sh` responsibilities (idempotent):
- Install Docker Engine + nvidia-container-toolkit from pre-staged debs
- Enable systemd if not already on
- Create `/opt/basalt/`, `/opt/basalt/models/`, `/opt/dev/forgejo/`
- Clone or copy the Basalt repo into `/opt/basalt/basalt-stack-v1.0/`
- Run `docker network create proxy` (idempotent guard)
- Print next-step instructions referencing the deployment guide

### Model weights layout

```
/opt/basalt/models/
└── gemma-4-26B-A4B-it-AWQ-4bit/
    ├── config.json
    ├── tokenizer.json
    ├── *.safetensors
    └── ...
```

vLLM container mounts `/opt/basalt/models/` → `/models/` read-only. 9p bridge disappears.

### Lifecycle operations

| Op                     | Command                                                     |
|------------------------|-------------------------------------------------------------|
| Enter the distro       | `wsl -d basalt-host`                                        |
| Stop the distro        | `wsl --terminate basalt-host`                               |
| Set as default         | `wsl --set-default basalt-host`                             |
| Export for air-gap     | `wsl --export basalt-host D:\staging\basalt-host-vX.Y.tar`  |
| Re-import on new host  | `wsl --import basalt-host <path> basalt-host-vX.Y.tar`      |

The exported tarball is Basalt's new air-gap happy path: one file containing OS + Docker Engine + images + model weights + the Basalt repo.

### Docker Desktop removal (§4.6)

Docker Desktop removal is the **final** step of this branch. Preconditions:

1. Forgejo migrated to `/opt/dev/forgejo/` on `basalt-host`; clone+push smoke passes
2. All six Basalt stacks verified healthy on `basalt-host` (smoke from Success Criteria)
3. Portainer reachable through Authentik and showing all six stacks adopted
4. `wsl --export basalt-host` tested; re-importable archive produced

Only then: uninstall Docker Desktop from Windows, reboot, confirm `docker` commands still work from inside `basalt-host` and from Windows via `wsl -d basalt-host -- docker ps`.

## Model Swap: gpt-oss-20b → Gemma 4 26B-A4B (AWQ 4-bit)

### Decision

- **Model:** `google/gemma-4-26B-A4B-it` (51.6 GB BF16)
- **Serving quant:** `cyankiwi/gemma-4-26B-A4B-it-AWQ-4bit` (~13 GB weights)
- **Architecture:** Sparse MoE — 25.2B total params, 3.8B active per token, 128 experts (8 active + 1 shared)

### Why AWQ 4-bit

A4000 (20 GB VRAM) cannot hold 51.6 GB BF16. AWQ 4-bit fits in ~15–17 GB with weights + KV cache + vision encoder disabled, leaving headroom for `--max-model-len 8192` and `--max-num-seqs 2`. Rejected alternatives: NVFP4 (Blackwell-only), GGUF (slow in vLLM), Intel AutoRound (less mature), official BF16 (too big).

### vLLM flags (target .env)

```
VLLM_MODEL=/models/gemma-4-26B-A4B-it-AWQ-4bit
VLLM_ARGS=--quantization awq \
          --max-model-len 8192 \
          --limit-mm-per-prompt image=0,audio=0 \
          --gpu-memory-utilization 0.90 \
          --max-num-seqs 2
```

`--async-scheduling` is NOT set — still incompatible with structured output (existing gotcha from gpt-oss-20b era). `--reasoning-parser gemma4` is deliberately omitted; see R1 below.

### LiteLLM routing

`inference/litellm/litellm-config.yaml` gets a new model entry for `gemma-4-26B-A4B-it`. The `gpt-4` alias remains and points to the new Gemma model so downstream clients do not reconfigure. OpenAI-compatible surface is unchanged.

### Fallback

If Gemma 4 friction proves intractable during implementation, roll back to `gpt-oss-20b` on this same branch without rewriting the spec. Rollback is a Phase-1 implementation deliverable (documented in the phase's runbook), not a pre-written rollback branch.

## Risks & Known Unknowns

### Risks (R1–R6)

**R1 — Gemma 4 vLLM friction.** Known issues at the time of research (2026-04-09):
- vLLM MoE boot crash (`top_k is None in MoEMixin.recursive_replace`, GH #39066)
- Structured output weirdness on Gemma 4 31B (#39071); 26B-A4B untested
- Vision encoder shape mismatch (#39061) — workaround: `--limit-mm-per-prompt image=0,audio=0`
- `--reasoning-parser gemma4` silently disables xgrammar when `enable_thinking=false` (#39130)

Posture: treat as friction to work through, not pre-pivot blockers. If any prove intractable, roll back to gpt-oss-20b per the fallback plan above.

**R2 — Mirrored networking enable procedure is unknown.** User's home PC works via "a script of some sort" whose contents are not captured. Resolution: Phase 0 recovery task (U4). If unrecoverable, this becomes a documented manual step in the host prereq guide.

**R3 — `proxy: external: false` silent failure.** If any compose file omits `external: true` on the `proxy` network, Docker creates a project-scoped `<project>_proxy` network instead and cross-stack DNS lookups return NXDOMAIN with no log line. This is a real bug the user already hit on their home PC. Mitigation: a 100-word gotcha explainer at `docs/guides/compose-networking.md` plus a pre-deploy lint check that greps every compose file for the external flag.

**R4 — Portainer adoption of pre-existing stacks.** Portainer adopts via compose labels; stacks deployed before Portainer is up may need re-adoption after Portainer comes online. Mitigation: startup sequence brings Portainer up **last**, after all six Basalt stacks, so adoption happens against stacks already running and labeled.

**R5 — Forgejo volume migration loses data.** Dev git host is the user's only non-Basalt container. Mitigation: volume backup via `tar` → restore into fresh volumes on basalt-host → verify clone/push BEFORE Docker Desktop removal. Rollback: Docker Desktop is still installed until §4.6, so a broken migration means starting Docker Desktop back up.

**R6 — LACI structural diff surfaces more deltas than budgeted.** The LACI alignment pass walks 6 services and timeboxes one session each. If a service turns up a large delta (e.g., Onyx structure differs meaningfully from LACI's Onyx), the delta is flagged as a follow-up track rather than absorbed into this branch. Out-of-scope guardrail enforced.

### Known Unknowns (U1–U8)

| #  | Unknown                                   | Resolution path                                     |
|----|-------------------------------------------|-----------------------------------------------------|
| U1 | vLLM release-note state on Gemma 4        | Phase 1 — release notes check                       |
| U2 | Gemma 4 quant options + VRAM empirical    | Phase 1 — HF model card (user will do, not Claude)  |
| U3 | Gemma 4 `response_format` on 26B-A4B      | Phase 2 — smoke test                                |
| U4 | Mirrored-networking enable procedure      | Phase 0 — user recovers from home PC                |
| U5 | `.wslconfig` experimental flags needed    | Phase 0 — trial and error                           |
| U6 | LACI structural delta count               | Phase 3 — diff pass                                 |
| U7 | Forgejo volume migration smoke            | Phase 4 — migration rehearsal                       |
| U8 | Portainer Authentik proxy-provider config | Phase 3 — manual setup + capture as blueprint       |

## Files to Create / Modify

### New files

```
docs/superpowers/specs/2026-04-09-wsl2-portainer-pivot-design.md  ← this file
docs/guides/compose-networking.md                                 ← R3 gotcha (100 words)
docs/guides/deployment-guide-wsl2.md                              ← sibling of deployment-guide-dev.md
scripts/bootstrap-basalt-host.sh                                  ← idempotent host setup
scripts/check-host-prereqs.ps1                                    ← Windows prereq validator
ops/portainer/docker-compose.yaml                                 ← new stack
ops/portainer/docker-compose.dev.yaml                             ← publishes :9443 for first-run
```

### Modified compose files (networking refactor)

```
inference/vllm/docker-compose.yaml
inference/litellm/docker-compose.yaml
inference/langfuse/docker-compose.yaml
web/authentik/docker-compose.yaml
web/onyx/docker-compose.yaml
web/open-webui/docker-compose.yaml
```

Each gains `proxy: external: true`, cross-stack service attachments, service-name URLs, removal of `host.docker.internal`, and removal of non-essential published ports. Each gains a sibling `docker-compose.dev.yaml` that restores dev-only published ports.

### Modified configs

```
inference/litellm/litellm-config.yaml    ← add gemma-4-26B-A4B-it, preserve gpt-4 alias
inference/vllm/.env                      ← model path + AWQ/MoE flags
inference/*/.env                         ← host.docker.internal → service names
web/*/.env                               ← host.docker.internal → service names
$env:USERPROFILE\.wslconfig              ← (host, not in repo) mirrored networking
```

### Updated docs

```
CLAUDE.md                                ← new gotchas, new diagram, Gemma 4 swap, startup sequence unchanged textually
MEMORY.md (auto-memory)                  ← architecture decisions table updated
project_next_steps.md                    ← §5f parked section with intent/bug/baseline/resume trigger
```

## Success Criteria

1. Docker Desktop uninstalled from the Windows host. `docker` commands work from `wsl -d basalt-host` and from Windows via `wsl -d basalt-host -- docker <cmd>`
2. All six Basalt service stacks start cleanly via the `CLAUDE.md` startup sequence on the new topology, with no changes to the textual command list
3. Portainer UI reachable through the Authentik front door; all six stacks visible as adopted external stacks
4. E2E smoke passes: browser → Authentik → Onyx → LiteLLM → vLLM (Gemma 4 26B-A4B) → Langfuse trace recorded
5. vLLM cold start < 60 seconds (ext4 vs 9p proof)
6. `wsl --export basalt-host` produces a re-importable tarball; re-import on a clean host reproduces the stack without internet access
7. LACI structural-alignment diff pass completed; every delta either fixed inline or recorded as a follow-up with justification
8. Documentation debt closed:
   - `deployment-guide-wsl2.md` covers the `docker-compose.dev.yaml` pattern and when to use it
   - Database operations runbook documents Portainer Console path (day-2) and raw `docker exec` path (scripted), one paragraph per DB: Langfuse PG, Authentik PG, Onyx PG, ClickHouse, Vespa, all Redis instances

## Phased Rollout (preview — detailed breakdown belongs in the plan)

| Phase | Theme                               | Gate to next phase                                    |
|-------|-------------------------------------|-------------------------------------------------------|
| 0     | Host prereqs + `.wslconfig` recovery | `check-host-prereqs.ps1` green                        |
| 1     | `basalt-host` distro + bootstrap    | `docker ps` works inside distro; `proxy` network exists |
| 2     | Compose networking refactor         | All 6 stacks up, healthy, cross-stack DNS works       |
| 3     | Portainer + Authentik proxy provider | Portainer reachable via Authentik; stacks adopted    |
| 4     | Forgejo migration                   | Clone+push smoke passes on `basalt-host`              |
| 5     | Docker Desktop removal (§4.6)       | Uninstall + reboot + smoke still green                |
| 6     | LACI structural-alignment diff pass | Every service walked; deltas fixed or flagged        |
| 7     | Air-gap export rehearsal            | `wsl --export` produces re-importable tarball        |

## Do Not Do (decisions locked during brainstorm)

- ❌ Do not re-open WebFetch policy. The 2026-04-09 Gemma 4 research lift was one-time, not a general policy change
- ❌ Do not reopen the mirrored-networking firewall-rule angle. User confirmed firewalls were not the issue
- ❌ Do not add §5f back to scope. Default Authentik enrollment is the LACI-aligned choice
- ❌ Do not rename the network to `basalt-net` or anything non-LACI
- ❌ Do not pin Authentik to LACI's 2023.10.6 — version drift is allowlisted
- ❌ Do not expand co-tenant migration beyond Forgejo
- ❌ Do not attempt to absorb large LACI structural deltas into this branch — flag as follow-ups
- ❌ Do not treat Portainer as a deployment source of truth; compose + LACI Updater remain canonical
