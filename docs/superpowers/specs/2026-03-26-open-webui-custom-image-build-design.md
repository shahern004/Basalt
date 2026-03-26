# Open-WebUI Custom Image Build + LACI Directory Alignment

## Guiding Principle

**Maximum LACI alignment.** Basalt always attempts to align with LACI conventions so we are not beholden to their timeline and do not incur burden on their workflows to include our requirements. Our customizations layer on top of LACI's artifacts without modifying them.

## Problem

The 4 Authentik SSO patches (shared-secret validation, JWT expiry config, error messages) committed in `40bdf9b` exist only in the vendored `open-webui/` source tree. The deployment compose pulls the stock upstream image (`ghcr.io/open-webui/open-webui:main`), so **the security hardening is not deployed**. Anyone bypassing Authentik and hitting port 3002 directly skips the shared-secret validation.

Additionally, Basalt's directory structure diverges from LACI v1.1's layout, making it harder to absorb future upstream updates.

## Key Discovery: LACI Ships Custom Images

LACI v1.1 already rebuilds Open-WebUI and Onyx backend with their own modifications:

| Image | Source | Meaning |
|-------|--------|---------|
| `laci-docker/laci/open-webui:v0.8.10` | `laci-docker` | **Rebuilt by LACI team** |
| `laci-docker/laci/onyx/onyx-backend:v2.0.3` | `laci-docker` | **Rebuilt by LACI team** |
| `laci-docker-io/vllm/vllm-openai:v0.17.1` | `laci-docker-io` | Unmodified mirror of docker.io |
| `laci-ghcr-io/berriai/litellm-database:v1.82.0` | `laci-ghcr-io` | Unmodified mirror of ghcr.io |

Convention: `laci-<upstream>-io` = unmodified mirror. `laci-docker` = rebuilt with LACI changes.

## Approach

**Layer-on-LACI**: Use LACI's custom `laci/open-webui:v0.8.10` as the base image. Apply Basalt's Authentik SSO patches via a thin Dockerfile. Push to Forgejo container registry. `docker save` for air-gap transfer.

This differs from the original spec (which cloned upstream source). Layering on LACI's image preserves their modifications while adding ours.

## Part 1: Directory Restructure (LACI Alignment)

### Current vs Target Layout

```
CURRENT (basalt-stack/ wrapper)          TARGET (LACI-aligned)
─────────────────────────────            ─────────────────────────
basalt-stack/inference/vllm/       →     inference/vllm/
basalt-stack/inference/litellm/    →     inference/litellm/
basalt-stack/inference/langfuse/   →     inference/langfuse/
basalt-stack/web/authentik/        →     web/authentik/
basalt-stack/web/open-webui/       →     web/open-webui/
basalt-stack/web/portal-archived/  →     web/portal-archived/
onyx/deployment/docker_compose/    →     web/onyx/
onyx/ (2,622 vendored files)       →     REMOVED
open-webui/ (221 vendored files)   →     REMOVED
basalt-stack/tools/rmf-generator/  →     tools/rmf-generator/
```

### Target Repo Structure

```
basalt-stack-v1.0/                       # repo root
├── inference/                           # LACI-aligned
│   ├── vllm/
│   ├── litellm/
│   └── langfuse/
├── web/                                 # LACI-aligned
│   ├── authentik/
│   ├── open-webui/
│   ├── onyx/                            # moved from onyx/deployment/docker_compose/
│   └── portal-archived/
├── utils/                               # LACI-aligned (future: stage scripts)
├── builds/                              # Basalt-specific: custom image build tooling
│   └── open-webui/
│       ├── Dockerfile.basalt
│       ├── build.sh
│       ├── patches/
│       │   └── 001-authentik-sso.patch
│       └── README.md
├── tools/                               # Basalt-specific: RMF doc automation
│   └── rmf-generator/
├── rmf-plan-templates/                  # Basalt-specific: 20 NIST .docx templates
├── docs/                                # Basalt-specific: plans, solutions, brainstorms
├── todos/                               # Basalt-specific: issue tracking
├── CLAUDE.md
└── .gitignore
```

**Principle:** The LACI-aligned directories (`inference/`, `web/`, `utils/`) mirror the upstream tarball structure. Basalt-specific directories (`builds/`, `tools/`, `docs/`, `todos/`, `rmf-plan-templates/`) live as peers and never collide with LACI's tree.

### What Gets Removed

| Directory | Files | Size | Reason |
|-----------|-------|------|--------|
| `open-webui/` (root) | 221 | 7.5 MB | Vendored upstream source; patches preserved in `builds/open-webui/patches/` |
| `onyx/` (root) | 2,622 | 50 MB | Vendored upstream source; only deployment config needed (moves to `web/onyx/`) |
| `basalt-stack/` (wrapper) | 0 | 0 | Directory itself removed; contents move up one level |

**Net result:** ~2,900 tracked files / 85 MB → ~130 tracked files / ~13 MB.

## Part 2: Custom Image Build

### Dockerfile.basalt

A thin Dockerfile that layers Basalt patches onto LACI's image:

```dockerfile
ARG BASE_IMAGE=laci/open-webui:v0.8.10
FROM ${BASE_IMAGE}

# Apply Basalt Authentik SSO patches
COPY patches/ /tmp/patches/
RUN apt-get update && apt-get install -y --no-install-recommends patch \
    && cd /app \
    && for p in /tmp/patches/*.patch; do patch -p1 < "$p"; done \
    && apt-get purge -y patch && apt-get autoremove -y \
    && rm -rf /tmp/patches /var/lib/apt/lists/*
```

**Why this works:** LACI's image already has the built frontend and backend at `/app`. We only modify 4 Python files in-place. No rebuild of the frontend or pip install needed — the patches add new env var reads and a validation function, not new dependencies.

**Note:** The `patch` utility may need adjustment depending on the base image's package manager. If LACI's image is Alpine-based, use `apk add patch` instead.

### Build Script (`build.sh`)

#### Inputs

| Variable | Value | Purpose |
|----------|-------|---------|
| `BASE_IMAGE` | `laci/open-webui:v0.8.10` | LACI's custom image (from their registry or local `docker load`) |
| `REGISTRY` | `localhost:3205/isse` | Forgejo container registry |
| `IMAGE_NAME` | `open-webui` | Image name |
| `BASALT_TAG` | `v0.8.10-basalt` | Output tag (LACI version + `-basalt` suffix) |

#### Steps

1. Verify base image exists locally (either pulled or `docker load`ed from LACI tarball)
2. Run `docker build -f Dockerfile.basalt --build-arg BASE_IMAGE=$BASE_IMAGE -t $REGISTRY/$IMAGE_NAME:$BASALT_TAG .`
3. Push to Forgejo registry
4. Print image digest for verification

#### Tag format

`localhost:3205/isse/open-webui:v0.8.10-basalt`

- LACI version preserved for traceability
- `-basalt` suffix distinguishes from LACI's stock image

### Patches

#### Current patch: `001-authentik-sso.patch`

4 files, ~86 lines changed (against v0.1.113 — must be re-ported):

| File (v0.1.113 path) | Change |
|------|--------|
| `backend/config.py` | Adds `JWT_EXPIRES_IN` and `AUTHENTIK_SHARED_SECRET` env vars; removes hardcoded fallback secret |
| `backend/constants.py` | Adds `INVALID_AUTH_SOURCE` and `MISSING_IDENTITY_HEADER` error messages |
| `backend/apps/web/main.py` | Wires `JWT_EXPIRES_IN` from config instead of hardcoded `"-1"` |
| `backend/apps/web/routers/auths.py` | Adds `_validate_authentik_secret()` shared-secret validation on SSO signin |

#### Re-porting required

The patches were written against Open-WebUI v0.1.113. LACI's image is v0.8.10. Open-WebUI reorganized its codebase between these versions. The first build requires **re-porting the 4 patches to v0.8.10's file structure**. This is a one-time cost.

**Re-porting approach:** Pull LACI's `v0.8.10` image, `docker cp` the backend source out, locate the equivalent files/functions, rewrite the patch against the new paths.

#### Upgrade workflow (future LACI updates)

1. Receive new LACI tarball with updated `laci/open-webui:v<new>`
2. `docker load` the new image
3. Update `BASE_IMAGE` in `build.sh`
4. Run `build.sh` — if `patch` fails, re-port patches to the new structure
5. Commit updated patch, re-run `build.sh`

### Stage & Deploy

#### `stage-images.sh` (in `web/open-webui/`)

Same pattern as Authentik's `stage-images.sh` with four subcommands:

| Command | Where | What |
|---------|-------|------|
| `pull` | Dev machine | Pull from Forgejo registry (`localhost:3205/isse/open-webui:<tag>`) |
| `save` | Dev machine | Export to `.tar` in `./images/` |
| `load` | Air-gapped target | Import `.tar` into local Docker |
| `verify` | Both | Print image digests for comparison |

#### Deployment config change

`.env` updates from:
```
OPENWEBUI_IMAGE=ghcr.io/open-webui/open-webui:main
```
to:
```
OPENWEBUI_IMAGE=localhost:3205/isse/open-webui:v0.8.10-basalt
```

`docker-compose.yaml` is unchanged — it already uses `${OPENWEBUI_IMAGE}`.

## Prerequisites

### Docker Desktop: Insecure Registry

Forgejo runs HTTP, not HTTPS. One-time GUI change in Docker Desktop:

**Settings > Docker Engine** — update JSON config:

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

Apply & Restart. Not needed on air-gapped target (images arrive via `docker load`).

### Forgejo Authentication

`docker login localhost:3205` with Forgejo credentials before running `build.sh`. Use an access token rather than password for scriptability.

### LACI Base Image Available Locally

LACI's `laci/open-webui:v0.8.10` must be loaded into local Docker before building. Source: LACI's CHQ artifactory or the tarball they provide.

## Deferred: Roadmap Items (Separate Tasks)

### D2: Networking Model Alignment

Migrate from `host.docker.internal` (host-routed) to LACI's shared Docker network model (`proxy` and `inference` external networks). This touches every compose file and requires testing cross-stack communication.

### D4: Two-Part Image Reference Pattern

Adopt LACI's `${DOCKER_IMAGE_REPO}${IMAGE}` pattern across all compose files and `.env` files. Enables single-variable registry swapping between dev, Forgejo, and air-gap targets.

### Version Alignment

Align component versions with LACI v1.1 (vLLM v0.17.1, LiteLLM v1.82.0, Langfuse v3.155.1, Postgres 18.3, Redis 8.6.1). Each upgrade should be tested individually.
