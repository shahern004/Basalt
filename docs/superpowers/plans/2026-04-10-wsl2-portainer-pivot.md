# WSL2 + Portainer Pivot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Docker Desktop from Basalt's runtime story, migrate to a dedicated WSL2 distro (`basalt-host`) running Docker Engine natively, adopt LACI-aligned `proxy` network topology, add Portainer CE for Day-2 ops, and swap model weights to Gemma 4 26B-A4B (AWQ 4-bit).

**Architecture:** All six service stacks attach to a shared external Docker network named `proxy`. Cross-stack traffic uses Docker DNS service names instead of `host.docker.internal`. Model weights live on ext4 inside the `basalt-host` WSL2 distro, eliminating the 9p bridge mount penalty. Portainer CE adopts existing stacks as a Day-2 GUI; compose files remain the deployment source of truth.

**Tech Stack:** Docker Compose, WSL2, Docker Engine (native), nvidia-container-toolkit, Portainer CE, Authentik, vLLM (Gemma 4 AWQ 4-bit), LiteLLM, Langfuse, Onyx, Open-WebUI

**Spec:** `docs/superpowers/specs/2026-04-09-wsl2-portainer-pivot-design.md`
**Branch:** `feat/wsl2-portainer-pivot`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `scripts/check-host-prereqs.ps1` | Windows-side prereq validator (WSL version, GPU driver, .wslconfig, distro name) |
| `scripts/bootstrap-basalt-host.sh` | Idempotent basalt-host distro setup (Docker Engine, nvidia-ctk, dirs, proxy network) |
| `scripts/lint-compose-networks.sh` | Pre-deploy lint: greps all compose files for `external: true` on proxy network (R3) |
| `docs/guides/compose-networking.md` | 100-word gotcha explainer for R3 (`proxy: external: true` silent failure) |
| `ops/portainer/docker-compose.yaml` | Portainer CE stack (single container, socket mount, proxy network) |
| `ops/portainer/docker-compose.dev.yaml` | Dev override: publishes port 9443 for first-run setup |
| `inference/vllm/docker-compose.dev.yaml` | Dev override: publishes port 8001 |
| `inference/litellm/docker-compose.dev.yaml` | Dev override: publishes port 8000 |
| `inference/langfuse/docker-compose.dev.yaml` | Dev override: publishes port 3001 |
| `web/authentik/docker-compose.dev.yaml` | Dev override: publishes port 80 (HTTP redirect) |
| `web/onyx/docker-compose.dev.yaml` | Dev override: publishes ports 3000, 8080, 5432, etc. |
| `web/open-webui/docker-compose.dev.yaml` | Dev override: publishes port 3002 |
| `docs/guides/deployment-guide-wsl2.md` | WSL2 deployment guide (sibling of deployment-guide-dev.md) |
| `docs/guides/database-operations-runbook.md` | Day-2 DB access: Portainer Console + raw docker exec |

### Modified Files

| File | What Changes |
|------|-------------|
| `inference/vllm/docker-compose.yaml` | Model swap (Gemma 4 AWQ), remove ports, add proxy network, update healthcheck |
| `inference/vllm/.env` | Model path → ext4, remove 9p comment |
| `inference/litellm/docker-compose.yaml` | Remove extra_hosts + ports, add proxy network |
| `inference/litellm/.env` | `LANGFUSE_HOST` → Docker DNS (`langfuse-web:3000`) |
| `inference/litellm/litellm-config.yaml` | Model swap (Gemma 4), `api_base` → Docker DNS (`vllm:8000`) |
| `inference/langfuse/docker-compose.yaml` | Remove ports from langfuse-web, add proxy network |
| `web/authentik/docker-compose.yaml` | Rename `server` → `authentik-server`, remove extra_hosts, add proxy network, update ports |
| `web/authentik/.env` | `AUTHENTIK_PORT_HTTP` → 9000 |
| `web/onyx/docker-compose.yaml` | Remove extra_hosts, remove ports from nginx, add proxy network to nginx/api_server/background |
| `web/onyx/.env` | `OPENID_CONFIG_URL` → Docker DNS (`authentik-server:9000`) |
| `web/open-webui/docker-compose.yaml` | Remove extra_hosts + ports, add proxy network |
| `web/authentik/hosts-template.txt` | Add `portainer.basalt.local`, `langfuse.basalt.local` |
| `CLAUDE.md` | New architecture diagram, Gemma 4 swap, proxy network, updated gotchas |

### Intentionally NOT Modified

| File | Why |
|------|-----|
| `web/authentik/db/include.yaml` | Defines postgres + redis; stays on default network only |
| `inference/langfuse/.env` | No `host.docker.internal` references; no model swap impact |
| `web/open-webui/.env` | No `host.docker.internal` references; LiteLLM URL set in admin UI at runtime |

---

## Phase 0: Host Prerequisites & Bootstrap Scripts

### Task 1: Create branch and compose networking gotcha doc

**Files:**
- Create: `docs/guides/compose-networking.md`
- Create: `scripts/lint-compose-networks.sh`

- [ ] **Step 1: Create the feature branch**

```bash
git checkout -b feat/wsl2-portainer-pivot
```

- [ ] **Step 2: Create the `docs/guides/compose-networking.md` gotcha doc**

```markdown
# Compose Networking: `proxy` External Network

All Basalt stacks attach to a shared Docker network named `proxy`.
Cross-stack traffic uses Docker DNS service names (e.g., `vllm`, `litellm`, `langfuse-web`).

## The Rule

Every compose file MUST declare `proxy` as `external: true`:

```yaml
networks:
  proxy:
    external: true
```

## The Bug

If `external: true` is missing, Docker Compose creates a project-scoped network
named `<project>_proxy` instead of using the shared `proxy` network. Cross-stack
DNS lookups return NXDOMAIN with **no error in logs**. Services appear healthy
but cannot reach each other.

## How to Verify

```bash
docker network inspect proxy --format '{{range .Containers}}{{.Name}} {{end}}'
```

All cross-stack services should appear in one network. If any are missing,
check that stack's compose file for the `external: true` declaration.

## Bootstrap

The `proxy` network must exist before any stack starts:

```bash
docker network create proxy
```
```

- [ ] **Step 3: Create `scripts/lint-compose-networks.sh` (R3 pre-deploy lint check)**

```bash
#!/usr/bin/env bash
set -euo pipefail

# lint-compose-networks.sh — Verify all compose files declare proxy as external.
# Run before deploying to catch the R3 silent-failure bug.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

echo "=== Compose Network Lint ==="

for compose_file in \
    "$REPO_ROOT/inference/vllm/docker-compose.yaml" \
    "$REPO_ROOT/inference/litellm/docker-compose.yaml" \
    "$REPO_ROOT/inference/langfuse/docker-compose.yaml" \
    "$REPO_ROOT/web/authentik/docker-compose.yaml" \
    "$REPO_ROOT/web/onyx/docker-compose.yaml" \
    "$REPO_ROOT/web/open-webui/docker-compose.yaml" \
    "$REPO_ROOT/ops/portainer/docker-compose.yaml"; do

    if [ ! -f "$compose_file" ]; then
        echo "  [SKIP] $compose_file (not found)"
        continue
    fi

    # Check for 'external: true' within a proxy network block
    if grep -A1 'proxy:' "$compose_file" | grep -q 'external: true'; then
        echo "  [PASS] $compose_file"
    else
        echo "  [FAIL] $compose_file — missing 'proxy: external: true'"
        FAIL=1
    fi
done

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "All compose files declare proxy as external."
else
    echo "!!! Fix the failing files above. See docs/guides/compose-networking.md"
    exit 1
fi
```

- [ ] **Step 4: Commit**

```bash
chmod +x scripts/lint-compose-networks.sh
git add docs/guides/compose-networking.md scripts/lint-compose-networks.sh
git commit -m "docs: add compose networking gotcha guide + lint script (R3 mitigation)"
```

---

### Task 2: Create Windows host prereq checker

**Files:**
- Create: `scripts/check-host-prereqs.ps1`

- [ ] **Step 1: Create the `scripts/` directory and write the script**

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Validates Windows host prerequisites for the basalt-host WSL2 distro.
.DESCRIPTION
    Checks: WSL2 version, NVIDIA driver, .wslconfig mirrored networking,
    distro name availability, D:\WSL\ path.
    Run from the Windows host before creating the basalt-host distro.
#>

$ErrorActionPreference = 'Continue'
$allPassed = $true

function Write-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    if ($Passed) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Name - $Detail" -ForegroundColor Red
        $script:allPassed = $false
    }
}

Write-Host "`n=== Basalt Host Prerequisites ===" -ForegroundColor Cyan
Write-Host ""

# 1. WSL2 installed and version 2.0+
try {
    $wslOutput = wsl --version 2>&1
    $versionLine = ($wslOutput | Select-String 'WSL version').ToString()
    $verString = ($versionLine -replace '.*:\s*', '').Trim()
    $ver = [version]$verString
    Write-Check "WSL2 version ($ver)" ($ver -ge [version]'2.0.0') "Requires 2.0+. Run: wsl --update"
} catch {
    Write-Check "WSL2 installed" $false "WSL2 not found. Enable via: wsl --install"
}

# 2. NVIDIA driver visible from host
try {
    $driverVersion = (& nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>&1).Trim()
    Write-Check "NVIDIA driver ($driverVersion)" $true ""
} catch {
    Write-Check "NVIDIA driver" $false "nvidia-smi not found. Install NVIDIA Game Ready or Studio driver."
}

# 3. .wslconfig exists with mirrored networking
$wslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path $wslConfigPath) {
    $content = Get-Content $wslConfigPath -Raw
    $hasMirrored = $content -match 'networkingMode\s*=\s*mirrored'
    Write-Check ".wslconfig exists" $true ""
    Write-Check ".wslconfig has networkingMode=mirrored" $hasMirrored `
        "Add under [wsl2]: networkingMode=mirrored  (see U4 in spec)"
} else {
    Write-Check ".wslconfig exists" $false "Create $wslConfigPath with [wsl2] section. See U4/U5 in spec."
}

# 4. Distro name 'basalt-host' not already taken
$distros = (wsl --list --quiet 2>&1) | ForEach-Object { $_.Trim() }
$taken = $distros -contains 'basalt-host'
Write-Check "Distro name 'basalt-host' available" (-not $taken) `
    "Already exists. Unregister first: wsl --unregister basalt-host"

# 5. D:\WSL\ parent directory exists
$parentExists = Test-Path 'D:\WSL'
Write-Check "D:\WSL\ directory exists" $parentExists "Create D:\WSL\ for WSL2 distro storage"

# Summary
Write-Host ""
if ($allPassed) {
    Write-Host "All checks passed. Ready to create basalt-host distro." -ForegroundColor Green
} else {
    Write-Host "Some checks failed. Fix the issues above before proceeding." -ForegroundColor Yellow
}
Write-Host ""
```

- [ ] **Step 2: Commit**

```bash
git add scripts/check-host-prereqs.ps1
git commit -m "feat: add Windows host prereq checker for basalt-host distro"
```

---

### Task 3: Create basalt-host bootstrap script

**Files:**
- Create: `scripts/bootstrap-basalt-host.sh`

- [ ] **Step 1: Write the bootstrap script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# bootstrap-basalt-host.sh — Idempotent setup for the basalt-host WSL2 distro.
#
# Run once after: wsl --import basalt-host D:\WSL\basalt-host\ <rootfs.tar> --version 2
#
# This script uses apt repos (internet required on the dev box).
# Air-gap targets receive this pre-baked via: wsl --export basalt-host <tarball>

BASALT_ROOT=/opt/basalt
MODELS_DIR=$BASALT_ROOT/models
FORGEJO_DIR=/opt/dev/forgejo

echo ""
echo "=== Basalt Host Bootstrap ==="
echo ""

# -------------------------------------------------------------------
# 1. Enable systemd (required for Docker Engine service management)
# -------------------------------------------------------------------
if ! grep -q 'systemd=true' /etc/wsl.conf 2>/dev/null; then
    echo ">>> Enabling systemd in /etc/wsl.conf..."
    sudo tee -a /etc/wsl.conf > /dev/null <<'WSLCONF'

[boot]
systemd=true
WSLCONF
    echo ""
    echo "!!! systemd enabled. You MUST restart the distro before continuing:"
    echo "    From PowerShell: wsl --terminate basalt-host"
    echo "    Then:            wsl -d basalt-host"
    echo "    Then re-run:     ./scripts/bootstrap-basalt-host.sh"
    echo ""
    exit 0
fi

# Verify systemd is actually running
if [ "$(ps -p 1 -o comm=)" != "systemd" ]; then
    echo "!!! systemd is configured but not running as PID 1."
    echo "    Restart the distro: wsl --terminate basalt-host && wsl -d basalt-host"
    exit 1
fi

echo ">>> systemd: running"

# -------------------------------------------------------------------
# 2. Install Docker Engine
# -------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
    echo ">>> Installing Docker Engine..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl gnupg

    # Add Docker GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repo
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    # Add current user to docker group
    sudo usermod -aG docker "$USER"
    echo ">>> Docker installed. Group membership takes effect on next login."
else
    echo ">>> Docker: already installed ($(docker --version))"
fi

# Ensure Docker service is running
if ! systemctl is-active --quiet docker; then
    sudo systemctl enable --now docker
    echo ">>> Docker service started."
else
    echo ">>> Docker service: running"
fi

# -------------------------------------------------------------------
# 3. Install NVIDIA Container Toolkit
# -------------------------------------------------------------------
if ! dpkg -l nvidia-container-toolkit &>/dev/null 2>&1; then
    echo ">>> Installing NVIDIA Container Toolkit..."
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
    echo ">>> NVIDIA Container Toolkit installed and Docker runtime configured."
else
    echo ">>> NVIDIA Container Toolkit: already installed"
fi

# -------------------------------------------------------------------
# 4. Create directory structure
# -------------------------------------------------------------------
echo ">>> Creating directory structure..."
sudo mkdir -p "$BASALT_ROOT" "$MODELS_DIR" "$FORGEJO_DIR"
sudo chown -R "$USER:$USER" "$BASALT_ROOT"
sudo chown -R "$USER:$USER" /opt/dev

echo "    $BASALT_ROOT/"
echo "    $MODELS_DIR/"
echo "    $FORGEJO_DIR/"

# -------------------------------------------------------------------
# 5. Create proxy network (idempotent)
# -------------------------------------------------------------------
if docker network ls --format '{{.Name}}' | grep -qx 'proxy'; then
    echo ">>> Docker network 'proxy': already exists"
else
    docker network create proxy
    echo ">>> Docker network 'proxy': created"
fi

# -------------------------------------------------------------------
# 6. Verify GPU passthrough
# -------------------------------------------------------------------
echo ">>> Verifying GPU passthrough..."
if docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu24.04 nvidia-smi > /dev/null 2>&1; then
    echo ">>> GPU passthrough: verified"
else
    echo "!!! GPU passthrough failed. Check:"
    echo "    - NVIDIA driver is installed on the Windows host"
    echo "    - WSL2 kernel supports GPU passthrough (wsl --update)"
    echo "    (Continuing — vLLM will fail at startup if GPU is unavailable)"
fi

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------
echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Next steps:"
echo "  1. Copy/clone the Basalt repo:"
echo "     cp -r /mnt/d/BASALT/Basalt-Architecture/basalt-stack-v1.0 $BASALT_ROOT/basalt-stack-v1.0"
echo ""
echo "  2. Copy model weights:"
echo "     cp -r /mnt/d/BASALT/models/gemma-4-26B-A4B-it-AWQ-4bit $MODELS_DIR/"
echo ""
echo "  3. Follow the deployment guide:"
echo "     $BASALT_ROOT/basalt-stack-v1.0/docs/guides/deployment-guide-wsl2.md"
echo ""
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x scripts/bootstrap-basalt-host.sh
git add scripts/bootstrap-basalt-host.sh
git commit -m "feat: add basalt-host bootstrap script (Docker Engine + nvidia-ctk)"
```

---

## Phase 1: basalt-host Distro Creation

### Task 4: [HUMAN GATE] Create WSL2 distro and run bootstrap

This task is performed manually by the operator on the Windows host. It cannot be automated by an agentic worker.

**Prerequisites:** Task 2 (check-host-prereqs.ps1) passes green.

- [ ] **Step 1: Run prereq checker from PowerShell**

```powershell
cd D:\BASALT\Basalt-Architecture\basalt-stack-v1.0
.\scripts\check-host-prereqs.ps1
```

Expected: all checks PASS. Fix any failures before continuing.

- [ ] **Step 2: Obtain Ubuntu 24.04 rootfs tarball**

Download from https://cloud-images.ubuntu.com/wsl/ (on a machine with internet) or use an existing Ubuntu WSL2 export. Pre-stage the tarball at `D:\BASALT\staging\ubuntu-24.04-rootfs.tar`.

- [ ] **Step 3: Import the distro**

```powershell
wsl --import basalt-host D:\WSL\basalt-host\ D:\BASALT\staging\ubuntu-24.04-rootfs.tar --version 2
```

- [ ] **Step 4: Enter distro and run bootstrap**

```powershell
wsl -d basalt-host
```

Inside basalt-host:
```bash
cd /mnt/d/BASALT/Basalt-Architecture/basalt-stack-v1.0
./scripts/bootstrap-basalt-host.sh
```

If the script exits requesting a restart (systemd enable), follow its instructions and re-run.

- [ ] **Step 5: Copy repo and model weights**

```bash
cp -r /mnt/d/BASALT/Basalt-Architecture/basalt-stack-v1.0 /opt/basalt/basalt-stack-v1.0
# Model weights — download separately (user's responsibility, see spec U2)
# cp -r /mnt/d/BASALT/models/gemma-4-26B-A4B-it-AWQ-4bit /opt/basalt/models/
```

- [ ] **Step 6: Verify Docker works**

```bash
docker ps
docker network ls | grep proxy
nvidia-smi
```

Expected: Docker running, `proxy` network exists, GPU visible.

**Gate:** `docker ps` works inside basalt-host and `proxy` network exists. Proceed to Phase 2.

---

## Phase 2: Compose Networking Refactor + Model Swap

### Task 5: Refactor vLLM stack — compose + .env + model swap

**Files:**
- Modify: `inference/vllm/docker-compose.yaml` (full rewrite — model swap + networking)
- Modify: `inference/vllm/.env`
- Create: `inference/vllm/docker-compose.dev.yaml`

- [ ] **Step 1: Replace `inference/vllm/docker-compose.yaml` with target state**

```yaml
services:
  vllm:
    image: ${VLLM_IMAGE:-vllm/vllm-openai}:${VLLM_TAG:-v0.10.2}
    restart: unless-stopped
    # ipc: host required for NVIDIA GPU shared memory (NCCL)
    ipc: host
    volumes:
      - ${MODEL_PATH:-/opt/basalt/models}:/models
      - vllm-hf-cache:/root/.cache/huggingface
    environment:
      - VLLM_NO_USAGE_STATS=1
      - NVIDIA_VISIBLE_DEVICES=all
      # Prevent HuggingFace Hub from attempting downloads (air-gap safe)
      - HF_HUB_OFFLINE=1
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    command: >
      --model /models/gemma-4-26B-A4B-it-AWQ-4bit
      --served-model-name gemma-4-26B-A4B-it
      --host 0.0.0.0
      --port 8000
      --quantization awq
      --gpu-memory-utilization 0.90
      --max-model-len 8192
      --max-num-seqs 2
      --tensor-parallel-size 1
      --limit-mm-per-prompt image=0,audio=0
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8000/v1/models | grep -q gemma-4-26B-A4B-it || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 600s
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "6"
    networks:
      - proxy

volumes:
  vllm-hf-cache:

networks:
  proxy:
    external: true
```

Key changes from the original:
- **Model swap**: `gpt-oss-20b` → `gemma-4-26B-A4B-it-AWQ-4bit` (command, healthcheck)
- **AWQ quantization**: `--quantization awq` added
- **VRAM tuning**: `--gpu-memory-utilization 0.90` (was 0.85), `--max-num-seqs 2` (was 64)
- **Vision disabled**: `--limit-mm-per-prompt image=0,audio=0` (R1 workaround)
- **`--async-scheduling` removed**: incompatible with structured output
- **Ports removed**: moved to dev override
- **Proxy network added**: single-service stack, proxy only (LACI pattern)
- **Default `MODEL_PATH`**: `/opt/basalt/models` (ext4, was `./models`)

- [ ] **Step 2: Replace `inference/vllm/.env`**

```
#####################################################################
## vLLM Image Settings
#####################################################################
VLLM_IMAGE=vllm/vllm-openai
VLLM_TAG=v0.10.2

#####################################################################
## Model Configuration
#####################################################################
# Model weights live on ext4 inside basalt-host WSL2 distro.
# No more 9p bridge mount from Windows — vLLM cold start < 60s.
MODEL_PATH=/opt/basalt/models
```

- [ ] **Step 3: Create `inference/vllm/docker-compose.dev.yaml`**

```yaml
# Dev override: publishes vLLM port for direct smoke tests.
# Usage: docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d
services:
  vllm:
    ports:
      - "8001:8000"
```

- [ ] **Step 4: Verify compose config parses**

```bash
cd inference/vllm && docker compose config --quiet && echo "OK" && cd -
cd inference/vllm && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml config --quiet && echo "OK (dev)" && cd -
```

Expected: both print `OK` with no errors.

- [ ] **Step 5: Commit**

```bash
git add inference/vllm/docker-compose.yaml inference/vllm/.env inference/vllm/docker-compose.dev.yaml
git commit -m "refactor(vllm): proxy network + Gemma 4 AWQ model swap

- Remove ports from base compose (dev override publishes 8001)
- Add proxy network (LACI-aligned shared external network)
- Swap gpt-oss-20b for gemma-4-26B-A4B-it-AWQ-4bit
- Add --quantization awq, --limit-mm-per-prompt, tune VRAM params
- Remove --async-scheduling (incompatible with structured output)
- MODEL_PATH default to /opt/basalt/models (ext4, no 9p bridge)"
```

> **Gemma 4 rollback procedure (R1):** If Gemma 4 has intractable vLLM issues during Task 11 smoke test, revert this task's compose changes to gpt-oss-20b:
> 1. Restore the `command:` block to `--model /models/gpt-oss-20b --served-model-name gpt-oss-20b ... --max-num-seqs 64 --gpu-memory-utilization 0.85` (remove `--quantization awq` and `--limit-mm-per-prompt`)
> 2. Restore healthcheck grep to `gpt-oss-20b`
> 3. Revert `.env` MODEL_PATH if needed (still `/opt/basalt/models` — just point to gpt-oss-20b subdir)
> 4. Revert litellm-config.yaml model name and `gpt-4` alias target (Task 7)
> 5. Commit as `revert(vllm): roll back Gemma 4 to gpt-oss-20b per R1 fallback`
> The networking refactor (proxy network, dev override) is independent of the model and stays.

---

### Task 6: Refactor Langfuse stack — compose + dev override

**Files:**
- Modify: `inference/langfuse/docker-compose.yaml` (surgical edits)
- Create: `inference/langfuse/docker-compose.dev.yaml`

- [ ] **Step 1: Remove published port from `langfuse-web` service**

In `inference/langfuse/docker-compose.yaml`, find the `langfuse-web` service and remove its `ports:` section:

Find:
```yaml
    ports:
      - ${LANGFUSE_WEB_PORT}:3000
```

Replace with nothing (delete these two lines).

- [ ] **Step 2: Add proxy network to `langfuse-web` service**

After the `healthcheck:` block of `langfuse-web`, add:

Find:
```yaml
    healthcheck:
      test: wget --no-verbose --tries=1 --spider http://langfuse-web:3000/api/public/health || exit 1
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 1s
```

Replace with:
```yaml
    healthcheck:
      test: wget --no-verbose --tries=1 --spider http://langfuse-web:3000/api/public/health || exit 1
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 1s
    networks:
      - default
      - proxy
```

- [ ] **Step 3: Add network declarations at the bottom of the file**

After the `volumes:` section at the bottom, add:

Find:
```yaml
volumes:
  langfuse_postgres_data:
    driver: local
  langfuse_clickhouse_data:
    driver: local
  langfuse_clickhouse_logs:
    driver: local
  langfuse_minio_data:
    driver: local
  redis_data:
    driver: local
```

Replace with:
```yaml
volumes:
  langfuse_postgres_data:
    driver: local
  langfuse_clickhouse_data:
    driver: local
  langfuse_clickhouse_logs:
    driver: local
  langfuse_minio_data:
    driver: local
  redis_data:
    driver: local

networks:
  default:
    name: langfuse_internal
  proxy:
    external: true
```

- [ ] **Step 4: Create `inference/langfuse/docker-compose.dev.yaml`**

```yaml
# Dev override: publishes Langfuse web UI port for direct access.
# Usage: docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d
services:
  langfuse-web:
    ports:
      - "${LANGFUSE_WEB_PORT:-3001}:3000"
```

- [ ] **Step 5: Verify compose config parses**

```bash
cd inference/langfuse && docker compose config --quiet && echo "OK" && cd -
cd inference/langfuse && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml config --quiet && echo "OK (dev)" && cd -
```

- [ ] **Step 6: Commit**

```bash
git add inference/langfuse/docker-compose.yaml inference/langfuse/docker-compose.dev.yaml
git commit -m "refactor(langfuse): proxy network + move port to dev override

- langfuse-web joins proxy network (LiteLLM reaches it as langfuse-web:3000)
- Port 3001 moved to docker-compose.dev.yaml (dev-only per spec)
- Internal services (postgres, redis, clickhouse, minio, worker) stay on default"
```

---

### Task 7: Refactor LiteLLM stack — compose + .env + config + dev override

**Files:**
- Modify: `inference/litellm/docker-compose.yaml`
- Modify: `inference/litellm/.env`
- Modify: `inference/litellm/litellm-config.yaml` (full rewrite)
- Create: `inference/litellm/docker-compose.dev.yaml`

- [ ] **Step 1: Remove `extra_hosts` from litellm service in `docker-compose.yaml`**

Find:
```yaml
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

Replace with nothing (delete these two lines).

- [ ] **Step 2: Remove `ports` from litellm service**

Find:
```yaml
    ports:
      - ${LITELLM_PORT:-8000}:8000
```

Replace with nothing (delete these two lines).

- [ ] **Step 3: Add proxy network to litellm service**

After the litellm service's `environment:` block (after the last env var `OTEL_HEADERS`), add:

Find:
```yaml
      OTEL_HEADERS: "Authorization=Basic ${LANGFUSE_AUTH}"
```

Replace with:
```yaml
      OTEL_HEADERS: "Authorization=Basic ${LANGFUSE_AUTH}"
    networks:
      - default
      - proxy
```

- [ ] **Step 4: Add network declarations at the bottom**

After the `volumes:` section, add:

Find:
```yaml
volumes:
  redis_data:
    driver: local
  postgres_data:
    driver: local
```

Replace with:
```yaml
volumes:
  redis_data:
    driver: local
  postgres_data:
    driver: local

networks:
  default:
    name: litellm_internal
  proxy:
    external: true
```

- [ ] **Step 5: Update `inference/litellm/.env` — change LANGFUSE_HOST**

Find:
```
LANGFUSE_HOST=http://host.docker.internal:3001
```

Replace with:
```
# Docker DNS: langfuse-web service on the shared proxy network, internal port 3000
LANGFUSE_HOST=http://langfuse-web:3000
```

- [ ] **Step 6: Replace `inference/litellm/litellm-config.yaml` with target state**

```yaml
model_list:
  - model_name: gemma-4-26B-A4B-it
    litellm_params:
      # openai/ prefix for OpenAI-compatible vLLM endpoint
      # Note: hosted_vllm/ prefix requires LiteLLM >= v1.50; pinned at v1.41.14
      model: openai/gemma-4-26B-A4B-it
      # Docker DNS: vllm service on the shared proxy network, internal port 8000
      api_base: http://vllm:8000/v1
    model_info:
      mode: chat

  # Alias so OpenAI-compatible clients work without reconfiguration
  - model_name: gpt-4
    litellm_params:
      model: openai/gemma-4-26B-A4B-it
      api_base: http://vllm:8000/v1

litellm_settings:
  # drop_params: false ensures unrecognized params raise errors instead of
  # being silently stripped (prevents response_format from vanishing)
  drop_params: false
  set_verbose: false
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  background_health_checks: true
  # Reduced from 300s — 60s detects vLLM failures faster
  health_check_interval: 60
```

Changes from original:
- Model: `gpt-oss-20b` → `gemma-4-26B-A4B-it`
- `api_base`: `http://host.docker.internal:8001/v1` → `http://vllm:8000/v1` (Docker DNS + internal port)
- `gpt-4` alias now points to `gemma-4-26B-A4B-it`

- [ ] **Step 7: Create `inference/litellm/docker-compose.dev.yaml`**

```yaml
# Dev override: publishes LiteLLM port for direct smoke tests.
# Usage: docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d
services:
  litellm:
    ports:
      - "${LITELLM_PORT:-8000}:8000"
```

- [ ] **Step 8: Verify compose config parses**

```bash
cd inference/litellm && docker compose config --quiet && echo "OK" && cd -
cd inference/litellm && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml config --quiet && echo "OK (dev)" && cd -
```

- [ ] **Step 9: Commit**

```bash
git add inference/litellm/docker-compose.yaml inference/litellm/.env \
      inference/litellm/litellm-config.yaml inference/litellm/docker-compose.dev.yaml
git commit -m "refactor(litellm): proxy network + Gemma 4 routing + Docker DNS

- Remove extra_hosts (host.docker.internal eliminated)
- Move port 8000 to dev override
- litellm service joins proxy network
- LANGFUSE_HOST: host.docker.internal:3001 -> langfuse-web:3000
- litellm-config: gpt-oss-20b -> gemma-4-26B-A4B-it, api_base -> vllm:8000
- gpt-4 alias preserved for downstream client compatibility"
```

---

### Task 8: Refactor Authentik stack — compose + .env + dev override

**Files:**
- Modify: `web/authentik/docker-compose.yaml`
- Modify: `web/authentik/.env`
- Create: `web/authentik/docker-compose.dev.yaml`

- [ ] **Step 1: Rename `server` service to `authentik-server` and add networks**

In `web/authentik/docker-compose.yaml`, rename the service key and add networking.

Find:
```yaml
services:
  server:
    image: ${AUTHENTIK_IMAGE:-ghcr.io/goauthentik/server}:${AUTHENTIK_TAG:?error}
    command: server
    restart: unless-stopped
    shm_size: 512mb
    environment:
      <<: *authentik-env
    volumes: *authentik-vols
    ports:
      - "${AUTHENTIK_PORT_HTTP:-80}:9000"
      - "${AUTHENTIK_PORT_HTTPS:-443}:9443"
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

Replace with:
```yaml
services:
  authentik-server:
    image: ${AUTHENTIK_IMAGE:-ghcr.io/goauthentik/server}:${AUTHENTIK_TAG:?error}
    command: server
    restart: unless-stopped
    shm_size: 512mb
    environment:
      <<: *authentik-env
    volumes: *authentik-vols
    ports:
      - "${AUTHENTIK_PORT_HTTPS:-443}:9443"
      - "${AUTHENTIK_PORT_HTTP:-9000}:9000"
    networks:
      - default
      - proxy
```

Changes:
- Service renamed from `server` to `authentik-server` (prevents DNS collision on shared proxy network)
- `extra_hosts` removed
- Port mapping: HTTP default changed from 80 to 9000 (OIDC discovery port, spec table)
- `networks: [default, proxy]` added

- [ ] **Step 2: Remove `extra_hosts` from worker service**

Find:
```yaml
  worker:
    image: ${AUTHENTIK_IMAGE:-ghcr.io/goauthentik/server}:${AUTHENTIK_TAG:?error}
    command: worker
    restart: unless-stopped
    user: root
    shm_size: 512mb
    environment:
      <<: *authentik-env
    volumes: *authentik-vols
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

Replace with:
```yaml
  worker:
    image: ${AUTHENTIK_IMAGE:-ghcr.io/goauthentik/server}:${AUTHENTIK_TAG:?error}
    command: worker
    restart: unless-stopped
    user: root
    shm_size: 512mb
    environment:
      <<: *authentik-env
    volumes: *authentik-vols
```

- [ ] **Step 3: Add network declarations at the end of the file**

After the worker service's closing (after `logging: *default-logging`), add the networks section. If the file doesn't already have a `networks:` section at the top level, add it at the bottom:

```yaml

networks:
  default:
    name: authentik_internal
  proxy:
    external: true
```

- [ ] **Step 4: Update `web/authentik/.env` — change HTTP port default**

Find:
```
AUTHENTIK_PORT_HTTP=80
```

Replace with:
```
# HTTP port: 9000 for internal OIDC discovery (Phase 7 will add cert trust and remove)
AUTHENTIK_PORT_HTTP=9000
```

- [ ] **Step 5: Create `web/authentik/docker-compose.dev.yaml`**

```yaml
# Dev override: publishes HTTP redirect port for development convenience.
# Usage: docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d
services:
  authentik-server:
    ports:
      - "80:9000"
```

- [ ] **Step 6: Verify compose config parses**

```bash
cd web/authentik && docker compose config --quiet && echo "OK" && cd -
cd web/authentik && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml config --quiet && echo "OK (dev)" && cd -
```

- [ ] **Step 7: Commit**

```bash
git add web/authentik/docker-compose.yaml web/authentik/.env web/authentik/docker-compose.dev.yaml
git commit -m "refactor(authentik): proxy network + rename server to authentik-server

- Rename server -> authentik-server (prevent DNS collision on shared proxy network)
- Remove extra_hosts from server and worker
- authentik-server joins proxy network; worker stays on default only
- HTTP port default: 80 -> 9000 (OIDC discovery, Phase 7 removes)
- db/include.yaml intentionally untouched (postgres/redis stay on default)"
```

---

### Task 9: Refactor Onyx stack — compose + .env + dev override

**Files:**
- Modify: `web/onyx/docker-compose.yaml`
- Modify: `web/onyx/.env`
- Create: `web/onyx/docker-compose.dev.yaml`

- [ ] **Step 1: Remove `extra_hosts` from `api_server` service**

Find:
```yaml
    extra_hosts:
      - "host.docker.internal:host-gateway"
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "6"
    # Optional, only for debugging purposes
    volumes:
      - api_server_logs:/var/log/onyx
```

Replace with (in the `api_server` service):
```yaml
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "6"
    # Optional, only for debugging purposes
    volumes:
      - api_server_logs:/var/log/onyx
    networks:
      - default
      - proxy
```

- [ ] **Step 2: Remove `extra_hosts` from `background` service and add proxy network**

Find (in the `background` service):
```yaml
    extra_hosts:
      - "host.docker.internal:host-gateway"
    # Optional, only for debugging purposes
    volumes:
      - background_logs:/var/log/onyx
```

Replace with:
```yaml
    # Optional, only for debugging purposes
    volumes:
      - background_logs:/var/log/onyx
    networks:
      - default
      - proxy
```

- [ ] **Step 3: Remove published port from `nginx` service and add proxy network**

Find (in the `nginx` service):
```yaml
    ports:
      # - "80:80"
      - "${HOST_PORT:-3000}:80" # allow for localhost:3000 usage, since that is the norm
```

Replace with:
```yaml
    # Ports removed — Onyx is reached through Authentik proxy provider.
    # For dev access, use: docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d
```

Also, at the end of the `nginx` service block (after the `command:` section), add:

Find:
```yaml
    command: >
      /bin/sh -c "dos2unix /etc/nginx/conf.d/run-nginx.sh 
      && /etc/nginx/conf.d/run-nginx.sh app.conf.template"
```

Replace with:
```yaml
    command: >
      /bin/sh -c "dos2unix /etc/nginx/conf.d/run-nginx.sh 
      && /etc/nginx/conf.d/run-nginx.sh app.conf.template"
    networks:
      - default
      - proxy
```

- [ ] **Step 4: Add network declarations at the bottom**

After the `volumes:` section at the bottom of the file, add:

```yaml

networks:
  default:
    name: onyx_internal
  proxy:
    external: true
```

- [ ] **Step 5: Update `web/onyx/.env` — change OIDC discovery URL**

Find:
```
OPENID_CONFIG_URL=http://host.docker.internal:9000/application/o/onyx/.well-known/openid-configuration
```

Replace with:
```
# Docker DNS: authentik-server on the shared proxy network, internal port 9000
OPENID_CONFIG_URL=http://authentik-server:9000/application/o/onyx/.well-known/openid-configuration
```

- [ ] **Step 6: Create `web/onyx/docker-compose.dev.yaml`**

```yaml
# Dev override: publishes Onyx ports for direct access during development.
# Usage: docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d
services:
  nginx:
    ports:
      - "${HOST_PORT:-3000}:80"
  api_server:
    ports:
      - "8080:8080"
  relational_db:
    ports:
      - "5432:5432"
  index:
    ports:
      - "19071:19071"
      - "8081:8081"
  cache:
    ports:
      - "6379:6379"
  minio:
    ports:
      - "9004:9000"
      - "9005:9001"
```

- [ ] **Step 7: Verify compose config parses**

```bash
cd web/onyx && docker compose config --quiet && echo "OK" && cd -
cd web/onyx && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml config --quiet && echo "OK (dev)" && cd -
```

- [ ] **Step 8: Commit**

```bash
git add web/onyx/docker-compose.yaml web/onyx/.env web/onyx/docker-compose.dev.yaml
git commit -m "refactor(onyx): proxy network + Docker DNS for OIDC

- Remove extra_hosts from api_server and background
- nginx, api_server, background join proxy network
- Remove nginx published port (reached via Authentik proxy provider)
- OPENID_CONFIG_URL: host.docker.internal:9000 -> authentik-server:9000
- Dev override restores all service ports for development"
```

---

### Task 10: Refactor Open-WebUI stack — compose + dev override

**Files:**
- Modify: `web/open-webui/docker-compose.yaml`
- Create: `web/open-webui/docker-compose.dev.yaml`

- [ ] **Step 1: Remove `extra_hosts` and `ports`, add proxy network**

Replace `web/open-webui/docker-compose.yaml` with:

```yaml
services:
  open-webui:
    image: ${OPENWEBUI_IMAGE}
    volumes:
      - data:/app/backend/data
    environment:
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY:?error}
      - ENABLE_SIGNUP=${ENABLE_SIGNUP:-True}
      - DEFAULT_USER_ROLE=${DEFAULT_USER_ROLE:-user}
      - JWT_EXPIRES_IN=${JWT_EXPIRES_IN:-24h}
      - AUTHENTIK_SHARED_SECRET=${AUTHENTIK_SHARED_SECRET:-}
      - ENABLE_OLLAMA_API=${ENABLE_OLLAMA_API:-False}
      - SCARF_NO_ANALYTICS=${SCARF_NO_ANALYTICS:-true}
      - DO_NOT_TRACK=${DO_NOT_TRACK:-true}
      - ANONYMIZED_TELEMETRY=${ANONYMIZED_TELEMETRY:-false}
    restart: unless-stopped
    networks:
      - proxy

volumes:
  data: {}

networks:
  proxy:
    external: true
```

Changes from original:
- `ports` removed (reached through Authentik proxy provider)
- `extra_hosts` removed
- `networks: [proxy]` added (single-service stack, LACI-aligned pattern)
- Network declaration added at bottom

- [ ] **Step 2: Create `web/open-webui/docker-compose.dev.yaml`**

```yaml
# Dev override: publishes Open-WebUI port for direct access.
# Usage: docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d
services:
  open-webui:
    ports:
      - "${OPEN_WEBUI_PORT_HTTP:-3002}:8080"
```

- [ ] **Step 3: Verify compose config parses**

```bash
cd web/open-webui && docker compose config --quiet && echo "OK" && cd -
cd web/open-webui && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml config --quiet && echo "OK (dev)" && cd -
```

- [ ] **Step 4: Commit**

```bash
git add web/open-webui/docker-compose.yaml web/open-webui/docker-compose.dev.yaml
git commit -m "refactor(open-webui): proxy network + move port to dev override

- Remove extra_hosts and ports from base compose
- Join proxy network (single-service stack, matches LACI pattern)
- Dev override publishes port 3002 for direct access"
```

---

## Phase 2 Gate: Stack Smoke Test

### Task 11: [HUMAN GATE] Verify all stacks on new topology

This must be performed inside `basalt-host` after all compose refactors. The repo on `basalt-host` must be updated with the Phase 2 commits.

- [ ] **Step 1: Update repo on basalt-host**

```bash
# Inside basalt-host, pull latest from the branch
cd /opt/basalt/basalt-stack-v1.0
git pull  # or rsync from Windows mount
```

- [ ] **Step 2: Verify proxy network exists**

```bash
docker network ls | grep proxy
```

Expected: `proxy` network listed.

- [ ] **Step 3: Start stacks in order (with dev overrides for smoke testing)**

```bash
cd /opt/basalt/basalt-stack-v1.0

cd inference/vllm && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d && cd -
cd inference/langfuse && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d && cd -
cd inference/litellm && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d && cd -
cd web/authentik && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d && cd -
cd web/onyx && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d && cd -
cd web/open-webui && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d && cd -
```

- [ ] **Step 4: Verify all containers healthy**

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Expected: all containers running, health checks passing. vLLM may take up to 10 minutes for first model load (start_period: 600s).

- [ ] **Step 5: Verify cross-stack DNS resolution**

```bash
# From the litellm container, can it reach vllm?
docker exec $(docker ps -qf "name=litellm-litellm") sh -c "getent hosts vllm"

# From the litellm container, can it reach langfuse-web?
docker exec $(docker ps -qf "name=litellm-litellm") sh -c "getent hosts langfuse-web"
```

Expected: both resolve to container IPs on the `proxy` network.

- [ ] **Step 6: Verify proxy network membership**

```bash
docker network inspect proxy --format '{{range .Containers}}{{.Name}} {{end}}'
```

Expected: containers from all stacks that should be on proxy are listed (vllm, litellm, langfuse-web, authentik-server, nginx, api_server, background, open-webui).

- [ ] **Step 7: E2E smoke test (requires model weights loaded)**

```bash
# Direct vLLM test (dev port)
curl -sf http://localhost:8001/v1/models | grep gemma-4-26B-A4B-it

# LiteLLM through vLLM
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(grep LITELLM_MASTER_KEY inference/litellm/.env | cut -d= -f2)" \
  -d '{"model": "gpt-4", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 10}'

# Langfuse: check trace appeared
curl -sf http://localhost:3001/api/public/health
```

- [ ] **Step 8: Measure vLLM cold start time**

```bash
cd inference/vllm && docker compose down && cd -
time (cd inference/vllm && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d && \
  until curl -sf http://localhost:8001/v1/models > /dev/null 2>&1; do sleep 2; done && \
  echo "vLLM ready")
```

Expected: < 60 seconds (ext4 vs previous 2-5 min on 9p). Document actual result.

**Gate:** All six stacks healthy, cross-stack DNS works, E2E chat trace confirmed. Proceed to Phase 3.

---

## Phase 3: Portainer + Authentik Integration

### Task 12: Create Portainer stack

**Files:**
- Create: `ops/portainer/docker-compose.yaml`
- Create: `ops/portainer/docker-compose.dev.yaml`

- [ ] **Step 1: Create directory and compose file**

Create `ops/portainer/docker-compose.yaml`:

```yaml
services:
  portainer:
    image: portainer/portainer-ce:2.27.4
    restart: unless-stopped
    command: --no-analytics
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer_data:/data
    networks:
      - proxy

volumes:
  portainer_data:

networks:
  proxy:
    external: true
```

Notes:
- `--no-analytics` for air-gap compliance (no outbound telemetry)
- Docker socket mounted read-only where possible (Portainer may need write for restart/exec)
- Single-service stack: proxy only, no default network needed (LACI pattern)
- No ports in base compose — reached through Authentik proxy provider
- Portainer listens on 9000 (HTTP) and 9443 (HTTPS) internally

- [ ] **Step 2: Create `ops/portainer/docker-compose.dev.yaml`**

```yaml
# Dev override: publishes Portainer HTTPS port for first-run setup.
# First run requires direct access to set admin password before Authentik proxy is configured.
# Usage: docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d
services:
  portainer:
    ports:
      - "9443:9443"
```

- [ ] **Step 3: Verify compose config parses**

```bash
cd ops/portainer && docker compose config --quiet && echo "OK" && cd -
cd ops/portainer && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml config --quiet && echo "OK (dev)" && cd -
```

- [ ] **Step 4: Commit**

```bash
git add ops/portainer/
git commit -m "feat(portainer): add Portainer CE stack for Day-2 ops GUI

- portainer-ce:2.27.4, --no-analytics (air-gap safe)
- Docker socket mounted read-only
- Proxy network only (single-service LACI pattern)
- Dev override publishes 9443 for first-run admin setup"
```

---

### Task 13: Update hosts template

**Files:**
- Modify: `web/authentik/hosts-template.txt`

- [ ] **Step 1: Add Portainer and Langfuse subdomains**

Find:
```
<host-ip>  onyx.basalt.local
<host-ip>  rmf.basalt.local
```

Replace with:
```
<host-ip>  onyx.basalt.local
<host-ip>  portainer.basalt.local
<host-ip>  langfuse.basalt.local
<host-ip>  rmf.basalt.local
```

- [ ] **Step 2: Commit**

```bash
git add web/authentik/hosts-template.txt
git commit -m "docs: add portainer + langfuse subdomains to hosts template"
```

---

### Task 14: [HUMAN GATE] Configure Authentik proxy provider for Portainer

This is a manual GUI configuration in the Authentik admin interface. Perform after Task 12 (Portainer running) and Task 13 (hosts updated).

- [ ] **Step 1: Start Portainer with dev override for first-run setup**

```bash
cd ops/portainer && docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d && cd -
```

- [ ] **Step 2: Complete Portainer first-run setup**

Browse to `https://localhost:9443` (accept self-signed cert). Set admin password. Select "Docker" environment → connect to local socket.

- [ ] **Step 3: Verify Portainer sees all stacks**

In Portainer UI → Stacks: all six Basalt stacks should appear as "external" stacks. If not, verify Docker socket mount and that all stacks are running.

- [ ] **Step 4: Create Authentik proxy provider for Portainer**

In Authentik admin (https://auth.basalt.local/if/admin/):

1. **Providers** → Create → Proxy Provider
   - Name: `portainer-proxy`
   - External host: `https://portainer.basalt.local`
   - Internal host: `http://portainer:9000` (Docker DNS on proxy network)
   - Auth mode: Forward auth (single application)

2. **Applications** → Create
   - Name: `Portainer`
   - Slug: `portainer`
   - Provider: `portainer-proxy`
   - Launch URL: `https://portainer.basalt.local`

3. **Outposts** → Edit embedded outpost → add `portainer-proxy` provider

- [ ] **Step 5: Add `portainer.basalt.local` to client hosts file**

Per the updated `hosts-template.txt`.

- [ ] **Step 6: Verify end-to-end**

Browse to `https://portainer.basalt.local`. Should redirect to Authentik login, then proxy to Portainer dashboard.

- [ ] **Step 7: Capture Authentik proxy provider config as blueprint (U8)**

In Authentik admin → Admin Interface → System → Blueprints → Export. Export the blueprint that includes the Portainer proxy provider and application. Save to `web/authentik/blueprints/custom/portainer-proxy.yaml`.

```bash
git add web/authentik/blueprints/custom/portainer-proxy.yaml
git commit -m "feat(authentik): capture Portainer proxy provider blueprint (U8)"
```

- [ ] **Step 8: Remove dev override (port 9443 no longer needed)**

```bash
cd ops/portainer && docker compose down && docker compose up -d && cd -
```

- [ ] **Step 9: Verify stacks still adopted after switching to base compose**

Browse to `https://portainer.basalt.local` → verify all six stacks still appear as adopted.

**Gate:** Portainer reachable through Authentik front door, all six stacks visible and adopted.

---

## Phase 4: Forgejo Migration

### Task 15: [HUMAN GATE] Migrate Forgejo to basalt-host

This is a manual operational task. Forgejo is the only non-Basalt container on Docker Desktop and must be migrated before Docker Desktop can be removed (§4.6 prerequisite).

- [ ] **Step 1: Identify Forgejo volumes on Docker Desktop**

```bash
# From Docker Desktop's WSL integration or Windows
docker volume ls | grep forgejo
```

- [ ] **Step 2: Backup Forgejo volumes**

```bash
# From Docker Desktop context
docker run --rm -v forgejo_data:/source -v /tmp/forgejo-backup:/backup alpine \
  tar czf /backup/forgejo-data.tar.gz -C /source .
```

Copy the tarball to basalt-host:
```bash
cp /tmp/forgejo-backup/forgejo-data.tar.gz /mnt/d/BASALT/staging/
```

- [ ] **Step 3: Set up Forgejo on basalt-host**

```bash
# Inside basalt-host
mkdir -p /opt/dev/forgejo
# Copy Forgejo compose file from Docker Desktop setup to /opt/dev/forgejo/
# Restore volumes:
docker volume create forgejo_data
docker run --rm -v forgejo_data:/target -v /mnt/d/BASALT/staging:/backup alpine \
  sh -c "cd /target && tar xzf /backup/forgejo-data.tar.gz"
```

- [ ] **Step 4: Start Forgejo on basalt-host and verify**

```bash
cd /opt/dev/forgejo && docker compose up -d
```

Test: clone a repo, push a commit, verify data integrity.

- [ ] **Step 5: Stop Forgejo on Docker Desktop**

Only after verification passes on basalt-host.

**Gate:** Forgejo clone + push works on basalt-host. Proceed to Phase 5.

---

## Phase 5: Docker Desktop Removal

### Task 16: [HUMAN GATE] Remove Docker Desktop

**Prerequisites (all must pass):**
1. ✅ All six Basalt stacks verified healthy on basalt-host (Task 11)
2. ✅ Portainer reachable through Authentik (Task 14)
3. ✅ Forgejo migrated and verified (Task 15)
4. ✅ `wsl --export basalt-host` tested (Phase 8, or do a quick test now)

- [ ] **Step 1: Verify everything runs on basalt-host**

```bash
wsl -d basalt-host -- docker ps
```

All containers should be running.

- [ ] **Step 2: Uninstall Docker Desktop**

Windows Settings → Apps → Docker Desktop → Uninstall. Reboot when prompted.

- [ ] **Step 3: Verify Docker still works after uninstall**

```bash
wsl -d basalt-host -- docker ps
wsl -d basalt-host -- docker compose version
```

Expected: Docker works inside basalt-host (it runs Docker Engine natively, not via Docker Desktop).

- [ ] **Step 4: Verify Windows interop**

```powershell
wsl -d basalt-host -- docker ps
```

Expected: can run docker commands from PowerShell via WSL interop.

**Gate:** Docker Desktop uninstalled, Docker commands work from basalt-host and Windows interop.

---

## Phase 6: LACI Structural-Alignment Diff Pass

### Task 17: Walk each service against LACI counterpart

**Files:**
- LACI reference: `laci-24mar/laci-stack-v1.1/` (read-only input)
- May modify: any Basalt compose file or config where trivial alignment fixes are found

This task is a structured research + fix pass. For each service, compare Basalt's compose file against LACI's counterpart and categorize deltas.

**Alignment rules (from brainstorm):**
- ✅ Tight alignment: topology patterns, file/directory structure, naming conventions, operator UX
- ❌ Allowed to drift: stack component versions, LLM choice, host OS

- [ ] **Step 1: Diff vLLM**

```bash
diff <(cd inference/vllm && docker compose config) \
     <(cd laci-24mar/laci-stack-v1.1/inference/vllm && docker compose config) \
     || true
```

**Known justified delta:** Basalt uses single `proxy` network; LACI uses `inference-endpoint`. This is justified by single-host vs multi-host topology difference.

Check: service name, volume mount patterns, env var naming, image variable pattern (`${DOCKER_IMAGE_REPO}` prefix in LACI?).

- [ ] **Step 2: Diff Langfuse**

Compare `inference/langfuse/docker-compose.yaml` vs LACI's version. LACI uses `include: ./db/include.yaml` for db services; Basalt inlines them. This is a known structural delta. Fix if trivial (extract to include file) or flag as follow-up.

- [ ] **Step 3: Diff LiteLLM**

Compare compose structure, `litellm-config.yaml` format, env var naming. LACI uses `include: ./db/include.yaml` for db; Basalt inlines.

- [ ] **Step 4: Diff Authentik**

Compare compose structure. Key known delta: Basalt renames `server` to `authentik-server` (justified — single-network DNS collision prevention). LACI uses `proxy` network (aligned). LACI uses older version (allowed drift).

- [ ] **Step 5: Diff Onyx**

Compare compose structure. LACI uses extensive `include:` for db, minio, nginx, vespa. Basalt inlines everything. LACI uses YAML extension fields (`x-env-db`, `x-env-services`, `x-logging-config`). These are structural patterns to evaluate.

- [ ] **Step 6: Diff Open-WebUI**

Compare compose structure. LACI uses `${DOCKER_IMAGE_REPO}` prefix on image. Basalt doesn't. Evaluate alignment cost.

- [ ] **Step 7: Document findings**

For each delta found:
- **Trivial fix**: apply inline, include in commit
- **Non-trivial**: record as a follow-up in `todos/` with priority

- [ ] **Step 8: Commit fixes**

```bash
git add -A
git commit -m "refactor: LACI structural-alignment fixes from diff pass

[list specific fixes applied]"
```

---

## Phase 7: Documentation Updates

### Task 18: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update Architecture diagram**

Find the existing architecture diagram in CLAUDE.md and replace with:

````
```
  Client (browser)
    │
    │  DNS/hosts: *.basalt.local → <host-ip>
    │
    ▼
  ┌──────────────────────────────────────────────┐
  │         Authentik (port 443 / 9443)          │
  │                                              │
  │  auth.basalt.local → App Launcher / Login    │
  │  webui.basalt.local → Proxy ────────────────►│──→ Open-WebUI (8080)
  │  onyx.basalt.local  → Proxy + OIDC ─────────│──→ Onyx/nginx (80)
  │  portainer.basalt.local → Proxy ─────────────│──→ Portainer (9000)
  │                                              │
  │  Embedded Outpost (proxy mode)               │
  └──────────────────────────────────────────────┘
                        │
                        │ Docker network: proxy (shared external)
                        │ Cross-stack traffic uses Docker DNS
                        ▼
              ┌─────────────────┐
              │  LiteLLM (8000) │──→ Langfuse (3000)
              └────────┬────────┘
                       │
              ┌────────▼────────┐
              │   vLLM (8000)   │
              │  Gemma 4 26B-A4B│
              │  (AWQ 4-bit)    │
              └─────────────────┘
```
````

- [ ] **Step 2: Update Service Port Map table**

Replace the existing port table with:

```markdown
| Service | Internal Port | Published Port | Compose Location |
|---------|--------------|---------------|-----------------|
| Authentik | 9443/9000 | 443, 9000 | `web/authentik/` |
| vLLM | 8000 | 8001 (dev only) | `inference/vllm/` |
| LiteLLM | 8000 | 8000 (dev only) | `inference/litellm/` |
| Langfuse | 3000 | 3001 (dev only) | `inference/langfuse/` |
| Onyx/nginx | 80 | 3000 (dev only) | `web/onyx/` |
| Open-WebUI | 8080 | 3002 (dev only) | `web/open-webui/` |
| Portainer | 9000/9443 | 9443 (dev only) | `ops/portainer/` |
```

- [ ] **Step 3: Update Networking section**

Replace the networking section to reflect the proxy network topology:

```markdown
## Networking

All service stacks attach to a shared external Docker network named `proxy`. Cross-stack traffic uses Docker DNS service names (e.g., `litellm` reaches `vllm:8000`, not `host.docker.internal:8001`).

Within a **single compose stack**, services use in-stack service names (`redis`, `postgres`) on the stack's internal network.

**Bootstrap requirement:** `docker network create proxy` must run once per host before starting any stack.

**Dev overrides:** Each stack has a `docker-compose.dev.yaml` that publishes ports for direct access during development. Usage: `docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d`.

> See `docs/guides/compose-networking.md` for the `external: true` gotcha (R3).
```

- [ ] **Step 4: Update Startup Sequence**

Update the startup sequence to include Portainer and note dev override usage:

```markdown
## Startup Sequence

Each command assumes you are in the **repo root** (`basalt-stack-v1.0/`). For dev with published ports, add `-f docker-compose.dev.yaml` to each command.

```bash
# 0. Ensure proxy network exists (one-time per host)
docker network create proxy 2>/dev/null || true

# 1. Start vLLM
cd inference/vllm && docker compose up -d && cd -

# 2. Start Langfuse (observability)
cd inference/langfuse && docker compose up -d && cd -

# 3. Start LiteLLM (LLM gateway)
cd inference/litellm && docker compose up -d && cd -

# 4. Start Authentik (SSO portal)
cd web/authentik && docker compose up -d && cd -

# 5. Start Onyx
cd web/onyx && docker compose up -d && cd -

# 6. (Optional) Start Open-WebUI
cd web/open-webui && docker compose up -d && cd -

# 7. Start Portainer (Day-2 ops GUI — must be last for stack adoption)
cd ops/portainer && docker compose up -d && cd -
```
```

- [ ] **Step 5: Update Gotchas section**

Add/update gotchas:

```markdown
- **Proxy network bootstrap**: `docker network create proxy` must run before any stack starts. The bootstrap script does this, but manual setups must run it explicitly.
- **`external: true` silent failure (R3)**: If any compose file omits `external: true` on the `proxy` network, cross-stack DNS fails silently (NXDOMAIN, no log). See `docs/guides/compose-networking.md`.
- **Model weights path**: `/opt/basalt/models/gemma-4-26B-A4B-it-AWQ-4bit` — ext4 inside basalt-host WSL2 distro. No 9p bridge; cold start < 60s.
- **Gemma 4 known vLLM issues (R1)**: MoE boot crash (#39066), vision shape mismatch (#39061 — workaround: `--limit-mm-per-prompt image=0,audio=0`), reasoning parser (#39130). Fallback: roll back to gpt-oss-20b.
- **`gpt-4` alias**: `litellm-config.yaml` maps `gpt-4` → `gemma-4-26B-A4B-it` so OpenAI-compatible clients work without reconfiguration.
- **Authentik service rename**: Authentik's server service is `authentik-server` (not `server`) to prevent DNS collision on the shared proxy network.
- **Portainer is not deployment source of truth**: Portainer adopts existing stacks for Day-2 ops. Compose files + LACI Updater remain canonical for deployment.
```

- [ ] **Step 6: Update model weights path gotcha**

Remove or update the old gotcha about 9p bridge and D:/ model path.

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for WSL2 + proxy network + Gemma 4 topology"
```

---

### Task 19: Create WSL2 deployment guide

**Files:**
- Create: `docs/guides/deployment-guide-wsl2.md`

- [ ] **Step 1: Write the deployment guide**

This guide is a sibling of `deployment-guide-dev.md`, rewritten for the WSL2 + proxy network topology. It should cover:

```markdown
# Basalt Stack — WSL2 Deployment Guide

> Last synced with bootstrap-basalt-host.sh: <commit-hash>

## Prerequisites

- Windows 11 with WSL2 2.0+ enabled
- NVIDIA GPU driver installed on Windows host
- `.wslconfig` with `networkingMode=mirrored` (see Section 0.1)
- Ubuntu 24.04 rootfs tarball (pre-staged for air-gap)

## Section 0: Windows Host Setup

### 0.1 Configure `.wslconfig`

Create `%USERPROFILE%\.wslconfig`:
```ini
[wsl2]
networkingMode=mirrored
```

### 0.2 Run Prereq Checker

```powershell
.\scripts\check-host-prereqs.ps1
```

### 0.3 Create basalt-host Distro

```powershell
wsl --import basalt-host D:\WSL\basalt-host\ <path-to-rootfs.tar> --version 2
wsl -d basalt-host
./scripts/bootstrap-basalt-host.sh
```

## Section 1: Model Weights

Copy Gemma 4 26B-A4B (AWQ 4-bit) weights to `/opt/basalt/models/gemma-4-26B-A4B-it-AWQ-4bit/`.

Required files: `config.json`, `tokenizer.json`, `*.safetensors`

## Section 2: vLLM Inference Engine

```bash
cd inference/vllm && docker compose up -d && cd -
```

Verify:
```bash
# With dev override for direct port access:
docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d
curl http://localhost:8001/v1/models
```

## Section 3: Langfuse Observability

```bash
cd inference/langfuse && docker compose up -d && cd -
```

## Section 4: LiteLLM Gateway

```bash
cd inference/litellm && docker compose up -d && cd -
```

Verify LiteLLM → vLLM → Langfuse end-to-end:
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <LITELLM_MASTER_KEY>" \
  -d '{"model": "gpt-4", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 10}'
```

## Section 5: Authentik SSO Portal

```bash
cd web/authentik && docker compose up -d && cd -
```

Browse: https://auth.basalt.local

## Section 6: Open-WebUI

```bash
cd web/open-webui && docker compose up -d && cd -
```

## Section 7: Onyx

```bash
cd web/onyx && docker compose up -d && cd -
```

Configure LLM provider URL in Onyx admin: `http://litellm:8000`

## Section 8: Portainer

```bash
cd ops/portainer && docker compose up -d && cd -
```

First-run: use dev override to access Portainer directly at `https://localhost:9443`, set admin password, then switch to base compose.

## Dev Override Pattern

For development, publish service ports for direct access:

```bash
docker compose -f docker-compose.yaml -f docker-compose.dev.yaml up -d
```

This adds back published ports that are removed in production (reached through Authentik proxy instead).

## Appendix: Startup / Shutdown Order

### Startup (from repo root)
```bash
docker network create proxy 2>/dev/null || true
cd inference/vllm && docker compose up -d && cd -
cd inference/langfuse && docker compose up -d && cd -
cd inference/litellm && docker compose up -d && cd -
cd web/authentik && docker compose up -d && cd -
cd web/onyx && docker compose up -d && cd -
cd web/open-webui && docker compose up -d && cd -
cd ops/portainer && docker compose up -d && cd -
```

### Shutdown (reverse order)
```bash
cd ops/portainer && docker compose down && cd -
cd web/open-webui && docker compose down && cd -
cd web/onyx && docker compose down && cd -
cd web/authentik && docker compose down && cd -
cd inference/litellm && docker compose down && cd -
cd inference/langfuse && docker compose down && cd -
cd inference/vllm && docker compose down && cd -
```
```

- [ ] **Step 2: Commit**

```bash
git add docs/guides/deployment-guide-wsl2.md
git commit -m "docs: add WSL2 deployment guide for basalt-host topology"
```

---

### Task 20: Create database operations runbook

**Files:**
- Create: `docs/guides/database-operations-runbook.md`

- [ ] **Step 1: Write the runbook**

```markdown
# Database Operations Runbook

Day-2 database access for Basalt Stack operators and maintainers.

Two paths: **Portainer Console** (GUI, for operators) and **docker exec** (CLI, for scripting/maintainers).

## Langfuse PostgreSQL

**Stack:** `inference/langfuse/`
**Container:** `langfuse-postgres-1` (or similar — check `docker ps`)
**Credentials:** See `inference/langfuse/.env` → `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`

**Portainer Console:**
Containers → `langfuse-postgres-1` → Console → `/bin/sh` → `psql -U postgres -d langfuse`

**docker exec:**
```bash
docker exec -it $(docker ps -qf "name=langfuse.*postgres") psql -U postgres -d langfuse
```

## Authentik PostgreSQL

**Stack:** `web/authentik/`
**Container:** `authentik-postgres-1`
**Credentials:** See `web/authentik/.env` → `PG_USER`, `PG_PASS`, `PG_DB`

**Portainer Console:**
Containers → `authentik-postgres-1` → Console → `/bin/sh` → `psql -U authentik -d authentik`

**docker exec:**
```bash
docker exec -it $(docker ps -qf "name=authentik.*postgres") psql -U authentik -d authentik
```

## Onyx PostgreSQL

**Stack:** `web/onyx/`
**Container:** `onyx-relational_db-1`
**Credentials:** See `web/onyx/.env` → `POSTGRES_USER`, `POSTGRES_PASSWORD`

**Portainer Console:**
Containers → `onyx-relational_db-1` → Console → `/bin/sh` → `psql -U postgres`

**docker exec:**
```bash
docker exec -it $(docker ps -qf "name=onyx.*relational_db") psql -U postgres
```

## LiteLLM PostgreSQL

**Stack:** `inference/litellm/`
**Container:** `litellm-postgres-1`
**Credentials:** See `inference/litellm/.env` → `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`

**Portainer Console:**
Containers → `litellm-postgres-1` → Console → `/bin/sh` → `psql -U postgres -d litellm`

**docker exec:**
```bash
docker exec -it $(docker ps -qf "name=litellm.*postgres") psql -U postgres -d litellm
```

## ClickHouse (Langfuse)

**Stack:** `inference/langfuse/`
**Container:** `langfuse-clickhouse-1`

**Portainer Console:**
Containers → `langfuse-clickhouse-1` → Console → `/bin/sh` → `clickhouse-client`

**docker exec:**
```bash
docker exec -it $(docker ps -qf "name=langfuse.*clickhouse") clickhouse-client
```

## Vespa (Onyx)

**Stack:** `web/onyx/`
**Container:** `onyx-index-1`

Vespa is primarily accessed via its HTTP API (port 19071 for config, 8081 for search). Direct shell access is rarely needed.

**docker exec:**
```bash
docker exec -it $(docker ps -qf "name=onyx.*index") /bin/bash
```

## Redis Instances

| Stack | Container Pattern | Auth |
|-------|-------------------|------|
| LiteLLM | `litellm.*redis` | `REDIS_AUTH` in `inference/litellm/.env` |
| Langfuse | `langfuse.*redis` | `REDIS_AUTH` in `inference/langfuse/.env` (default: `myredissecret`) |
| Authentik | `authentik.*redis` | `REDIS_PASSWORD` in `web/authentik/.env` |
| Onyx | `onyx.*cache` | No auth (ephemeral, `--save "" --appendonly no`) |

**docker exec (example — LiteLLM Redis):**
```bash
docker exec -it $(docker ps -qf "name=litellm.*redis") redis-cli -a '<REDIS_AUTH_VALUE>'
```
```

- [ ] **Step 2: Commit**

```bash
git add docs/guides/database-operations-runbook.md
git commit -m "docs: add database operations runbook (Portainer Console + docker exec)"
```

---

### Task 21: Update auto-memory and park §5f

**Files:**
- Modify: `C:\Users\isse\.claude\projects\D--BASALT-Basalt-Architecture-basalt-stack-v1-0\memory\MEMORY.md` (auto-memory index)
- Modify: `C:\Users\isse\.claude\projects\D--BASALT-Basalt-Architecture-basalt-stack-v1-0\memory\project_next_steps.md`

- [ ] **Step 1: Update MEMORY.md architecture decisions table**

Update the "Architecture Decisions" table in MEMORY.md to reflect:

| Decision | Choice |
|----------|--------|
| Model (MVP) | **gemma-4-26B-A4B-it (AWQ 4-bit)** (was gpt-oss-20b) |
| Networking | **Shared `proxy` Docker network** (was host.docker.internal) |
| Runtime | **WSL2 native Docker Engine in basalt-host** (was Docker Desktop) |
| Day-2 Ops | **Portainer CE** (new) |

Also update the Service Port Map to reflect internal vs published ports and the new Portainer entry.

- [ ] **Step 2: Update project_next_steps.md — park §5f with resume trigger**

Add a §5f parking section:

```markdown
## §5f Custom Enrollment Flow — PARKED

**Parked by:** WSL2 + Portainer pivot (2026-04-10)
**Why parked:** Default Authentik enrollment is MORE LACI-aligned. LACI ships zero
Authentik customization. Federal controls (AC/IA/AU/SC) satisfied by vanilla Authentik.
**Intent:** Custom enrollment flow for invitation-only onboarding (no self-signup).
**Baseline:** §5a-5e complete; §5f was next before pivot.
**Resume trigger:** Leadership requests custom enrollment OR LACI adds enrollment customization.
**Do NOT resume:** Automatically or without explicit user request.
```

- [ ] **Step 3: No git commit** (auto-memory is outside the repo)

---

## Phase 8: Air-Gap Export Rehearsal

### Task 22: [HUMAN GATE] Export and verify tarball

- [ ] **Step 1: Stop all stacks cleanly**

```bash
# Inside basalt-host, from repo root
cd ops/portainer && docker compose down && cd -
cd web/open-webui && docker compose down && cd -
cd web/onyx && docker compose down && cd -
cd web/authentik && docker compose down && cd -
cd inference/litellm && docker compose down && cd -
cd inference/langfuse && docker compose down && cd -
cd inference/vllm && docker compose down && cd -
```

- [ ] **Step 2: Terminate the distro**

```powershell
wsl --terminate basalt-host
```

- [ ] **Step 3: Export the distro**

```powershell
wsl --export basalt-host D:\BASALT\staging\basalt-host-v1.0.tar
```

Note the file size and export time. This tarball contains: OS + Docker Engine + all Docker images + model weights + Basalt repo.

- [ ] **Step 4: Re-import on a clean path (verification)**

```powershell
wsl --import basalt-host-test D:\WSL\basalt-host-test\ D:\BASALT\staging\basalt-host-v1.0.tar --version 2
wsl -d basalt-host-test
```

Inside the test distro:
```bash
docker ps  # should be empty (clean start)
docker network create proxy
cd /opt/basalt/basalt-stack-v1.0
cd inference/vllm && docker compose up -d && cd -
# ... start remaining stacks ...
```

Verify all stacks come up healthy without internet access.

- [ ] **Step 5: Clean up test distro**

```powershell
wsl --unregister basalt-host-test
Remove-Item -Recurse D:\WSL\basalt-host-test\
```

- [ ] **Step 6: Document results**

Record in the integration log or a commit message:
- Tarball size
- Export/import time
- Whether stacks came up cleanly on re-import
- Any issues encountered

**Gate:** Tarball is re-importable and stacks start without internet. This is Success Criterion #6.

---

## Summary: Success Criteria Traceability

| # | Criterion | Verified By |
|---|-----------|------------|
| 1 | Docker Desktop uninstalled; docker works from basalt-host + Windows interop | Task 16 |
| 2 | All six stacks start cleanly via CLAUDE.md startup sequence | Task 11 |
| 3 | Portainer reachable through Authentik; six stacks adopted | Task 14 |
| 4 | E2E smoke: browser → Authentik → Onyx → LiteLLM → vLLM (Gemma 4) → Langfuse trace | Task 11, Step 7 |
| 5 | vLLM cold start < 60s (ext4 proof) | Task 11, Step 8 |
| 6 | `wsl --export` produces re-importable tarball | Task 22 |
| 7 | LACI structural-alignment diff pass completed | Task 17 |
| 8 | Deployment guide + DB runbook documented | Tasks 19-20 |
| — | Auto-memory + §5f parking updated | Task 21 |
