# Open-WebUI Custom Image Build

## Problem

The 4 Authentik SSO patches (shared-secret validation, JWT expiry config, error messages) committed in `40bdf9b` exist only in the vendored `open-webui/` source tree. The deployment compose pulls the stock upstream image (`ghcr.io/open-webui/open-webui:main`), so **the security hardening is not deployed**. Anyone bypassing Authentik and hitting port 3002 directly skips the shared-secret validation.

## Approach

**Patch-on-Build**: Clone upstream Open-WebUI at a pinned tag, apply `.patch` files, build using upstream's Dockerfile, push to Forgejo container registry, `docker save` for air-gap transfer.

## File Layout

```
basalt-stack/
├── builds/
│   └── open-webui/
│       ├── build.sh                     # clone -> patch -> build -> tag -> push
│       ├── patches/
│       │   └── 001-authentik-sso.patch  # extracted + re-ported to current upstream
│       └── README.md                    # documents patches, upstream version, build steps
└── web/
    └── open-webui/
        ├── docker-compose.yaml          # deployment config (references built image)
        ├── .env                         # image tag, secrets, runtime config
        ├── .env.example                 # template
        └── stage-images.sh             # save/load built image for air-gap transfer
```

**Separation of concerns:**
- `builds/` = how to produce the image (build tooling, patches)
- `web/` = how to run the image (compose, env, staging)

## Build Script (`build.sh`)

### Inputs (configurable at top of script)

| Variable | Value | Purpose |
|----------|-------|---------|
| `UPSTREAM_REPO` | `https://github.com/open-webui/open-webui.git` | Source repo |
| `UPSTREAM_TAG` | Pinned to a specific release tag | Version to build against |
| `REGISTRY` | `localhost:3205/isse` | Forgejo container registry |
| `IMAGE_NAME` | `open-webui` | Image name |

### Steps

1. Clone upstream at the pinned tag into a temp directory
2. Copy `patches/*.patch` in and run `git apply` for each (numbered order)
3. Build using upstream's own Dockerfile (no custom Dockerfile)
4. Tag as `$REGISTRY/$IMAGE_NAME:$UPSTREAM_TAG-basalt`
5. Push to Forgejo registry
6. Clean up temp directory

### Tag format

`localhost:3205/isse/open-webui:v<version>-basalt`

- Upstream version preserved for traceability
- `-basalt` suffix distinguishes from stock upstream

### What it does NOT do

- No `docker save` (that's `stage-images.sh`'s job)
- No version auto-detection (explicit pin, manual update)

## Patches

### Current patch: `001-authentik-sso.patch`

4 files, ~86 lines changed:

| File | Change |
|------|--------|
| `backend/config.py` | Adds `JWT_EXPIRES_IN` and `AUTHENTIK_SHARED_SECRET` env vars; removes hardcoded fallback secret |
| `backend/constants.py` | Adds `INVALID_AUTH_SOURCE` and `MISSING_IDENTITY_HEADER` error messages |
| `backend/apps/web/main.py` | Wires `JWT_EXPIRES_IN` from config instead of hardcoded `"-1"` |
| `backend/apps/web/routers/auths.py` | Adds `_validate_authentik_secret()` shared-secret validation on SSO signin |

### Re-porting required

The patches were written against Open-WebUI v0.1.113 (Jan 2026). Open-WebUI has reorganized its codebase since then. The first build requires **re-porting the patches** to the current upstream file structure. This is a one-time cost; subsequent upgrades within the same structure will apply cleanly.

### Upgrade workflow

1. Update `UPSTREAM_TAG` in `build.sh`
2. Run `build.sh` -- if `git apply` fails, the script stops with a clear error
3. Manually resolve conflicts, regenerate the patch file
4. Commit the updated patch
5. Re-run `build.sh`

## Stage & Deploy

### `stage-images.sh` (in `basalt-stack/web/open-webui/`)

Same pattern as Authentik's `stage-images.sh` with four subcommands:

| Command | Where | What |
|---------|-------|------|
| `pull` | Dev machine | Pull from Forgejo registry (`localhost:3205/isse/open-webui:<tag>`) |
| `save` | Dev machine | Export to `.tar` in `./images/` |
| `load` | Air-gapped target | Import `.tar` into local Docker |
| `verify` | Both | Print image digests for comparison |

### Deployment config change

`.env` updates from:
```
OPENWEBUI_IMAGE=ghcr.io/open-webui/open-webui:main
```
to:
```
OPENWEBUI_IMAGE=localhost:3205/isse/open-webui:v<version>-basalt
```

`docker-compose.yaml` is unchanged -- it already uses `${OPENWEBUI_IMAGE}`.

### Air-gapped target workflow

1. Transfer `images/` directory to target
2. `stage-images.sh load`
3. `.env` points to the loaded image tag
4. `docker compose up -d`

## Prerequisites

### Docker Desktop: Insecure Registry

Forgejo runs HTTP, not HTTPS. One-time GUI change in Docker Desktop:

**Settings > Docker Engine** -- update JSON config:

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

## Follow-up: Repo Cleanup

After the custom image is built and verified, the vendored `open-webui/` root directory (221 files, 7.5 MB) can be removed. The patches preserve all local modifications. This is a separate task, not part of the build work.
