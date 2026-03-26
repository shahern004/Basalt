# Open-WebUI Custom Build + LACI Directory Alignment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Basalt's Authentik SSO patches on a custom Open-WebUI image layered on LACI's v0.8.10 base, and restructure the repo to align with LACI v1.1's directory layout.

**Architecture:** Two-phase approach. Phase A restructures the repo from `basalt-stack/` nesting to LACI-aligned flat layout (`inference/`, `web/`, `tools/`), removes 2,820 vendored upstream files, and moves Onyx deployment config to `web/onyx/`. Phase B builds a custom Open-WebUI Docker image by layering Basalt's Authentik patches onto LACI's pre-built image, pushes to Forgejo registry, and updates deployment config.

**Tech Stack:** Docker, git, bash, patch utility, Forgejo container registry

**Spec:** `docs/superpowers/specs/2026-03-26-open-webui-custom-image-build-design.md`

---

## Phase A: LACI Directory Alignment

### Task A1: Move `basalt-stack/inference/` to `inference/`

**Files:**
- Move: `basalt-stack/inference/vllm/docker-compose.yaml` → `inference/vllm/docker-compose.yaml`
- Move: `basalt-stack/inference/litellm/docker-compose.yaml` → `inference/litellm/docker-compose.yaml`
- Move: `basalt-stack/inference/litellm/litellm-config.yaml` → `inference/litellm/litellm-config.yaml`
- Move: `basalt-stack/inference/langfuse/docker-compose.yaml` → `inference/langfuse/docker-compose.yaml`
- Move: `basalt-stack/inference/langfuse/clickhouse-users.xml` → `inference/langfuse/clickhouse-users.xml`

- [ ] **Step 1: Create target directories and move files**

```bash
cd /d/BASALT/Basalt-Architecture/basalt-stack-v1.0

mkdir -p inference/vllm inference/litellm inference/langfuse

git mv basalt-stack/inference/vllm/docker-compose.yaml inference/vllm/docker-compose.yaml
git mv basalt-stack/inference/litellm/docker-compose.yaml inference/litellm/docker-compose.yaml
git mv basalt-stack/inference/litellm/litellm-config.yaml inference/litellm/litellm-config.yaml
git mv basalt-stack/inference/langfuse/docker-compose.yaml inference/langfuse/docker-compose.yaml
git mv basalt-stack/inference/langfuse/clickhouse-users.xml inference/langfuse/clickhouse-users.xml
```

- [ ] **Step 2: Verify the .env files are gitignored and still present on disk**

`.env` files are gitignored and won't be tracked by `git mv`. They must be copied manually.

```bash
# Copy .env files (gitignored, not tracked)
cp basalt-stack/inference/vllm/.env inference/vllm/.env 2>/dev/null || echo "No vllm .env"
cp basalt-stack/inference/litellm/.env inference/litellm/.env 2>/dev/null || echo "No litellm .env"
cp basalt-stack/inference/langfuse/.env inference/langfuse/.env 2>/dev/null || echo "No langfuse .env"

# Verify
ls -la inference/vllm/.env inference/litellm/.env inference/langfuse/.env
```

- [ ] **Step 3: Verify compose files parse correctly at new paths**

```bash
docker compose -f inference/vllm/docker-compose.yaml config --quiet && echo "vllm: OK" || echo "vllm: FAIL"
docker compose -f inference/litellm/docker-compose.yaml config --quiet && echo "litellm: OK" || echo "litellm: FAIL"
docker compose -f inference/langfuse/docker-compose.yaml config --quiet && echo "langfuse: OK" || echo "langfuse: FAIL"
```

Expected: All three print OK. If any FAIL, check for relative path references in the compose files that broke during the move.

- [ ] **Step 4: Commit**

```bash
git add inference/
git commit -m "refactor: move basalt-stack/inference/ to inference/ (LACI alignment)"
```

---

### Task A2: Move `basalt-stack/web/` to `web/`

**Files:**
- Move: `basalt-stack/web/authentik/` → `web/authentik/` (all tracked files)
- Move: `basalt-stack/web/open-webui/` → `web/open-webui/` (all tracked files)
- Move: `basalt-stack/web/portal-archived/` → `web/portal-archived/` (all tracked files)

- [ ] **Step 1: Create target directories and move files**

```bash
cd /d/BASALT/Basalt-Architecture/basalt-stack-v1.0

mkdir -p web/authentik/blueprints/custom web/authentik/scripts web/authentik/db
mkdir -p web/open-webui
mkdir -p web/portal-archived/html web/portal-archived/nginx web/portal-archived/scripts

# Authentik
git mv basalt-stack/web/authentik/.env.example web/authentik/.env.example
git mv basalt-stack/web/authentik/.gitignore web/authentik/.gitignore
git mv basalt-stack/web/authentik/blueprints/custom/00-system-settings.yaml web/authentik/blueprints/custom/00-system-settings.yaml
git mv basalt-stack/web/authentik/db/include.yaml web/authentik/db/include.yaml
git mv basalt-stack/web/authentik/docker-compose.yaml web/authentik/docker-compose.yaml
git mv basalt-stack/web/authentik/hosts-template.txt web/authentik/hosts-template.txt
git mv basalt-stack/web/authentik/scripts/gen-cert.sh web/authentik/scripts/gen-cert.sh
git mv basalt-stack/web/authentik/scripts/stage-images.sh web/authentik/scripts/stage-images.sh

# Open-WebUI
git mv basalt-stack/web/open-webui/.env.example web/open-webui/.env.example
git mv basalt-stack/web/open-webui/docker-compose.yaml web/open-webui/docker-compose.yaml

# Portal (archived)
git mv basalt-stack/web/portal-archived/.env.example web/portal-archived/.env.example
git mv basalt-stack/web/portal-archived/.gitignore web/portal-archived/.gitignore
git mv basalt-stack/web/portal-archived/docker-compose.yaml web/portal-archived/docker-compose.yaml
git mv basalt-stack/web/portal-archived/html/index.html web/portal-archived/html/index.html
git mv basalt-stack/web/portal-archived/nginx/portal.conf web/portal-archived/nginx/portal.conf
git mv basalt-stack/web/portal-archived/scripts/gen-cert.sh web/portal-archived/scripts/gen-cert.sh
```

- [ ] **Step 2: Copy gitignored .env files**

```bash
cp basalt-stack/web/authentik/.env web/authentik/.env 2>/dev/null || echo "No authentik .env"
cp basalt-stack/web/open-webui/.env web/open-webui/.env 2>/dev/null || echo "No open-webui .env"

ls -la web/authentik/.env web/open-webui/.env
```

- [ ] **Step 3: Verify compose files parse at new paths**

```bash
docker compose -f web/authentik/docker-compose.yaml config --quiet && echo "authentik: OK" || echo "authentik: FAIL"
docker compose -f web/open-webui/docker-compose.yaml config --quiet && echo "open-webui: OK" || echo "open-webui: FAIL"
```

Expected: Both print OK.

- [ ] **Step 4: Commit**

```bash
git add web/
git commit -m "refactor: move basalt-stack/web/ to web/ (LACI alignment)"
```

---

### Task A3: Move `basalt-stack/tools/` to `tools/`

**Files:**
- Move: `basalt-stack/tools/rmf-generator/` → `tools/rmf-generator/` (all 11 tracked files)

- [ ] **Step 1: Move all rmf-generator files**

```bash
cd /d/BASALT/Basalt-Architecture/basalt-stack-v1.0

mkdir -p tools/rmf-generator/{data,generators,llm,loaders,models,templates}

git mv basalt-stack/tools/rmf-generator/data/nist-800-53-catalog.json tools/rmf-generator/data/nist-800-53-catalog.json
git mv basalt-stack/tools/rmf-generator/data/notional_system.yaml tools/rmf-generator/data/notional_system.yaml
git mv basalt-stack/tools/rmf-generator/fill_template.py tools/rmf-generator/fill_template.py
git mv basalt-stack/tools/rmf-generator/generators/__init__.py tools/rmf-generator/generators/__init__.py
git mv basalt-stack/tools/rmf-generator/llm/__init__.py tools/rmf-generator/llm/__init__.py
git mv basalt-stack/tools/rmf-generator/loaders/__init__.py tools/rmf-generator/loaders/__init__.py
git mv basalt-stack/tools/rmf-generator/models/__init__.py tools/rmf-generator/models/__init__.py
git mv basalt-stack/tools/rmf-generator/models/control.py tools/rmf-generator/models/control.py
git mv basalt-stack/tools/rmf-generator/models/system.py tools/rmf-generator/models/system.py
git mv basalt-stack/tools/rmf-generator/requirements.txt tools/rmf-generator/requirements.txt
git mv basalt-stack/tools/rmf-generator/retag_template.py tools/rmf-generator/retag_template.py
git mv basalt-stack/tools/rmf-generator/templates/MP.docx tools/rmf-generator/templates/MP.docx
```

- [ ] **Step 2: Verify Python imports work from new path**

```bash
cd tools/rmf-generator && python -c "from models.control import *; print('imports OK')" && cd -
```

Expected: `imports OK`

- [ ] **Step 3: Commit**

```bash
git add tools/
git commit -m "refactor: move basalt-stack/tools/ to tools/ (LACI alignment)"
```

---

### Task A4: Move Onyx deployment to `web/onyx/` and create `utils/`

**Files:**
- Move: `onyx/deployment/docker_compose/docker-compose.yml` → `web/onyx/docker-compose.yaml`
- Move: `onyx/deployment/docker_compose/.env` → `web/onyx/.env` (gitignored, manual copy)
- Move: `onyx/deployment/docker_compose/env.template` → `web/onyx/.env.example`
- Move: `onyx/deployment/docker_compose/custom_cert_oauth_client.patch` → `web/onyx/custom_cert_oauth_client.patch`
- Move: `onyx/deployment/docker_compose/custom_cert_oauth.py` → `web/onyx/custom_cert_oauth.py`
- Move: `onyx/CLAUDE.md` → `web/onyx/CLAUDE.md`
- Create: `utils/.gitkeep` (placeholder for future LACI-aligned utils)

Note: The remaining Onyx files (backend source, frontend, helm, terraform, CI workflows — 2,599 files) are not moved. They are removed in Task A5.

- [ ] **Step 1: Create target directory and move deployment files**

```bash
cd /d/BASALT/Basalt-Architecture/basalt-stack-v1.0

mkdir -p web/onyx

# Tracked files we want to keep
git mv onyx/CLAUDE.md web/onyx/CLAUDE.md
git mv onyx/deployment/docker_compose/docker-compose.yml web/onyx/docker-compose.yaml
git mv onyx/deployment/docker_compose/env.template web/onyx/.env.example
git mv onyx/deployment/docker_compose/custom_cert_oauth_client.patch web/onyx/custom_cert_oauth_client.patch
git mv onyx/deployment/docker_compose/custom_cert_oauth.py web/onyx/custom_cert_oauth.py
```

- [ ] **Step 2: Copy gitignored .env**

```bash
cp onyx/deployment/docker_compose/.env web/onyx/.env 2>/dev/null || echo "No onyx .env"
ls -la web/onyx/.env
```

- [ ] **Step 3: Create utils/ directory**

```bash
mkdir -p utils
touch utils/.gitkeep
git add utils/.gitkeep
```

- [ ] **Step 4: Commit the moves (before removal, to preserve git history)**

```bash
git add web/onyx/
git commit -m "refactor: move onyx deployment config to web/onyx/ (LACI alignment)"
```

---

### Task A5: Remove vendored upstream trees and empty `basalt-stack/` wrapper

**Files:**
- Remove: `open-webui/` (221 tracked files, 7.5 MB)
- Remove: `onyx/` (remaining 2,599+ tracked files, ~50 MB)
- Remove: `basalt-stack/` (now empty after Tasks A1-A3)

- [ ] **Step 1: Extract the Authentik SSO patch before removing vendored source**

This preserves the 4 patched files as a `.patch` for Phase B.

```bash
cd /d/BASALT/Basalt-Architecture/basalt-stack-v1.0

mkdir -p builds/open-webui/patches

# Generate patch from git history, stripping the open-webui/ prefix
git diff b0e5bf8..HEAD -- open-webui/backend/ | sed 's|a/open-webui/|a/|g; s|b/open-webui/|b/|g' > builds/open-webui/patches/001-authentik-sso-v0.1.113.patch

# Verify patch content
echo "=== Patch stats ==="
head -5 builds/open-webui/patches/001-authentik-sso-v0.1.113.patch
echo "..."
grep "^diff --git" builds/open-webui/patches/001-authentik-sso-v0.1.113.patch
```

Expected: 4 `diff --git` entries for `backend/config.py`, `backend/constants.py`, `backend/apps/web/main.py`, `backend/apps/web/routers/auths.py`.

- [ ] **Step 2: Remove vendored open-webui/**

```bash
git rm -r open-webui/
```

Expected: `rm 'open-webui/...'` for 221 files.

- [ ] **Step 3: Remove remaining vendored onyx/ tree**

```bash
git rm -r onyx/
```

Expected: `rm 'onyx/...'` for remaining tracked files (deployment files already moved in A4).

- [ ] **Step 4: Remove now-empty basalt-stack/ directory**

After Tasks A1-A3, `basalt-stack/` should be empty of tracked files. Verify and clean up:

```bash
# Check for any remaining tracked files
git ls-files basalt-stack/
# Should output nothing. If anything remains, git mv it to the correct location.

# Remove the directory if empty
rmdir basalt-stack 2>/dev/null || echo "basalt-stack/ has untracked files — check manually"
```

- [ ] **Step 5: Commit the removals**

```bash
git add builds/open-webui/patches/
git commit -m "refactor: remove vendored open-webui/ and onyx/ trees, extract SSO patch

Removes 2,820 vendored upstream files (~57 MB). Onyx deployment
config preserved in web/onyx/ (Task A4). Open-WebUI SSO patches
preserved in builds/open-webui/patches/ for Phase B custom build.
"
```

---

### Task A6: Update CLAUDE.md and .gitignore for new paths

**Files:**
- Modify: `CLAUDE.md` — update all `basalt-stack/` paths, service port table, startup/shutdown sequences, env file references, gotchas
- Modify: `.gitignore` — update `basalt-stack/` specific rules

- [ ] **Step 1: Update .gitignore**

Replace `basalt-stack/` references with new paths:

Old:
```
basalt-stack/web/portal/certs/
basalt-stack/tools/rmf-generator/output/
```

New:
```
web/portal-archived/certs/
tools/rmf-generator/output/
```

- [ ] **Step 2: Update CLAUDE.md**

All path references must change. Key substitutions (apply throughout):

| Old path | New path |
|----------|----------|
| `basalt-stack/inference/vllm/` | `inference/vllm/` |
| `basalt-stack/inference/litellm/` | `inference/litellm/` |
| `basalt-stack/inference/langfuse/` | `inference/langfuse/` |
| `basalt-stack/web/authentik/` | `web/authentik/` |
| `basalt-stack/web/open-webui/` | `web/open-webui/` |
| `basalt-stack/tools/rmf-generator/` | `tools/rmf-generator/` |
| `onyx/deployment/docker_compose/` | `web/onyx/` |

Update the **Overview** section directory listing:
```
- **inference/** — vLLM, LiteLLM, Langfuse compose stacks
- **web/** — Authentik SSO, Open-WebUI, Onyx deployment configs
- **tools/rmf-generator/** — RMF document automation (docxtpl + vLLM structured output)
- **builds/** — Custom image build tooling (Basalt patches on LACI base images)
```

Update the **Architecture** service port table to use new paths.

Update the **Startup Sequence** — replace `basalt-stack/inference/vllm` with `inference/vllm`, etc.

Update the **Shutdown Sequence** similarly.

Update the **Commands Quick Reference** — `cd basalt-stack/tools/rmf-generator` → `cd tools/rmf-generator`.

Update the **Environment Configuration** section — all `.env` paths.

Update the **Gotchas** — any `basalt-stack/` references.

- [ ] **Step 3: Update onyx/CLAUDE.md reference**

The Onyx CLAUDE.md moved to `web/onyx/CLAUDE.md`. Update the root CLAUDE.md Overview reference:
```
- **web/onyx/** — Onyx AI platform deployment (see `web/onyx/CLAUDE.md` for deploy-only reference)
```

- [ ] **Step 4: Verify no stale basalt-stack/ references remain**

```bash
grep -r "basalt-stack/" CLAUDE.md .gitignore
```

Expected: No output.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md .gitignore
git commit -m "docs: update all paths in CLAUDE.md and .gitignore for LACI-aligned layout"
```

---

### Task A7: Update development roadmap for deferred items

**Files:**
- Modify: `docs/plans/basalt-development-roadmap.md` — add D2 (networking), D4 (image refs), version alignment as roadmap items

- [ ] **Step 1: Read the current roadmap**

```bash
cat docs/plans/basalt-development-roadmap.md
```

Identify the appropriate section to add new items (likely the hardening/Phase 7 section or a new LACI alignment section).

- [ ] **Step 2: Add deferred LACI alignment items**

Add a new section or append to existing roadmap:

```markdown
### LACI v1.1 Alignment (Deferred)

- [ ] **D2: Networking model migration** — Migrate from `host.docker.internal` (host-routed) to LACI's shared Docker network model (`proxy` and `inference` external networks). Touches every compose file. Requires: `docker network create proxy inference`, update all compose files to join external networks, remove `extra_hosts` entries, test cross-stack communication.
- [ ] **D4: Two-part image reference pattern** — Adopt LACI's `${DOCKER_IMAGE_REPO}${IMAGE}` pattern across all `.env` and compose files. Enables single-variable registry swapping between dev, Forgejo, and air-gap.
- [ ] **Version alignment** — Upgrade to LACI v1.1 component versions: vLLM v0.17.1, LiteLLM v1.82.0, Langfuse v3.155.1, Postgres 18.3-alpine, Redis 8.6.1-trixie. Test each upgrade individually.
```

- [ ] **Step 3: Commit**

```bash
git add docs/plans/basalt-development-roadmap.md
git commit -m "docs: add deferred LACI alignment items (D2, D4, versions) to roadmap"
```

---

## Phase B: Open-WebUI Custom Image Build

### Task B1: Docker Desktop prerequisite — insecure registry

This is a **manual GUI step**, not a script.

- [ ] **Step 1: Add insecure registry in Docker Desktop**

Open Docker Desktop → Settings → Docker Engine. Replace the JSON config with:

```json
{
  "builder": {
    "gc": {
      "defaultKeepStorage": "20GB",
      "enabled": true
    }
  },
  "experimental": false,
  "insecure-registries": ["localhost:3205"]
}
```

Click **Apply & Restart**. Wait for Docker to restart.

- [ ] **Step 2: Verify Docker can reach Forgejo registry**

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3205/v2/
```

Expected: `401` (authentication required, but registry is reachable).

- [ ] **Step 3: Log in to Forgejo registry**

```bash
docker login localhost:3205
```

Enter your Forgejo username and password (or access token). Expected: `Login Succeeded`.

---

### Task B2: Load LACI base image and explore v0.8.10 file structure

**Files:**
- None created yet — this is research to inform patch re-porting in B3

- [ ] **Step 1: Acquire LACI's Open-WebUI image**

The image `laci/open-webui:v0.8.10` must be available locally. Check if it's in the LACI update package or needs to be pulled from their CHQ registry:

```bash
# Check if the image is already loaded
docker images | grep open-webui

# If not available, check if there's a .tar in the LACI package
find /d/BASALT/Basalt-Architecture/laci-24mar -name "*.tar" -o -name "*.tar.gz" | grep -i webui
```

If the image is not available locally, it must be pulled from LACI's CHQ artifactory (`lnsvr0310.gcsd.harris.com:8443/lacichq-docker/laci/open-webui:v0.8.10`) or requested from the LACI team. **Stop here and ask the user if the image is not available.**

- [ ] **Step 2: Explore the v0.8.10 backend file structure**

```bash
# Create a temp container and copy backend source out
docker create --name owui-inspect laci/open-webui:v0.8.10
docker cp owui-inspect:/app/backend /tmp/owui-backend-v0.8.10
docker rm owui-inspect

# Find the equivalent files for our patches
echo "=== Looking for config.py equivalent ==="
find /tmp/owui-backend-v0.8.10 -name "config.py" -path "*/config*"

echo "=== Looking for constants.py equivalent ==="
find /tmp/owui-backend-v0.8.10 -name "constants.py"

echo "=== Looking for auths.py equivalent ==="
find /tmp/owui-backend-v0.8.10 -name "auths.py" -path "*/routers/*"

echo "=== Looking for main.py in web app ==="
find /tmp/owui-backend-v0.8.10 -name "main.py" -path "*/web/*"
```

- [ ] **Step 3: Identify the exact functions/variables to patch**

For each of the 4 original patch targets, find the equivalent in v0.8.10:

1. **JWT_EXPIRES_IN config** — search for `JWT_EXPIRES_IN` or `jwt.*expir`:
   ```bash
   grep -rn "JWT_EXPIRES_IN\|jwt.*expir\|app.state.JWT" /tmp/owui-backend-v0.8.10/ | head -20
   ```

2. **WEBUI_SECRET_KEY fallback** — search for the hardcoded `t0p-s3cr3t`:
   ```bash
   grep -rn "t0p-s3cr3t\|WEBUI_SECRET_KEY\|WEBUI_JWT_SECRET" /tmp/owui-backend-v0.8.10/ | head -20
   ```

3. **Shared secret validation** — search for auth signin routes:
   ```bash
   grep -rn "def signin\|def sign_in\|/signin\|/api/v1/auths" /tmp/owui-backend-v0.8.10/ | head -20
   ```

4. **Error messages** — search for existing error constants:
   ```bash
   grep -rn "class ERROR_MESSAGES\|UNAUTHORIZED\|INVALID_PASSWORD" /tmp/owui-backend-v0.8.10/ | head -10
   ```

Document the new file paths and line numbers. These inform the patch in B3.

- [ ] **Step 4: Check base image's package manager**

```bash
docker run --rm laci/open-webui:v0.8.10 cat /etc/os-release | head -5
```

If `ID=alpine`, the Dockerfile uses `apk add patch`. If `ID=debian` or `ID=ubuntu`, use `apt-get install patch`. Record this for Task B3.

- [ ] **Step 5: Clean up**

```bash
rm -rf /tmp/owui-backend-v0.8.10
```

No commit — this is a research task.

---

### Task B3: Create the re-ported patch and Dockerfile.basalt

**Files:**
- Create: `builds/open-webui/patches/001-authentik-sso.patch` — re-ported to v0.8.10 paths
- Create: `builds/open-webui/Dockerfile.basalt`
- Create: `builds/open-webui/README.md`

- [ ] **Step 1: Write the re-ported patch**

Using the file paths discovered in B2, create the new patch. The patch must implement the same 4 changes against the v0.8.10 file structure:

1. Add `JWT_EXPIRES_IN` and `AUTHENTIK_SHARED_SECRET` env var reads to the config module
2. Add `INVALID_AUTH_SOURCE` and `MISSING_IDENTITY_HEADER` error constants
3. Wire `JWT_EXPIRES_IN` from config into the app state (replace hardcoded `"-1"`)
4. Add `_validate_authentik_secret()` function to the auth signin route

Write the patch to `builds/open-webui/patches/001-authentik-sso.patch`.

The exact content depends on B2's findings. The v0.1.113 patch in `builds/open-webui/patches/001-authentik-sso-v0.1.113.patch` (created in A5) serves as the reference for the logic. The file paths and surrounding context will differ.

- [ ] **Step 2: Write Dockerfile.basalt**

Create `builds/open-webui/Dockerfile.basalt`:

If base image is **Debian/Ubuntu-based**:
```dockerfile
ARG BASE_IMAGE=laci/open-webui:v0.8.10
FROM ${BASE_IMAGE}

COPY patches/ /tmp/patches/
RUN apt-get update \
    && apt-get install -y --no-install-recommends patch \
    && cd /app \
    && for p in /tmp/patches/*.patch; do patch -p1 < "$p"; done \
    && apt-get purge -y patch \
    && apt-get autoremove -y \
    && rm -rf /tmp/patches /var/lib/apt/lists/*
```

If base image is **Alpine-based**:
```dockerfile
ARG BASE_IMAGE=laci/open-webui:v0.8.10
FROM ${BASE_IMAGE}

COPY patches/ /tmp/patches/
RUN apk add --no-cache patch \
    && cd /app \
    && for p in /tmp/patches/*.patch; do patch -p1 < "$p"; done \
    && apk del patch \
    && rm -rf /tmp/patches
```

- [ ] **Step 3: Write README.md**

Create `builds/open-webui/README.md`:

```markdown
# Open-WebUI Custom Build (Basalt)

Layers Basalt's Authentik SSO patches onto LACI's pre-built Open-WebUI image.

## Patches

| Patch | Base Version | What it does |
|-------|-------------|-------------|
| 001-authentik-sso.patch | v0.8.10 | Adds shared-secret validation, JWT expiry config, error messages for Authentik SSO |

## Build

```bash
./build.sh
```

## Upgrade

1. Load new LACI base image (`docker load < laci-open-webui-vX.Y.Z.tar`)
2. Update `BASE_IMAGE` in `build.sh`
3. Run `./build.sh` — if patch fails, re-port the patch to the new file structure
4. Commit updated patch
```

- [ ] **Step 4: Commit**

```bash
git add builds/open-webui/
git commit -m "feat: add Dockerfile.basalt, re-ported SSO patch, and README for custom Open-WebUI build"
```

---

### Task B4: Create build.sh and stage-images.sh

**Files:**
- Create: `builds/open-webui/build.sh`
- Create: `web/open-webui/stage-images.sh`

- [ ] **Step 1: Write build.sh**

Create `builds/open-webui/build.sh`:

```bash
#!/usr/bin/env bash
# build.sh — Build Basalt's custom Open-WebUI image layered on LACI's base
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Configuration ---
BASE_IMAGE="${BASE_IMAGE:-laci/open-webui:v0.8.10}"
REGISTRY="${REGISTRY:-localhost:3205/isse}"
IMAGE_NAME="open-webui"
# Tag format: LACI version + -basalt suffix
BASALT_TAG="${BASALT_TAG:-v0.8.10-basalt}"

FULL_TAG="${REGISTRY}/${IMAGE_NAME}:${BASALT_TAG}"

echo "Building ${FULL_TAG}"
echo "  Base: ${BASE_IMAGE}"
echo ""

# Verify base image exists
if ! docker image inspect "${BASE_IMAGE}" >/dev/null 2>&1; then
  echo "ERROR: Base image ${BASE_IMAGE} not found locally."
  echo "Load it with: docker load < <laci-image>.tar"
  exit 1
fi

# Build
docker build \
  -f "${SCRIPT_DIR}/Dockerfile.basalt" \
  --build-arg BASE_IMAGE="${BASE_IMAGE}" \
  -t "${FULL_TAG}" \
  "${SCRIPT_DIR}"

echo ""
echo "Built: ${FULL_TAG}"

# Push to Forgejo registry
echo "Pushing to ${REGISTRY}..."
docker push "${FULL_TAG}"

echo ""
echo "Done. Image digest:"
docker image inspect --format '{{.Id}}' "${FULL_TAG}"
echo ""
echo "To stage for air-gap transfer, run:"
echo "  cd ../../web/open-webui && ./stage-images.sh save"
```

```bash
chmod +x builds/open-webui/build.sh
```

- [ ] **Step 2: Write stage-images.sh**

Create `web/open-webui/stage-images.sh`:

```bash
#!/usr/bin/env bash
# stage-images.sh — Save/load custom Open-WebUI image for air-gap transfer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_DIR="${SCRIPT_DIR}/images"

# Image to stage — update when build.sh produces a new version
OPENWEBUI_IMAGE="localhost:3205/isse/open-webui:v0.8.10-basalt"

tar_name() {
  echo "$1" | sed 's|[/:]|_|g'
}

cmd_pull() {
  echo "Pulling image from Forgejo registry..."
  docker pull "${OPENWEBUI_IMAGE}"
  echo "Done. Run '$0 verify' to record digest, then '$0 save' to export."
}

cmd_save() {
  mkdir -p "${IMAGE_DIR}"
  local tarfile="${IMAGE_DIR}/$(tar_name "${OPENWEBUI_IMAGE}").tar"
  echo "Saving ${OPENWEBUI_IMAGE} → $(basename "${tarfile}")"
  docker save -o "${tarfile}" "${OPENWEBUI_IMAGE}"
  echo ""
  echo "Transfer ${IMAGE_DIR}/ to the air-gapped host."
  echo "Then run '$0 load' on the target."
}

cmd_load() {
  if [ ! -d "${IMAGE_DIR}" ]; then
    echo "ERROR: ${IMAGE_DIR} not found. Copy the images/ directory from the staging machine first."
    exit 1
  fi
  echo "Loading images from ${IMAGE_DIR}..."
  for tarfile in "${IMAGE_DIR}"/*.tar; do
    echo "  $(basename "${tarfile}")"
    docker load -i "${tarfile}"
  done
  echo "Done. Run '$0 verify' to confirm digest matches."
}

cmd_verify() {
  echo "Image digest (compare before and after transfer):"
  echo "---------------------------------------------------"
  local digest
  digest=$(docker image inspect --format '{{.Id}}' "${OPENWEBUI_IMAGE}" 2>/dev/null || echo "NOT FOUND")
  printf "  %-55s %s\n" "${OPENWEBUI_IMAGE}" "${digest}"
}

case "${1:-help}" in
  pull)   cmd_pull   ;;
  save)   cmd_save   ;;
  load)   cmd_load   ;;
  verify) cmd_verify ;;
  *)
    echo "Usage: $0 {pull|save|load|verify}"
    echo ""
    echo "  pull    Pull image from Forgejo registry (dev machine)"
    echo "  save    Export image to .tar file in ./images/"
    echo "  load    Import .tar file into Docker (air-gapped target)"
    echo "  verify  Print image digest for comparison"
    exit 1
    ;;
esac
```

```bash
chmod +x web/open-webui/stage-images.sh
```

- [ ] **Step 3: Commit**

```bash
git add builds/open-webui/build.sh web/open-webui/stage-images.sh
git commit -m "feat: add build.sh and stage-images.sh for custom Open-WebUI image pipeline"
```

---

### Task B5: Build the custom image and verify patches

- [ ] **Step 1: Run the build**

```bash
cd /d/BASALT/Basalt-Architecture/basalt-stack-v1.0
./builds/open-webui/build.sh
```

Expected output:
```
Building localhost:3205/isse/open-webui:v0.8.10-basalt
  Base: laci/open-webui:v0.8.10

...
Built: localhost:3205/isse/open-webui:v0.8.10-basalt
Pushing to localhost:3205/isse...
...
Done. Image digest:
sha256:...
```

If `patch` fails, the Dockerfile build will exit with an error showing which hunk failed. Go back to B3 Step 1 and fix the patch.

- [ ] **Step 2: Verify patches are applied inside the image**

```bash
# Check that our changes are present in the built image
docker run --rm localhost:3205/isse/open-webui:v0.8.10-basalt \
  grep -l "AUTHENTIK_SHARED_SECRET" /app/backend/**/*.py 2>/dev/null || \
  grep -rl "AUTHENTIK_SHARED_SECRET" /app/backend/
```

Expected: At least 2 files containing `AUTHENTIK_SHARED_SECRET` (config module + auth router).

```bash
docker run --rm localhost:3205/isse/open-webui:v0.8.10-basalt \
  grep -l "INVALID_AUTH_SOURCE" /app/backend/**/*.py 2>/dev/null || \
  grep -rl "INVALID_AUTH_SOURCE" /app/backend/
```

Expected: At least 1 file containing the error constant.

- [ ] **Step 3: Verify image is in Forgejo registry**

```bash
curl -s -u "<forgejo-user>:<forgejo-token>" http://localhost:3205/v2/isse/open-webui/tags/list
```

Expected: JSON containing `v0.8.10-basalt` in the tags list.

No commit — this is a verification task.

---

### Task B6: Update deployment config to use custom image

**Files:**
- Modify: `web/open-webui/.env` — update `OPENWEBUI_IMAGE`
- Modify: `web/open-webui/.env.example` — update example image reference

- [ ] **Step 1: Update .env**

In `web/open-webui/.env`, change:

Old:
```
OPENWEBUI_IMAGE=ghcr.io/open-webui/open-webui:main
```

New:
```
OPENWEBUI_IMAGE=localhost:3205/isse/open-webui:v0.8.10-basalt
```

Note: `.env` is gitignored, so this is a manual edit only.

- [ ] **Step 2: Update .env.example**

In `web/open-webui/.env.example`, update the image reference to reflect the new convention:

Old:
```
OPENWEBUI_IMAGE="{INSERT PUBLIC IMAGE HERE}"
```

New:
```
OPENWEBUI_IMAGE="localhost:3205/isse/open-webui:v0.8.10-basalt"
```

- [ ] **Step 3: Smoke test — bring up Open-WebUI with the custom image**

```bash
cd /d/BASALT/Basalt-Architecture/basalt-stack-v1.0/web/open-webui
docker compose up -d
docker compose logs -f --tail=20
```

Expected: Open-WebUI starts without errors. Check for `Uvicorn running on` or equivalent startup message. Ctrl+C to exit logs.

- [ ] **Step 4: Verify SSO patch is active at runtime**

Browse to `http://localhost:3002` (or wherever Open-WebUI is exposed). The auth behavior should reflect the patched code. If Authentik is not running, verify by checking the container's environment:

```bash
docker compose exec open-webui env | grep AUTHENTIK
```

Expected: `AUTHENTIK_SHARED_SECRET=<value from .env>`

- [ ] **Step 5: Commit .env.example update**

```bash
git add web/open-webui/.env.example
git commit -m "feat: update Open-WebUI .env.example to reference custom Basalt image"
```

- [ ] **Step 6: Tear down**

```bash
cd /d/BASALT/Basalt-Architecture/basalt-stack-v1.0/web/open-webui
docker compose down
```
