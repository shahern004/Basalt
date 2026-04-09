---
title: "Basalt Stack — Developer Deployment Guide"
date: 2026-04-07
status: active
category: guide
tags:
  - deployment
  - developer
  - docker
  - setup
aliases:
  - deployment-guide
  - dev-deploy
related:
  - "[[basalt-system-design|system-design]]"
  - "[[basalt-development-roadmap|roadmap]]"
  - "[[vllm-gpt-oss-20b-version-requirements|vllm-version]]"
  - "[[clickhouse-alpine-healthcheck-fix|clickhouse-fix]]"
  - "[[authentik-sso-integration-log|authentik-log]]"
---

# Basalt Stack — Developer Deployment Guide

**Version:** 1.1
**Date:** 2026-04-07
**Environment:** Connected dev machine (internet access for image pulls and model download). This is a *dev* workflow — production deployment onto the real air-gapped network uses pre-staged images and pre-downloaded weights (see Phase 5 in the roadmap).
**Endstate:** Full stack running with GPT-OSS:20B accessible via Authentik SSO portal
**Repo layout:** Post-LACI flat structure — `inference/`, `web/`, `tools/`, `builds/` at the repo root (no `basalt-stack/` subdirectory prefix).

---

## Table of Contents

1. [Prerequisites](#section-0--prerequisites--environment-validation)
2. [Model Weights Download](#section-1--model-weights-download)
3. [vLLM — Inference Engine](#section-2--vllm-inference-engine)
4. [Langfuse — Observability](#section-3--langfuse-observability)
5. [LiteLLM — LLM Gateway + vLLM Readiness](#section-4--litellm-llm-gateway--vllm-readiness-check)
6. [Authentik — SSO Portal](#section-5--authentik-sso-portal)
7. [Open-WebUI — Chat Interface + SSO](#section-6--open-webui-chat-interface--sso-integration)
8. [Onyx — AI Platform + OIDC](#section-7--onyx-ai-platform--oidc-integration)
9. [Final Verification](#section-8--final-verification--smoke-tests)
10. [Troubleshooting](#appendix-a--troubleshooting)
11. [Quick Reference](#appendix-b--quick-reference)

---

## Deployment Strategy

vLLM model loading takes **5-10 minutes** — the longest startup in the stack. This guide starts vLLM first, then uses that wait time to bring up Langfuse and LiteLLM. By the time the inference layer is verified, you're ready for the Authentik SSO and UI services.

```
Timeline (approximate):
────────────────────────────────────────────────────────────
 0 min   Start vLLM (model loading begins in background)
 1 min   Start Langfuse (6 containers, ~60s to healthy)
 3 min   Start LiteLLM (3 containers, ~30s to healthy)
 5 min   Verify vLLM ready → test inference pipeline end-to-end
10 min   Start Authentik, generate TLS cert, configure admin UI
20 min   Start Open-WebUI, configure SSO proxy
25 min   Start Onyx, configure OIDC
35 min   Full stack verification
────────────────────────────────────────────────────────────
```

---

## Section 0 — Prerequisites & Environment Validation

### Hardware Requirements

| Component | Requirement |
|-----------|-------------|
| GPU (dev, current) | NVIDIA RTX A4000 (20 GB VRAM) — forces 4-bit quantization, tight KV cache, `--max-num-seqs 2` |
| GPU (prod target) | NVIDIA RTX A6000 (48 GB VRAM) or equivalent — procurement pending as of 2026-04-09 |
| RAM | 32 GB minimum (64 GB recommended for ~25 containers) |
| Disk | 100 GB free (model weights ~40 GB + Docker images ~50 GB) |
| OS | Windows 11 Pro with WSL2 |

### Software Requirements

| Software | Version | Check Command |
|----------|---------|---------------|
| Docker Desktop | Latest with WSL2 backend | `docker compose version` |
| NVIDIA Container Toolkit | Latest | `nvidia-smi` (dev box: should show A4000; prod target: A6000) |
| WSL2 | Ubuntu or Debian distro | `wsl --list --verbose` |
| Git | Any | `git --version` |
| OpenSSL | Any (for cert generation) | `openssl version` |

### Pre-Flight Checks

**PowerShell (primary shell for this guide — Basalt dev runs on Windows):**
```powershell
# 1. Verify Docker is running with GPU support
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi

# 2. Verify Docker Compose v2 (Docker Desktop ships v2 by default)
docker compose version
# Expected: Docker Compose version v2.x.x

# 3. Check available disk space on D:\ (where model weights + the Docker disk image live)
Get-PSDrive D | Select-Object Used,Free
```


### Hosts File Setup

Add these entries **now** (requires admin elevation on Windows). This enables `*.basalt.local` subdomain routing for Authentik SSO.

**Windows:** Edit `C:\Windows\System32\drivers\etc\hosts` as Administrator.
**WSL2:** Edit `/etc/hosts` (may need `sudo`).

```
# Basalt Stack — SSO Subdomains
127.0.0.1  auth.basalt.local
127.0.0.1  webui.basalt.local
127.0.0.1  onyx.basalt.local
127.0.0.1  rmf.basalt.local
```

> **Note:** Use `127.0.0.1` when accessing from the server itself. If other machines on the network need access, replace with the server's LAN IP and add entries to each client's hosts file.

**Verify:**

```powershell
# PowerShell / cmd
ping -n 1 auth.basalt.local
```
```bash
# WSL2 / Git Bash alternate — note the flag flip (-c vs -n)
ping -c 1 auth.basalt.local
```
Either form should resolve to `127.0.0.1`.

### Clone/Verify Repository

The repo lives at `D:\BASALT\Basalt-Architecture\basalt-stack-v1.0`. All commands in this guide assume you run them from that directory (the "repo root") and most use `docker compose -f <stack>/docker-compose.yaml ...` so you don't need to `cd` around between stacks.

```powershell
# PowerShell (primary)
cd D:\BASALT\Basalt-Architecture\basalt-stack-v1.0

# Sanity check — post-LACI flat layout, no basalt-stack/ prefix.
# Test-Path is PowerShell-native and returns True/False per file.
Test-Path inference\vllm\docker-compose.yaml
Test-Path web\authentik\docker-compose.yaml
Test-Path web\onyx\docker-compose.yaml
```

```bash
# WSL2 / Git Bash alternate
cd /mnt/d/BASALT/Basalt-Architecture/basalt-stack-v1.0   # WSL2
# cd /d/BASALT/Basalt-Architecture/basalt-stack-v1.0     # Git Bash

ls inference/vllm/docker-compose.yaml
ls web/authentik/docker-compose.yaml
ls web/onyx/docker-compose.yaml
```

> **Shell compatibility note:** Docker Desktop on Windows exposes the same `docker` / `docker compose` CLI to both PowerShell and WSL2 bash, but historically we've hit intermittent WSL2-side bind-mount and signal-forwarding issues when driving Docker Desktop from inside WSL2. **Use PowerShell for the deployment workflow.** Drop into WSL2 only for tasks that genuinely require Linux tooling (e.g., `huggingface-cli download` in §1, if you prefer it there).

- [ ] Docker running with GPU support
- [ ] `nvidia-smi` shows an RTX card matching your target (A4000 on dev bench, A6000 on prod target when available)
- [ ] Hosts file updated with `*.basalt.local` entries
- [ ] Repository present with all compose files

---

## Section 1 — Model Weights Download

Download `openai/gpt-oss-20b` from HuggingFace. This is the largest single artifact in the stack (~13 GB across 3 safetensors shards for the MXFP4-quantized build; full checkout is ~40 GB if you also pull the original-precision files).

### Storage Location — What the Reference Deployment Uses

The validated C1 deployment (2026-03-24) stores weights at **`D:\BASALT\models\gpt-oss-20b`** on the Windows host, mounted into the vLLM container by Docker Desktop. This is intentional:

- Docker Desktop accepts Windows-style paths directly, so no path translation is needed.
- First-load startup adds ~2–5 minutes (model shards stream from NTFS into the container).
- After load, weights live entirely in GPU VRAM. Inference latency is unaffected by disk speed from that point on.
- Keeping weights on `D:\` lets you inspect them from Windows tooling and survive WSL2 distro rebuilds without copying.

### Download Steps

**PowerShell (primary) — requires Python + `pip` on PATH:**
```powershell
# Option A — huggingface-cli (recommended, resumable)
pip install huggingface-hub
huggingface-cli download openai/gpt-oss-20b `
  --local-dir D:\BASALT\models\gpt-oss-20b `
  --local-dir-use-symlinks False

# Option B — git lfs
git lfs install
git clone https://huggingface.co/openai/gpt-oss-20b D:\BASALT\models\gpt-oss-20b
```
> PowerShell uses backtick (`` ` ``) for line continuation, not backslash. Don't paste bash-style `\` continuations into PS — it won't parse.

**WSL2 / Git Bash alternate (use this if your Python toolchain lives in WSL2):**
```bash
pip install huggingface-hub
huggingface-cli download openai/gpt-oss-20b \
  --local-dir /mnt/d/BASALT/models/gpt-oss-20b \
  --local-dir-use-symlinks False
```

### Update vLLM Configuration

Edit `inference/vllm/.env` and set:

```env
MODEL_PATH=D:/BASALT/models
```

> **How the mount works:** `inference/vllm/docker-compose.yaml` mounts `${MODEL_PATH}:/models` and passes `--model /models/gpt-oss-20b` (or equivalent) to vLLM. `MODEL_PATH` is the *parent* directory, not the model directory itself. Docker Desktop accepts `D:/BASALT/models` (forward slashes) as a bind-mount source — **use forward slashes in `.env`, not backslashes**, so the value is interpreted correctly by Docker Compose regardless of which shell invoked it.

### Verify Download

```powershell
# PowerShell (primary)
Get-ChildItem D:\BASALT\models\gpt-oss-20b | Select-Object Name,Length
# Expected: config.json, tokenizer.json, generation_config.json, *.safetensors (3 shards), etc.
```
```bash
# WSL2 / Git Bash alternate
ls /mnt/d/BASALT/models/gpt-oss-20b/
```

- [ ] Model weights present under the path referenced by `MODEL_PATH`
- [ ] `MODEL_PATH` updated in `inference/vllm/.env`
- [ ] Directory contains `config.json` and `*.safetensors` shards

---

## Section 2 — vLLM (Inference Engine)

Start vLLM **first** — model loading takes 5-10 minutes. You'll do other work while it loads.

### Configuration Review

| Setting | Value | File |
|---------|-------|------|
| Image | `vllm/vllm-openai:v0.10.2` | `.env` |
| Port | `8001` (host) → `8000` (container) | `.env` |
| Model | `openai/gpt-oss-20b` | `docker-compose.yaml` command |
| GPU memory (dev / A4000 20 GB) | 90% of 20 GB = 18 GB | compose command — tight, requires 4-bit quant + `--max-num-seqs 2` |
| GPU memory (prod / A6000 48 GB) | 85% of 48 GB = 40.8 GB | compose command — generous |
| Max sequence length | 4096 tokens | compose command |
| Health check start period | 600s (10 minutes) | compose healthcheck |

### Start vLLM

All `docker compose` commands in this guide use the `-f <stack>/docker-compose.yaml` form so you can run them from the repo root without `cd`-ing between stacks. This form is shell-agnostic — the exact same line works in PowerShell, cmd, and bash.

```powershell
docker compose -f inference/vllm/docker-compose.yaml up -d
```

**Do not wait for this to become healthy.** The health check has a 600-second (10-minute) start period. Proceed to Section 3 immediately.

You can optionally watch the model loading progress in a separate terminal:
```powershell
docker compose -f inference/vllm/docker-compose.yaml logs -f vllm
# Look for: "Loading model weights..." → "Model loaded successfully"
# Ctrl+C to stop following logs
```

> **Known gotcha — `--async-scheduling`:** The current compose file ships with `--async-scheduling` for throughput. It is **incompatible with structured output (`response_format`)** and must be removed when the RMF structured-output feature (Track B3) lands. If you're deploying for B3 work, strip that flag from the `command:` block in `inference/vllm/docker-compose.yaml` first. See `docs/solutions/vllm-gpt-oss-20b-version-requirements.md` and upstream issue #29379.

- [ ] `docker compose up -d` started without errors
- [ ] Container is running (health: starting)
- [ ] **Proceed to Section 3 — do not wait**

---

## Section 3 — Langfuse (Observability)

Langfuse provides tracing and observability for all LLM calls. It has **no upstream dependencies** and starts quickly (~60 seconds).

### Configuration Review

| Setting | Value | File |
|---------|-------|------|
| Image | `langfuse/langfuse:3.40.0` | `.env` |
| Port | `3001` | `.env` |
| Init user | `basalt@gmail.com` / `password` | `.env` |
| Init project | `basalt` (pk: `pk-examplekey`, sk: `sk-examplekey`) | `.env` |
| Telemetry | **Disabled** (`TELEMETRY_ENABLED=false`) | `.env` |
| Containers | 6: langfuse-web, langfuse-worker, clickhouse, minio, postgres, redis | compose |

### Start Langfuse

```powershell
docker compose -f inference/langfuse/docker-compose.yaml up -d
```

Wait ~60 seconds for all 6 containers to become healthy:
```powershell
docker compose -f inference/langfuse/docker-compose.yaml ps
# All services should show "healthy"
```

> **ClickHouse IPv6 gotcha:** The compose file already uses `127.0.0.1` in the ClickHouse health check instead of `localhost`. On Alpine, `localhost` resolves to `::1` and the health check fails. Don't "fix" it back to `localhost`. See `docs/solutions/clickhouse-alpine-healthcheck-fix.md`.

### Verify Langfuse

1. Browse to **http://localhost:3001**
2. Log in with `basalt@gmail.com` / `password`
3. Confirm the "basalt" project exists in the sidebar
4. Open browser DevTools → Network tab → verify **no outbound requests** to external domains (air-gap compliance)

- [ ] All 6 containers healthy
- [ ] Login successful at `http://localhost:3001`
- [ ] "basalt" project visible
- [ ] No external network requests

---

## Section 4 — LiteLLM (LLM Gateway) + vLLM Readiness Check

LiteLLM is the unified API gateway. It routes requests to vLLM and sends traces to Langfuse.

### Configuration Review

| Setting | Value | File |
|---------|-------|------|
| Image | `ghcr.io/berriai/litellm-database:main-v1.41.14` | `.env` |
| Port | `8000` | `.env` |
| Master key | `sk-120fb1a...` | `.env` |
| Model routing | `gpt-oss-20b` → `host.docker.internal:8001` | `litellm-config.yaml` |
| Model alias | `gpt-4` → `gpt-oss-20b` | `litellm-config.yaml` |
| Langfuse | `host.docker.internal:3001` | `.env` |
| Containers | 3: litellm, redis, postgres | compose |

### Start LiteLLM

```powershell
docker compose -f inference/litellm/docker-compose.yaml up -d
```

Wait ~30 seconds:
```powershell
docker compose -f inference/litellm/docker-compose.yaml ps
# All services should show healthy/running
```

### vLLM Readiness Check

By now (~10 minutes since Section 2), vLLM should be ready. Check:

```powershell
# PowerShell — call curl.exe explicitly to bypass the Invoke-WebRequest alias
curl.exe http://localhost:8001/v1/models
```

**Expected:** JSON response listing `gpt-oss-20b`.

> **Why `curl.exe` and not `curl`?** In PowerShell, `curl` is an alias for `Invoke-WebRequest`, which takes completely different arguments and will silently misinterpret `-X`, `-H`, and `-d`. Windows 10+ ships a real curl binary at `C:\Windows\System32\curl.exe` — always call it explicitly as `curl.exe` in PS, or use `Invoke-RestMethod` natively.

If not ready yet, check logs:
```powershell
docker compose -f inference/vllm/docker-compose.yaml logs --tail 20 vllm
# Look for progress messages or errors
```

Common issues:
- `torch.cuda.OutOfMemoryError` → Reduce `gpu-memory-utilization` in compose command
- Model files not found → Check `MODEL_PATH` in `.env` and verify the mount landed:
  `docker compose -f inference/vllm/docker-compose.yaml exec vllm ls /models/gpt-oss-20b`
- Container exited with `--async-scheduling` error → remove the flag (only a problem on older vLLM builds; v0.10.2 supports it but it conflicts with structured output — see §2 note)

### Verify Full Inference Pipeline

Once vLLM is ready, test the complete path: LiteLLM → vLLM → response → Langfuse trace.

**PowerShell (primary):**
```powershell
# 1. Check LiteLLM sees the model (no auth needed)
curl.exe http://localhost:8000/v1/models

# 2. Load the master key from the .env file. Select-String picks the line,
#    -replace trims the 'LITELLM_MASTER_KEY=' prefix. No bash command-substitution.
$env:LITELLM_MASTER_KEY = (Select-String -Path inference\litellm\.env -Pattern '^LITELLM_MASTER_KEY=').Line -replace '^LITELLM_MASTER_KEY=', ''
"$($env:LITELLM_MASTER_KEY.Substring(0,10))..."   # sanity check — should print 'sk-...' prefix

# 3. Send a test chat completion. Keep the JSON body as a single-quoted one-liner
#    so PowerShell doesn't try to interpolate $ inside it, and so curl.exe receives
#    it as a single argument.
$body = '{"model":"gpt-oss-20b","messages":[{"role":"user","content":"Hello, what model are you?"}],"max_tokens":100}'

curl.exe -X POST http://localhost:8000/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer $env:LITELLM_MASTER_KEY" `
  -d $body
# Should return a chat completion response
```

**WSL2 / Git Bash alternate:**
```bash
curl http://localhost:8000/v1/models

export LITELLM_MASTER_KEY=$(grep -E '^LITELLM_MASTER_KEY=' inference/litellm/.env | cut -d= -f2-)
echo "${LITELLM_MASTER_KEY:0:10}..."

curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [{"role": "user", "content": "Hello, what model are you?"}],
    "max_tokens": 100
  }'
```

**3. Check Langfuse for the trace:**
- Browse to `http://localhost:3001`
- Navigate to the "basalt" project → Traces
- A new trace should appear for the request you just sent

> **Known gotcha — reasoning models via LiteLLM v1.41.14:** `gpt-oss-20b` is a reasoning model and emits a `reasoning_content` field. LiteLLM v1.41.14 has a bug where `choices[0].message.content` comes back as `null` for such responses even though the reasoning_content is present. The direct vLLM endpoint (`http://localhost:8001/v1/...`) returns content correctly. If a downstream client (Open-WebUI, Onyx) shows empty replies, bypass LiteLLM to confirm, then upgrade LiteLLM (≥ v1.50 also unlocks the `hosted_vllm/` model prefix needed for structured output).

**Milestone: The inference pipeline is working.** You have a self-hosted LLM responding to API calls with full observability.

- [ ] vLLM healthy and responding at port 8001
- [ ] LiteLLM healthy and responding at port 8000
- [ ] Test chat completion returns a valid response
- [ ] Trace visible in Langfuse

---

## Section 5 — Authentik (SSO Portal)

Authentik provides centralized authentication, an application launcher, and reverse proxying via subdomain routing.

### 5a — Generate TLS Certificate

Pick one path based on your shell:

**PowerShell (primary):** the script resolves its own paths via `$PSScriptRoot`, so you can invoke it directly from the repo root — no `cd` required, and you stay in the repo root for the rest of the section.
```powershell
.\web\authentik\scripts\gen-cert.ps1
```

**WSL2 / Git Bash alternate:**
```bash
bash web/authentik/scripts/gen-cert.sh
```

> Both scripts produce identical certs. Use the PowerShell version on Windows hosts — `bash scripts/gen-cert.sh` will fail with `invalid option name: pipefail` if your `bash` resolves to a non-GNU shell (BusyBox/dash, common on minimal Windows installs). The PowerShell script has a fallback to `C:\Program Files\Git\usr\bin\openssl.exe` if `openssl` isn't on `PATH`.

This creates a wildcard certificate covering `*.basalt.local` in `./certs/`:
- `basalt.local.pem` (fullchain)
- `basalt.local-key.pem` (private key)
- SANs: `*.basalt.local`, `basalt.local`, `host.docker.internal`, `localhost`, `127.0.0.1`
- RSA 4096, valid 10 years

**Verify the cert SANs (optional but recommended):**
```powershell
# PowerShell (uses Git's openssl if not on PATH)
& 'C:\Program Files\Git\usr\bin\openssl.exe' x509 -in certs\basalt.local.pem -noout -ext subjectAltName
```
```bash
# bash
openssl x509 -in certs/basalt.local.pem -noout -ext subjectAltName
```
You should see all 5 SANs listed.

### 5b — Environment Review

The `.env` file should already have generated secrets (from Phase 1 setup). Verify:

| Setting | Value | Notes |
|---------|-------|-------|
| Image | `ghcr.io/goauthentik/server:2026.2.1` | `.env` |
| Ports | HTTPS `443`, HTTP `80` | `.env` |
| Bootstrap email | `admin@basalt.local` | `.env` |
| Bootstrap password | (generated hex value) | `.env` |
| PostgreSQL | `postgres:16-alpine` | `.env` |
| Redis | `redis:7.4-alpine` (pinned) | `.env` |
| Air-gap flags | All 4 set (update check, error reporting, analytics, avatars) | `.env` + compose |

If `.env` doesn't exist, create it from the example (from the repo root):
```powershell
# PowerShell (primary)
Copy-Item web\authentik\.env.example web\authentik\.env
# Then edit web/authentik/.env and generate one hex value per <generate> placeholder:
# (If openssl isn't on PATH, use Git's: & 'C:\Program Files\Git\usr\bin\openssl.exe' rand -hex 32)
openssl rand -hex 32
```
```bash
# WSL2 / Git Bash alternate
cp web/authentik/.env.example web/authentik/.env
openssl rand -hex 32
```

### 5c — Start Authentik

```powershell
docker compose -f web/authentik/docker-compose.yaml up -d
```

This starts 4 containers: `authentik-server-1`, `authentik-worker-1`, `authentik-postgres-1`, `authentik-redis-1`. The server healthcheck has a 60s `start_period`, so allow ~60–90 seconds before all 4 report healthy:

```powershell
docker compose -f web/authentik/docker-compose.yaml ps
# All 4 services should show "healthy"
```

On first start, the worker also applies the `00-system-settings.yaml` blueprint, which sets the brand title to "Basalt Stack" and marks the default brand. You can verify after login (5d) by checking that the browser tab title reads "Basalt Stack".

> **Port conflict:** If port 443 is in use (e.g., by the archived nginx portal that predated Authentik), stop it first: `docker compose -f web/portal-archived/docker-compose.yaml down`. The portal was archived in Phase 3 of the SSO integration; if you're on a clean checkout post-LACI restructure, this conflict shouldn't occur.

### 5d — Initial Admin Setup

1. Browse to **https://auth.basalt.local/if/flow/initial-setup/**
2. Accept the self-signed certificate warning in your browser
3. Set the admin password (or use the bootstrap password from `.env`)
4. Log in with `admin@basalt.local` and your password

### 5e — Brand & Certificate Configuration (Admin UI)

After logging in to the Authentik admin interface:

**Assign the TLS certificate to the brand:**

1. Navigate to **System > Certificates**. You should see a `basalt.local` entry auto-imported by the worker's cert-discovery sweep (which mounts `./certs:/certs` and scans periodically). If it isn't visible within ~30s, wait a moment and refresh, or restart the worker: `docker compose -f web/authentik/docker-compose.yaml restart worker`.

2. **Attach the private key to the imported cert.** This step is easy to miss: Authentik's auto-discovery imports `basalt.local.pem` as a **cert-only** entry because our gen-cert script emits the key as `basalt.local-key.pem`, a filename Authentik doesn't pair automatically. Without a private key attached, the cert won't appear in the **Web certificate** dropdown in the next step (that dropdown filters to entries that can actually terminate TLS, i.e. ones with a usable private key).

   To fix it:
   - Click the `basalt.local` entry in **System > Certificates** to open it
   - You'll see the certificate body populated but the **Private Key** field empty
   - Open `web/authentik/certs/basalt.local-key.pem` on the host, copy the entire contents (including the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` markers), and paste into the **Private Key** field
   - Save

   After save, the entry should show both cert and key present. If you navigate away and back, the cert's status indicator should now reflect that it has a paired key.

3. Navigate to **System > Brands**.

4. Edit the default brand (`authentik-default`) — **Branding title** is already set to "Basalt Stack" by the `00-system-settings.yaml` blueprint, so you only need to assign the cert here.

5. Set **Web certificate** to `basalt.local`. If it doesn't appear in the dropdown, go back to step 2 — the private key didn't attach successfully.

6. Save.

> **Why the manual key-paste step exists:** Authentik's cert-discovery pairs files by basename convention — it expects either `<name>.pem` + `<name>.key` as a pair, or a single `<name>.pem` containing both cert and key concatenated. Our gen-cert scripts (`gen-cert.ps1` / `gen-cert.sh`) emit the OpenSSL-idiomatic `<name>-key.pem` which discovery leaves unpaired. A cleaner fix at the script level — renaming the key output to `basalt.local.key`, or concatenating — is tracked as a follow-up; for now the manual paste is a one-time step per cert rotation.

**Configure the embedded outpost for self-signed TLS:**
1. Navigate to **Outposts > authentik Embedded Outpost**
2. Edit the outpost
3. In the **Configuration** section (YAML editor), add:
   ```yaml
   authentik_host_insecure: true
   ```
4. Save

### 5f — Enrollment Flow Configuration (Admin UI)

Set up self-registration with admin approval:

1. Navigate to **Flows & Stages > Flows**
2. Create a new flow:
   - Name: `enrollment-approval`
   - Title: "Request Account"
   - Designation: `Enrollment`
3. Add stages to the flow (in order):
   - **Stage 1 — Prompt Stage**: Collect username, email, name
   - **Stage 2 — User Write Stage**: Set `create_users_as_inactive: true` (users are inactive until admin approves)
   - **Stage 3 — Deny Stage**: Message: "Your account request has been submitted. An administrator will review and approve your access."
4. Navigate to **System > Brands > authentik-default**
5. Set **Enrollment flow** to `enrollment-approval`
6. Save

**To approve a user:** Navigate to **Directory > Users** → find the inactive user → toggle **Is active** to true.

### Verify Authentik

- [ ] All 4 containers healthy (`docker compose ps`)
- [ ] Cert SANs verified via `openssl x509 -in certs/basalt.local.pem -noout -ext subjectAltName` (all 5 SANs present)
- [ ] Blueprint applied — browser tab title reads "Basalt Stack" (confirms `00-system-settings.yaml` was loaded by the worker)
- [ ] Browse to `https://auth.basalt.local` → login page loads
- [ ] Admin login works with bootstrap credentials
- [ ] Certificate shows `basalt.local` (not default Authentik cert)
- [ ] Browser DevTools → Network tab → no outbound requests for 60 seconds

---

## Section 6 — Open-WebUI (Chat Interface) + SSO Integration

### Security Model (Phase 2 Summary)

Before configuring the proxy, understand the three-layer defense Phase 2 put in place — getting any of these wrong silently weakens SSO:

| Layer | What it does | Config |
|-------|-------------|--------|
| **S1 — Random passwords for SSO signups** | When Authentik provisions a user via the proxy header flow, Open-WebUI generates a cryptographically random password instead of a blank/known one. Prevents post-SSO password-based hijack. | Hardened in the LACI patch set — no knob to turn |
| **S2 — `WEBUI_SECRET_KEY` fail-fast** | Open-WebUI refuses to start if `WEBUI_SECRET_KEY` is unset or empty. JWTs signed with a blank key would be trivially forgeable. | `web/open-webui/.env` — must contain a 32+ byte hex value |
| **S3 — `AUTHENTIK_SHARED_SECRET` HMAC validation** | Every SSO header request from the Authentik proxy must carry `X-Authentik-Secret`. Without it, the request is rejected 403 even if `X-Authentik-Email` is present. Blocks header spoofing from anywhere on the host network. | `web/open-webui/.env` **and** the matching `basalt-users` group attribute in Authentik (§6d) |
| **JWT expiry** | `WEBUI_JWT_EXPIRES_IN` bounds session lifetime so a stolen JWT isn't forever. | `web/open-webui/.env` — defaults to a short window; raise only with intent |

If Open-WebUI crashes on startup with a secret-key error, that is S2 doing its job — set `WEBUI_SECRET_KEY` and restart.

### 6a — Bootstrap Admin Account (Before SSO)

**Critical:** Create the admin account at Open-WebUI **before** enabling the Authentik proxy. The first account registered gets the `admin` role. If Authentik proxy is active first, a race condition could assign admin to the wrong user.

```powershell
docker compose -f web/open-webui/docker-compose.yaml up -d
```

1. Browse to **http://localhost:3002** (direct access, bypasses Authentik)
2. Click "Sign up" and create the admin account
   - Use the same email as your Authentik admin account (`admin@basalt.local`)
   - Any password (this won't be used after SSO is enabled — the auth code uses random passwords for SSO signups)
3. Confirm you can access the Open-WebUI dashboard

### 6b — Configure LLM Endpoint in Open-WebUI

While you're in Open-WebUI:

1. Go to **Settings > Connections** (or Admin Panel > Settings > Connections)
2. Set OpenAI API endpoint:
   - URL: `http://host.docker.internal:8000/v1`
   - API Key: `sk-120fb1a38a2a6ca5ef2745fe507e50fe479a509e6667e62dd4445d97b3ae8cf0`
3. Save and verify the model list loads (should show `gpt-oss-20b`)

### 6c — Create Authentik Proxy Provider (Admin UI)

Switch back to the Authentik admin UI at `https://auth.basalt.local`:

**Create the proxy provider:**
1. Navigate to **Applications > Providers**
2. Click **Create** → select **Proxy Provider**
3. Configure:
   - Name: `openwebui-proxy`
   - Authorization flow: `default-provider-authorization-implicit-consent`
   - Mode: **Proxy**
   - External host: `https://webui.basalt.local`
   - Internal host: `http://host.docker.internal:3002`
4. Save

**Create the application:**
1. Navigate to **Applications > Applications**
2. Click **Create**:
   - Name: `Open-WebUI`
   - Slug: `openwebui`
   - Group: `AI Services`
   - Provider: select `openwebui-proxy`
   - Launch URL: `https://webui.basalt.local`
3. Save

**Bind to the embedded outpost:**
1. Navigate to **Outposts > authentik Embedded Outpost**
2. Edit the outpost
3. In **Applications**, add `Open-WebUI` to the selected applications
4. Save

### 6d — Configure Shared Secret Group (Admin UI)

This prevents header spoofing — Open-WebUI rejects requests without the correct `X-Authentik-Secret` header.

**Create the basalt-users group:**
1. Navigate to **Directory > Groups**
2. Click **Create**:
   - Name: `basalt-users`
3. After creating, click into the group → **Attributes** tab
4. Add custom attribute (YAML/JSON editor):
   ```yaml
   additionalHeaders:
     X-Authentik-Secret: "c19345ef4c1dc11e574054c33d97865db668907d0a0a461b72df483ba8964a64"
   ```
   > This value must match `AUTHENTIK_SHARED_SECRET` in `web/open-webui/.env`
5. Save

**Add admin to the group:**
1. Navigate to **Directory > Users** → select admin user
2. Go to **Groups** tab → add to `basalt-users`

**Auto-assign on enrollment (optional):**
- Edit the User Write stage in the enrollment flow
- Set **Group** to `basalt-users` so approved users are automatically added

### Verify Open-WebUI SSO

1. **SSO flow:** Browse to `https://webui.basalt.local`
   - Should redirect to Authentik login
   - Log in as admin → auto-authenticated in Open-WebUI
2. **Chat works:** Send a test message → response streams back (WebSocket through proxy)
3. **Spoofing blocked:** Test direct access with a fake header:
   ```powershell
   # PowerShell — curl.exe, not the Invoke-WebRequest alias
   curl.exe -H "X-Authentik-Email: admin@basalt.local" http://localhost:3002/api/v1/auths/signin
   # Should return 403 (missing shared secret)
   ```
   ```bash
   # WSL2 / Git Bash alternate
   curl -H "X-Authentik-Email: admin@basalt.local" http://localhost:3002/api/v1/auths/signin
   ```
4. **Trace in Langfuse:** Check `http://localhost:3001` → new trace from the chat message

- [ ] `https://webui.basalt.local` redirects to Authentik login
- [ ] Admin auto-authenticated after Authentik login
- [ ] Chat streaming works through proxy (WebSocket)
- [ ] Spoofed header without shared secret → 403
- [ ] Trace visible in Langfuse

---

## Section 7 — Onyx (AI Platform) + OIDC Integration

Onyx uses **native OIDC** (not forward-auth headers like Open-WebUI). It redirects to Authentik for login and handles the OAuth2 callback itself. A proxy provider handles subdomain routing.

### 7a — Create Authentik OIDC Provider (Admin UI)

In the Authentik admin UI at `https://auth.basalt.local`:

**Create the OIDC provider:**
1. Navigate to **Applications > Providers**
2. Click **Create** → select **OAuth2/OpenID Provider**
3. Configure:
   - Name: `onyx-oidc`
   - Client type: **Confidential**
   - Redirect URIs: `https://onyx.basalt.local/auth/oidc/callback`
   - Scopes: `openid`, `email`, `profile`
   - Signing key: `authentik Self-signed Certificate` (or your imported cert)
   - Authorization flow: `default-provider-authorization-implicit-consent`
4. Save
5. **Record the Client ID and Client Secret** displayed after saving — you'll need these for the Onyx `.env`

### 7b — Create Authentik Proxy Provider (Admin UI)

The proxy provider handles subdomain routing for `onyx.basalt.local`:

**Create the proxy provider:**
1. Navigate to **Applications > Providers**
2. Click **Create** → select **Proxy Provider**
3. Configure:
   - Name: `onyx-proxy`
   - Authorization flow: `default-provider-authorization-implicit-consent`
   - Mode: **Proxy**
   - External host: `https://onyx.basalt.local`
   - Internal host: `http://host.docker.internal:3000`
4. Save

**Create the application:**
1. Navigate to **Applications > Applications**
2. Click **Create**:
   - Name: `Onyx`
   - Slug: `onyx`
   - Group: `AI Services`
   - Provider: select `onyx-proxy` (primary — handles routing)
   - Launch URL: `https://onyx.basalt.local`
   - Optionally add `onyx-oidc` as a backchannel provider if supported
3. Save

**Bind to the embedded outpost:**
1. Navigate to **Outposts > authentik Embedded Outpost**
2. Edit → add `Onyx` to selected applications
3. Save

### 7c — Update Onyx Environment

Edit `web/onyx/.env` — replace the placeholder values with the actual Client ID and Secret from step 7a:

```env
################################################################################
## Auth — Authentik OIDC SSO
################################################################################
AUTH_TYPE=oidc
OAUTH_CLIENT_ID=<paste-client-id-from-step-7a>
OAUTH_CLIENT_SECRET=<paste-client-secret-from-step-7a>
OPENID_CONFIG_URL=http://host.docker.internal:9000/application/o/onyx/.well-known/openid-configuration
WEB_DOMAIN=https://onyx.basalt.local
```

> **Why HTTP for OIDC discovery?** The `OPENID_CONFIG_URL` uses HTTP (`host.docker.internal:9000`) for the internal server-to-server OIDC call. This avoids SSL verification failures against Authentik's self-signed cert. User-facing traffic still uses HTTPS via port 443. This is documented security debt — Phase 7 will add cert trust.

### 7d — Start Onyx

```powershell
docker compose -f web/onyx/docker-compose.yaml up -d
```

Onyx starts **10 containers**: `nginx`, `api_server`, `background`, `web_server`, `inference_model_server`, `indexing_model_server`, `relational_db`, `index` (Vespa), `cache`, `minio`. This takes 2–3 minutes on a warm cache.

> **First-run model download — read carefully (air-gap implication):** The `inference_model_server` and `indexing_model_server` containers pull HuggingFace embedding and reranking models (all-MiniLM-L6-v2, the BGE reranker, etc.) on first startup and cache them in named volumes (`model_cache_huggingface`, `indexing_huggingface_model_cache`). **This requires internet access on the dev host** and is the single largest air-gap violation in the whole dev workflow.
>
> - On the *connected dev host* (this guide): let it run once, then confirm the cached volumes survive `docker compose down` (they should — they're named volumes, not bind mounts).
> - For the *real air-gapped deployment*: these caches must be pre-populated offline and either baked into a custom image (Phase B of the LACI custom-build track) or shipped as a volume export. Do **not** assume `docker compose up` will work on an isolated network without that prep.

```bash
docker compose -f web/onyx/docker-compose.yaml ps
# Wait for all 10 containers to show healthy/running
```

### 7e — Configure LLM Provider in Onyx (Admin UI)

1. Browse to **https://onyx.basalt.local** (should redirect to Authentik login)
2. Log in with your Authentik admin account
3. After OIDC callback, you should be in the Onyx dashboard
4. Navigate to **Admin > LLM Providers** (or the initial setup wizard)
5. Add an OpenAI-compatible provider:
   - API Base: `http://host.docker.internal:8000/v1`
   - API Key: `sk-120fb1a38a2a6ca5ef2745fe507e50fe479a509e6667e62dd4445d97b3ae8cf0`
   - Model: `gpt-oss-20b`

### Verify Onyx OIDC

1. **OIDC flow:** Browse to `https://onyx.basalt.local`
   - Redirects to Authentik login → OIDC callback → Onyx session created
   - User created in Onyx with correct email from Authentik
2. **Cross-app SSO:** If already logged in via Open-WebUI:
   - Click the Onyx tile in Authentik app launcher (`https://auth.basalt.local`)
   - Should authenticate without re-login
3. **OIDC discovery reachable from inside the Onyx container:** use `docker compose exec` with the service name (`api_server`) so you don't have to guess the full container name — compose resolves it regardless of the project prefix.
   ```powershell
   # PowerShell — backtick for line continuation
   docker compose -f web/onyx/docker-compose.yaml exec api_server `
     curl -s http://host.docker.internal:9000/application/o/onyx/.well-known/openid-configuration
   # Should return JSON with issuer, authorization_endpoint, etc.
   ```
   > The `curl` inside the command runs *inside the Linux container*, not on the Windows host, so it's the real curl regardless of your host shell. If the Onyx api_server image doesn't include curl, substitute `wget -qO- <url>` or `python -c 'import urllib.request; print(urllib.request.urlopen("<url>").read().decode())'`.
4. **Chat works:** Send a test query in Onyx → response from GPT-OSS:20B → trace in Langfuse

- [ ] `https://onyx.basalt.local` redirects to Authentik login
- [ ] OIDC callback completes → Onyx session created
- [ ] Cross-app SSO works (no re-login from Authentik app launcher)
- [ ] OIDC discovery endpoint reachable from Onyx container
- [ ] Chat query returns a response

---

## Section 8 — Final Verification & Smoke Tests

### Service Health Check

Run across all compose directories:

```powershell
# PowerShell (primary) — no subshells, no cd. Works in both PS 5.1 and 7.
Write-Host "=== vLLM ===";       docker compose -f inference/vllm/docker-compose.yaml ps
Write-Host "=== Langfuse ===";   docker compose -f inference/langfuse/docker-compose.yaml ps
Write-Host "=== LiteLLM ===";    docker compose -f inference/litellm/docker-compose.yaml ps
Write-Host "=== Authentik ==="; docker compose -f web/authentik/docker-compose.yaml ps
Write-Host "=== Open-WebUI ==="; docker compose -f web/open-webui/docker-compose.yaml ps
Write-Host "=== Onyx ===";       docker compose -f web/onyx/docker-compose.yaml ps
```

**Expected:** ~25 containers, all showing `healthy` or `Up`.

### Cross-App SSO Flow

1. Open a **fresh incognito/private browser window** (no existing sessions)
2. Browse to `https://auth.basalt.local` → Authentik login page
3. Log in with admin credentials
4. You should see the **Application Launcher** with tiles for Open-WebUI and Onyx
5. Click **Open-WebUI** tile → `https://webui.basalt.local` → authenticated without re-login
6. Click **Onyx** tile → `https://onyx.basalt.local` → authenticated without re-login
7. Send a chat message in Open-WebUI → verify response
8. Send a query in Onyx → verify response

### User Registration Flow

1. Open a **different browser** (or another incognito window)
2. Browse to `https://auth.basalt.local`
3. Click "Request Account" (enrollment flow)
4. Fill in username, email, name → submit
5. See the "pending approval" message
6. Switch to admin browser → **Directory > Users** → find the new user → toggle **Is active** → add to `basalt-users` group
7. Switch back to test user browser → log in → access Open-WebUI and Onyx

### Inference Pipeline Trace

1. Send a chat from Open-WebUI
2. Open Langfuse at `http://localhost:3001`
3. Navigate to basalt project → Traces
4. Verify the trace shows the full path: request → LiteLLM → vLLM → response

### Air-Gap Compliance Check

On each service URL, open browser DevTools → Network tab → monitor for 60 seconds:

| URL | Expected |
|-----|----------|
| `https://auth.basalt.local` | No external requests |
| `https://webui.basalt.local` | No external requests |
| `https://onyx.basalt.local` | No external requests (after initial HF model download) |
| `http://localhost:3001` (Langfuse) | No external requests |

### Final Checklist

- [ ] ~25 containers running and healthy across 6 stacks
- [ ] GPT-OSS:20B responding to chat completions via LiteLLM
- [ ] Langfuse tracing all LLM requests
- [ ] Authentik login page at `https://auth.basalt.local`
- [ ] Cross-app SSO: single login → access Open-WebUI + Onyx
- [ ] User registration with admin approval works
- [ ] Spoofed header without shared secret → rejected
- [ ] No outbound network requests from any service

---

## Appendix A — Troubleshooting

### PowerShell & Windows Host Pitfalls

Basalt dev runs on Windows with PowerShell as the primary shell, driving Docker Desktop directly. These are the bugs you hit when you don't respect that:

| Symptom | Cause | Fix |
|---------|-------|-----|
| `curl` returns HTML or `Invoke-WebRequest` errors instead of calling the REST endpoint | In PowerShell, `curl` is an alias for `Invoke-WebRequest`, which has completely different argument semantics | Call `curl.exe` explicitly (Windows 10+ ships a real curl at `C:\Windows\System32\curl.exe`). Or use `Invoke-RestMethod` natively. |
| `$(command)` doesn't expand; variable ends up literal `$(...)` | Bash-style command substitution doesn't exist in PowerShell | Use `Select-String -Path <file> -Pattern <regex>` + `-replace` to parse `.env`. See §4 LITELLM_MASTER_KEY example. |
| `cmd1 && cmd2` fails with "The token '&&' is not a valid statement separator" | Pipeline chain operators require **PowerShell 7+**. Windows PowerShell 5.1 (the old default) doesn't support them. | Either upgrade to PS 7 (ships with Docker Desktop on Win11) or use `;` to unconditionally sequence, or just use `docker compose -f <path>/docker-compose.yaml ...` which needs no chaining. |
| `pipefail` / `set -e` errors from `.sh` scripts on Windows | `bash` on PATH may resolve to BusyBox/dash (no GNU bash), not the real thing | Use the PowerShell equivalent where one exists (e.g. `.\scripts\gen-cert.ps1` in §5a). Rule of thumb: Windows → PowerShell; stay out of WSL2 for deployment orchestration. |
| Bind mount in `docker-compose.yaml` silently empty inside the container | `MODEL_PATH` set with backslashes (`D:\BASALT\models`) — Compose doesn't interpret backslash escapes cleanly | Use forward slashes in `.env`: `MODEL_PATH=D:/BASALT/models`. Docker Desktop accepts that form on Windows. |
| Docker Desktop restarts and disk image moves back to `C:\` | You relocated it via registry edit, junction, or WSL export/import hack | Use Docker Desktop GUI → Settings → Resources → Advanced → "Disk image location" (3 clicks). Any other method is overwritten on restart. |
| Random bind-mount / signal-forwarding failures when driving `docker compose` from inside WSL2 bash | WSL2-side Docker Desktop CLI has occasional translation edge cases | Run deployment commands from **PowerShell**, not WSL2 bash. Drop into WSL2 only for Linux-native tooling (e.g., `huggingface-cli`) if you prefer it there. |
| `cd basalt-stack/...` → "path not found" | Pre-LACI layout reference (the prefix was removed 2026-03-30) | Drop the `basalt-stack/` prefix. The compose stacks are directly under `inference/` and `web/` at the repo root. |

### vLLM

| Symptom | Cause | Fix |
|---------|-------|-----|
| Container exits immediately with scheduling error | `--async-scheduling` flag issue (only on older vLLM builds; v0.10.2 supports it but conflicts with structured output — see §2) | Remove the flag from the compose `command:` section |
| `torch.cuda.OutOfMemoryError` | Model + KV cache exceed available VRAM (20 GB on A4000 dev box, 48 GB on A6000 prod target) | **A4000 dev**: drop to a 4-bit quant, set `--max-model-len 8192`, `--max-num-seqs 2`, `--gpu-memory-utilization 0.90`. **A6000 prod**: lower `--gpu-memory-utilization` to `0.80` or reduce `max-model-len` to `2048`. |
| Model not found | `MODEL_PATH` points to wrong parent directory, or the bind mount didn't land | `docker compose -f inference/vllm/docker-compose.yaml exec vllm ls /models/gpt-oss-20b` — should list `config.json` and `*.safetensors`. If empty, the host-side path in `.env` is wrong. |
| Health check never passes | Model still loading (normal for first 5-10 min, and an extra 2–5 min on top if using the `D:/BASALT/models` 9p path) | Wait for `start_period` (600s). Check logs: `docker compose -f inference/vllm/docker-compose.yaml logs -f vllm` |
| First-load appears slow (several minutes before "Loading model weights...") | Weights served from Windows NTFS via the WSL2 9p bridge (`D:/BASALT/models`) | Expected and accepted trade-off per §1. Only relevant at cold start — post-load inference is GPU-bound. If it bothers you, move weights to a WSL2 native path (e.g., `/home/$USER/models/gpt-oss-20b`) and update `MODEL_PATH`. |

### Langfuse

| Symptom | Cause | Fix |
|---------|-------|-----|
| ClickHouse health check fails | IPv6 resolution of `localhost` → `::1` | Already fixed in compose (uses `127.0.0.1`). If you modified the compose, verify health check URL. |
| No traces appearing | LiteLLM not configured for Langfuse | Check `LANGFUSE_HOST` in LiteLLM `.env` points to `http://host.docker.internal:3001` |
| Login fails | Wrong init credentials | Default: `basalt@gmail.com` / `password` (from `.env`) |

### LiteLLM

| Symptom | Cause | Fix |
|---------|-------|-----|
| Model not listed in `/v1/models` | vLLM not ready yet | Wait for vLLM health check to pass, then restart LiteLLM: `docker compose restart litellm` |
| Chat returns error | `drop_params: true` stripping params | For structured output, consider changing model prefix to `hosted_vllm/` in `litellm-config.yaml` (requires LiteLLM ≥ v1.50 — current v1.41.14 only supports `openai/`) |
| `content: null` in chat response but `reasoning_content` is populated | LiteLLM v1.41.14 bug for reasoning models | Hit vLLM directly (`http://localhost:8001/v1/...`) to confirm. Upgrade LiteLLM ≥ v1.50 to fix permanently. |
| No Langfuse traces | Auth mismatch | Verify `LANGFUSE_AUTH` in LiteLLM `.env` is base64 of `pk-examplekey:sk-examplekey` |

### Authentik

| Symptom | Cause | Fix |
|---------|-------|-----|
| Login page won't load | Port 443 conflict (old portal?) | `docker ps` to find what's using port 443. Stop the old portal. |
| Login page loads but cert is wrong | Certificate not assigned to brand | Admin UI > System > Brands > set Web certificate to `basalt.local` |
| `basalt.local` visible in System > Certificates but **missing from the Web certificate dropdown** in System > Brands | Cert was auto-discovered standalone because Authentik's discovery doesn't pair `basalt.local.pem` with our `basalt.local-key.pem` filename. Dropdowns for server TLS filter out cert-only entries. | Open the `basalt.local` entry in System > Certificates, paste the contents of `web/authentik/certs/basalt.local-key.pem` into the Private Key field, save. The cert will then appear in the Web certificate dropdown. See §5e. |
| Subdomain doesn't route | Provider not bound to outpost | Outposts > authentik Embedded Outpost > verify application is selected |
| `502 Bad Gateway` on subdomain | Backend service not running | Start the backend service. Verify `host.docker.internal` resolves from Authentik container. |
| Workers unhealthy | Insufficient memory | Check `docker stats`. Worker needs up to 1 GB. |

### Open-WebUI

| Symptom | Cause | Fix |
|---------|-------|-----|
| 403 on proxy access | Shared secret mismatch | Verify `X-Authentik-Secret` in Authentik group attributes matches `AUTHENTIK_SHARED_SECRET` in Open-WebUI `.env` |
| Chat doesn't stream | WebSocket blocked by proxy | Verify embedded outpost handles `Upgrade: websocket`. Check outpost config. |
| JWT expired immediately | `WEBUI_SECRET_KEY` not set | Must be set in `.env` — fails at startup if missing (security blocker S2 fix) |

### Onyx

| Symptom | Cause | Fix |
|---------|-------|-----|
| OIDC callback fails | Client ID/secret mismatch | Verify values in Onyx `.env` match what Authentik generated |
| OIDC callback fails | Redirect URI mismatch | Must be exactly `https://onyx.basalt.local/auth/oidc/callback` in both Authentik provider and Onyx config |
| OIDC discovery unreachable | `host.docker.internal` not resolving from Onyx container | Check `extra_hosts` in Onyx compose (should have `host.docker.internal:host-gateway`) |
| Model servers download on every start | HF cache volume not persisted | Verify `model_cache_huggingface` volumes exist in compose |
| `AUTH_TYPE=oidc` but no login redirect | Onyx not detecting OIDC config | Verify `OPENID_CONFIG_URL` is set and reachable: `curl http://host.docker.internal:9000/application/o/onyx/.well-known/openid-configuration` |

---

## Appendix B — Quick Reference

### Service URLs

| Service | URL | Auth |
|---------|-----|------|
| **Authentik Portal** | `https://auth.basalt.local` | Admin: `admin@basalt.local` |
| **Open-WebUI** | `https://webui.basalt.local` | SSO via Authentik |
| **Onyx** | `https://onyx.basalt.local` | OIDC via Authentik |
| **Langfuse** | `http://localhost:3001` | `basalt@gmail.com` / `password` |
| **LiteLLM API** | `http://localhost:8000` | Key: `sk-120fb1a...` |
| **vLLM API** | `http://localhost:8001` | None (internal) |

### API Quick Test

**PowerShell (primary):**
```powershell
# Chat completion via LiteLLM — loads the master key from .env rather than hardcoding.
$env:LITELLM_MASTER_KEY = (Select-String -Path inference\litellm\.env -Pattern '^LITELLM_MASTER_KEY=').Line -replace '^LITELLM_MASTER_KEY=', ''

$body = '{"model":"gpt-oss-20b","messages":[{"role":"user","content":"Hello"}],"max_tokens":100}'

curl.exe -X POST http://localhost:8000/v1/chat/completions `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer $env:LITELLM_MASTER_KEY" `
  -d $body
```

**WSL2 / Git Bash alternate:**
```bash
export LITELLM_MASTER_KEY=$(grep -E '^LITELLM_MASTER_KEY=' inference/litellm/.env | cut -d= -f2-)

curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'
```

### Startup Order (Quick)

Run from the repo root in PowerShell. These lines are shell-agnostic — the `-f` form avoids `cd`, subshells, and `&&` chaining entirely, so the same sequence works in PowerShell 5.1, PowerShell 7, cmd, and bash.

```powershell
docker compose -f inference/vllm/docker-compose.yaml      up -d
docker compose -f inference/langfuse/docker-compose.yaml  up -d
docker compose -f inference/litellm/docker-compose.yaml   up -d
docker compose -f web/authentik/docker-compose.yaml       up -d
docker compose -f web/open-webui/docker-compose.yaml      up -d
docker compose -f web/onyx/docker-compose.yaml            up -d
```

### Shutdown Order (Reverse)

```powershell
docker compose -f web/onyx/docker-compose.yaml            down
docker compose -f web/open-webui/docker-compose.yaml      down
docker compose -f web/authentik/docker-compose.yaml       down
docker compose -f inference/litellm/docker-compose.yaml   down
docker compose -f inference/langfuse/docker-compose.yaml  down
docker compose -f inference/vllm/docker-compose.yaml      down
```

### Compose Directories

| Stack | Directory | Containers |
|-------|-----------|------------|
| vLLM | `inference/vllm/` | 1 |
| Langfuse | `inference/langfuse/` | 6 |
| LiteLLM | `inference/litellm/` | 3 |
| Authentik | `web/authentik/` | 4 |
| Open-WebUI | `web/open-webui/` | 1 |
| Onyx | `web/onyx/` | 10 |
| **Total** | | **~25** |

### Secret Locations

| Secret | File | Notes |
|--------|------|-------|
| LiteLLM Master Key | `inference/litellm/.env` | `sk-120fb1a...` |
| Langfuse Login | `inference/langfuse/.env` | `basalt@gmail.com` / `password` |
| Langfuse API Keys | `inference/langfuse/.env` | `pk-examplekey` / `sk-examplekey` |
| Authentik Admin | `web/authentik/.env` | `admin@basalt.local` / bootstrap password |
| Authentik Secret Key | `web/authentik/.env` | `0fc014b4...` |
| Open-WebUI JWT Secret | `web/open-webui/.env` | `WEBUI_SECRET_KEY` — fail-fast if unset (S2) |
| Authentik Shared Secret | `web/open-webui/.env` | `AUTHENTIK_SHARED_SECRET=c19345ef...` — must match the `basalt-users` group attribute in Authentik (S3) |
| Onyx OIDC Client Secret | `web/onyx/.env` | `OAUTH_CLIENT_SECRET` (generated by Authentik in §7a) |

> **Warning:** These are dev values. Rotate all secrets before production deployment. Use `openssl rand -hex 32` for each.
