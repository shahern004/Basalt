# Basalt Stack — Developer Deployment Guide

**Version:** 1.0
**Date:** 2026-03-19
**Environment:** Connected dev machine (internet access for image pulls and model download)
**Endstate:** Full stack running with GPT-OSS:20B accessible via Authentik SSO portal

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
| GPU | NVIDIA RTX A6000 (48 GB VRAM) or equivalent |
| RAM | 32 GB minimum (64 GB recommended for ~25 containers) |
| Disk | 100 GB free (model weights ~40 GB + Docker images ~50 GB) |
| OS | Windows 11 Pro with WSL2 |

### Software Requirements

| Software | Version | Check Command |
|----------|---------|---------------|
| Docker Desktop | Latest with WSL2 backend | `docker compose version` |
| NVIDIA Container Toolkit | Latest | `nvidia-smi` (should show A6000) |
| WSL2 | Ubuntu or Debian distro | `wsl --list --verbose` |
| Git | Any | `git --version` |
| OpenSSL | Any (for cert generation) | `openssl version` |

### Pre-Flight Checks

```bash
# 1. Verify Docker is running with GPU support
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi

# 2. Verify Docker Compose v2
docker compose version
# Expected: Docker Compose version v2.x.x

# 3. Check available disk space
df -h /  # WSL2 filesystem
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
```bash
ping -n 1 auth.basalt.local
# Should resolve to 127.0.0.1
```

### Clone/Verify Repository

```bash
cd /path/to/your/workspace
# Repo should already be at:
# D:\BASALT\Basalt-Architecture\basalt-stack-v1.0
ls basalt-stack/inference/vllm/docker-compose.yaml  # Should exist
```

- [ ] Docker running with GPU support
- [ ] `nvidia-smi` shows RTX A6000
- [ ] Hosts file updated with `*.basalt.local` entries
- [ ] Repository present with all compose files

---

## Section 1 — Model Weights Download

Download `openai/gpt-oss-20b` from HuggingFace. This is the largest single download (~40 GB safetensors format).

### Important: Use a Linux Filesystem Path

Docker on WSL2 mounts Windows paths (`/mnt/c/`, `/mnt/d/`) through a 9p filesystem bridge that adds **10-20x I/O overhead** for model loading. Store weights on a native Linux filesystem instead.

**Recommended locations:**
- `/home/<user>/models/gpt-oss-20b/` (WSL2 home directory)
- A dedicated ext4 VHD mounted in WSL2

### Download Steps

```bash
# Option A: Using huggingface-cli (recommended)
pip install huggingface-hub
huggingface-cli download openai/gpt-oss-20b \
  --local-dir /home/$USER/models/gpt-oss-20b \
  --local-dir-use-symlinks False

# Option B: Using git lfs
git lfs install
git clone https://huggingface.co/openai/gpt-oss-20b /home/$USER/models/gpt-oss-20b
```

### Update vLLM Configuration

Edit `basalt-stack/inference/vllm/.env`:

```env
# Change from:
MODEL_PATH=./models

# Change to (your actual Linux path):
MODEL_PATH=/home/<user>/models/gpt-oss-20b
```

> **Note:** The vLLM compose file mounts `MODEL_PATH` to `/models` inside the container. The `--model` flag in the compose command is `openai/gpt-oss-20b` — vLLM resolves this from the mounted volume.

### Verify Download

```bash
ls /home/$USER/models/gpt-oss-20b/
# Expected files: config.json, tokenizer.json, *.safetensors, etc.
```

- [ ] Model weights downloaded to Linux filesystem (not `/mnt/c/` or `/mnt/d/`)
- [ ] `MODEL_PATH` updated in `basalt-stack/inference/vllm/.env`
- [ ] Directory contains `config.json` and `*.safetensors` files

---

## Section 2 — vLLM (Inference Engine)

Start vLLM **first** — model loading takes 5-10 minutes. You'll do other work while it loads.

### Configuration Review

| Setting | Value | File |
|---------|-------|------|
| Image | `vllm/vllm-openai:v0.10.2` | `.env` |
| Port | `8001` (host) → `8000` (container) | `.env` |
| Model | `openai/gpt-oss-20b` | `docker-compose.yaml` command |
| GPU memory | 85% of 48 GB = 40.8 GB | compose command |
| Max sequence length | 4096 tokens | compose command |
| Health check start period | 600s (10 minutes) | compose healthcheck |

### Start vLLM

```bash
cd basalt-stack/inference/vllm
docker compose up -d
```

**Do not wait for this to become healthy.** The health check has a 600-second (10-minute) start period. Proceed to Section 3 immediately.

You can optionally watch the model loading progress in a separate terminal:
```bash
docker compose logs -f vllm
# Look for: "Loading model weights..." → "Model loaded successfully"
# Ctrl+C to stop following logs
```

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

```bash
cd basalt-stack/inference/langfuse
docker compose up -d
```

Wait ~60 seconds for all 6 containers to become healthy:
```bash
docker compose ps
# All services should show "healthy"
```

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

```bash
cd basalt-stack/inference/litellm
docker compose up -d
```

Wait ~30 seconds:
```bash
docker compose ps
# All services should show healthy/running
```

### vLLM Readiness Check

By now (~10 minutes since Section 2), vLLM should be ready. Check:

```bash
curl http://localhost:8001/v1/models
```

**Expected:** JSON response listing `gpt-oss-20b`.

If not ready yet, check logs:
```bash
cd basalt-stack/inference/vllm
docker compose logs --tail 20 vllm
# Look for progress messages or errors
```

Common issues:
- `torch.cuda.OutOfMemoryError` → Reduce `gpu-memory-utilization` in compose command
- Model files not found → Check `MODEL_PATH` in `.env`
- Container exited → Check if `--async-scheduling` flag is supported (remove if not)

### Verify Full Inference Pipeline

Once vLLM is ready, test the complete path: LiteLLM → vLLM → response → Langfuse trace.

```bash
# 1. Check LiteLLM sees the model
curl http://localhost:8000/v1/models
# Should list gpt-oss-20b

# 2. Send a test chat completion
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-120fb1a38a2a6ca5ef2745fe507e50fe479a509e6667e62dd4445d97b3ae8cf0" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [{"role": "user", "content": "Hello, what model are you?"}],
    "max_tokens": 100
  }'
# Should return a chat completion response
```

**3. Check Langfuse for the trace:**
- Browse to `http://localhost:3001`
- Navigate to the "basalt" project → Traces
- A new trace should appear for the request you just sent

**Milestone: The inference pipeline is working.** You have a self-hosted LLM responding to API calls with full observability.

- [ ] vLLM healthy and responding at port 8001
- [ ] LiteLLM healthy and responding at port 8000
- [ ] Test chat completion returns a valid response
- [ ] Trace visible in Langfuse

---

## Section 5 — Authentik (SSO Portal)

Authentik provides centralized authentication, an application launcher, and reverse proxying via subdomain routing.

### 5a — Generate TLS Certificate

```bash
cd basalt-stack/web/authentik
bash scripts/gen-cert.sh
```

This creates a wildcard certificate covering `*.basalt.local` in `./certs/`:
- `basalt.local.pem` (fullchain)
- `basalt.local-key.pem` (private key)
- SANs: `*.basalt.local`, `basalt.local`, `host.docker.internal`, `localhost`, `127.0.0.1`
- RSA 4096, valid 10 years

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

If `.env` doesn't exist, create it from the example:
```bash
cp .env.example .env
# Then generate secrets for each <generate> placeholder:
# openssl rand -hex 32
```

### 5c — Start Authentik

```bash
cd basalt-stack/web/authentik
docker compose up -d
```

This starts 4 containers: server, worker, postgres, redis. Wait ~60-90 seconds:

```bash
docker compose ps
# All 4 services should show "healthy"
```

> **Port conflict:** If port 443 is in use (e.g., by the old nginx portal), stop it first: `cd basalt-stack/web/portal-archived && docker compose down`

### 5d — Initial Admin Setup

1. Browse to **https://auth.basalt.local/if/flow/initial-setup/**
2. Accept the self-signed certificate warning in your browser
3. Set the admin password (or use the bootstrap password from `.env`)
4. Log in with `admin@basalt.local` and your password

### 5e — Brand & Certificate Configuration (Admin UI)

After logging in to the Authentik admin interface:

**Assign the TLS certificate to the brand:**
1. Navigate to **System > Certificates**
2. Verify the `basalt.local` certificate was auto-imported (Authentik worker discovers PEM files in `/certs`)
3. Navigate to **System > Brands**
4. Edit the default brand (`authentik-default`)
5. Set **Web certificate** to `basalt.local`
6. Set **Branding title** to "Basalt Stack" (optional — the blueprint may have done this)
7. Save

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
- [ ] Browse to `https://auth.basalt.local` → login page loads
- [ ] Admin login works with bootstrap credentials
- [ ] Certificate shows `basalt.local` (not default Authentik cert)
- [ ] Browser DevTools → Network tab → no outbound requests for 60 seconds

---

## Section 6 — Open-WebUI (Chat Interface) + SSO Integration

### 6a — Bootstrap Admin Account (Before SSO)

**Critical:** Create the admin account at Open-WebUI **before** enabling the Authentik proxy. The first account registered gets the `admin` role. If Authentik proxy is active first, a race condition could assign admin to the wrong user.

```bash
cd basalt-stack/web/open-webui
docker compose up -d
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
   > This value must match `AUTHENTIK_SHARED_SECRET` in `basalt-stack/web/open-webui/.env`
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
   ```bash
   curl -H "X-Authentik-Email: admin@basalt.local" http://localhost:3002/api/v1/auths/signin
   # Should return 403 (missing shared secret)
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

Edit `onyx/deployment/docker_compose/.env` — replace the placeholder values with the actual Client ID and Secret from step 7a:

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

```bash
cd onyx/deployment/docker_compose
docker compose up -d
```

Onyx starts **10 containers** (nginx, api_server, background, web_server, inference_model_server, indexing_model_server, relational_db, index/Vespa, cache, minio). This takes 2-3 minutes.

> **First run note:** The model servers (`inference_model_server`, `indexing_model_server`) will download HuggingFace embedding and reranking models on first startup. This requires internet access and may take several minutes. On subsequent starts, these models are cached in Docker volumes.

```bash
docker compose ps
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
3. **OIDC discovery reachable:**
   ```bash
   docker exec onyx-stack-api_server-1 curl -s http://host.docker.internal:9000/application/o/onyx/.well-known/openid-configuration | head -5
   # Should return JSON with issuer, authorization_endpoint, etc.
   ```
   > Note: The container name may vary. Use `docker ps --filter name=api_server` to find it.
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

```bash
# Check all containers
echo "=== vLLM ===" && cd basalt-stack/inference/vllm && docker compose ps
echo "=== Langfuse ===" && cd basalt-stack/inference/langfuse && docker compose ps
echo "=== LiteLLM ===" && cd basalt-stack/inference/litellm && docker compose ps
echo "=== Authentik ===" && cd basalt-stack/web/authentik && docker compose ps
echo "=== Open-WebUI ===" && cd basalt-stack/web/open-webui && docker compose ps
echo "=== Onyx ===" && cd onyx/deployment/docker_compose && docker compose ps
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

### vLLM

| Symptom | Cause | Fix |
|---------|-------|-----|
| Container exits immediately | `--async-scheduling` not supported in v0.10.2 | Remove flag from compose `command:` section |
| `torch.cuda.OutOfMemoryError` | Model + KV cache exceed 48 GB | Lower `gpu-memory-utilization` to `0.80` or reduce `max-model-len` to `2048` |
| Model not found | `MODEL_PATH` points to wrong location or Windows filesystem | Verify path is on Linux FS, contains `config.json` |
| Health check never passes | Model still loading (normal for first 5-10 min) | Wait for `start_period` (600s). Check logs: `docker compose logs -f vllm` |
| 10-20x slow model loading | Model weights on `/mnt/c/` or `/mnt/d/` (9p bridge) | Move to Linux filesystem path |

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
| Chat returns error | `drop_params: true` stripping params | For structured output, consider changing model prefix to `hosted_vllm/` in `litellm-config.yaml` |
| No Langfuse traces | Auth mismatch | Verify `LANGFUSE_AUTH` in LiteLLM `.env` is base64 of `pk-examplekey:sk-examplekey` |

### Authentik

| Symptom | Cause | Fix |
|---------|-------|-----|
| Login page won't load | Port 443 conflict (old portal?) | `docker ps` to find what's using port 443. Stop the old portal. |
| Login page loads but cert is wrong | Certificate not assigned to brand | Admin UI > System > Brands > set Web certificate to `basalt.local` |
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

```bash
# Chat completion via LiteLLM
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-120fb1a38a2a6ca5ef2745fe507e50fe479a509e6667e62dd4445d97b3ae8cf0" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'
```

### Startup Order (Quick)

```bash
cd basalt-stack/inference/vllm && docker compose up -d
cd basalt-stack/inference/langfuse && docker compose up -d
cd basalt-stack/inference/litellm && docker compose up -d
cd basalt-stack/web/authentik && docker compose up -d
cd basalt-stack/web/open-webui && docker compose up -d
cd onyx/deployment/docker_compose && docker compose up -d
```

### Shutdown Order (Reverse)

```bash
cd onyx/deployment/docker_compose && docker compose down
cd basalt-stack/web/open-webui && docker compose down
cd basalt-stack/web/authentik && docker compose down
cd basalt-stack/inference/litellm && docker compose down
cd basalt-stack/inference/langfuse && docker compose down
cd basalt-stack/inference/vllm && docker compose down
```

### Compose Directories

| Stack | Directory | Containers |
|-------|-----------|------------|
| vLLM | `basalt-stack/inference/vllm/` | 1 |
| Langfuse | `basalt-stack/inference/langfuse/` | 6 |
| LiteLLM | `basalt-stack/inference/litellm/` | 3 |
| Authentik | `basalt-stack/web/authentik/` | 4 |
| Open-WebUI | `basalt-stack/web/open-webui/` | 1 |
| Onyx | `onyx/deployment/docker_compose/` | 10 |
| **Total** | | **~25** |

### Secret Locations

| Secret | File | Notes |
|--------|------|-------|
| LiteLLM Master Key | `basalt-stack/inference/litellm/.env` | `sk-120fb1a...` |
| Langfuse Login | `basalt-stack/inference/langfuse/.env` | `basalt@gmail.com` / `password` |
| Langfuse API Keys | `basalt-stack/inference/langfuse/.env` | `pk-examplekey` / `sk-examplekey` |
| Authentik Admin | `basalt-stack/web/authentik/.env` | `admin@basalt.local` / bootstrap password |
| Authentik Secret Key | `basalt-stack/web/authentik/.env` | `0fc014b4...` |
| Open-WebUI JWT Secret | `basalt-stack/web/open-webui/.env` | `a7c9e3f1...` |
| Authentik Shared Secret | `basalt-stack/web/open-webui/.env` | `c19345ef...` |

> **Warning:** These are dev values. Rotate all secrets before production deployment. Use `openssl rand -hex 32` for each.
