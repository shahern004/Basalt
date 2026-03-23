---
title: "Basalt Stack — Software Bill of Materials (SBOM)"
date: 2026-03-13
status: active
category: reference
tags:
  - sbom
  - compliance
  - air-gap
  - inventory
aliases:
  - SBOM
  - basalt-sbom
related:
  - "[[basalt-system-design|system-design]]"
  - "[[basalt-development-roadmap|roadmap]]"
  - "[[deployment-guide-dev|deployment-guide]]"
---

# Basalt Stack — Software Bill of Materials (SBOM)

## SBOM Metadata (NTIA Minimum Elements)

| Field                    | Value                                                        |
| ------------------------ | ------------------------------------------------------------ |
| **SBOM Author**          | Basalt Stack Development Team                                |
| **Timestamp**            | 2026-03-19T00:00:00Z                                         |
| **SBOM Format**          | Markdown (human-readable)                                    |
| **SBOM Scope**           | Container images, application dependencies                   |
| **Applicable Standards** | NIST SP 800-218 (SSDF), EO 14028, NTIA SBOM Minimum Elements |
| **Repository**           | basalt-stack-v1.0 (multi-project, air-gapped deployment)     |
| **Target Environment**   | Windows 11 + WSL2, NVIDIA RTX A6000, fully air-gapped        |

> **Air-Gap Declaration:** All components listed below are pre-staged before deployment. No runtime downloads, CDN fetches, or telemetry transmissions occur. See [Telemetry Suppression](#telemetry-suppression) for enforced settings.

---

## 1. Container Images

All images are pulled on an internet-connected machine, exported via `docker save`, and loaded on the air-gapped target via `docker load`.

### 1.1 Inference Tier

| Component | Image | Version | Supplier | Compose Location | Purpose |
|-----------|-------|---------|----------|-----------------|---------|
| vLLM | `vllm/vllm-openai` | `v0.10.2` | vLLM Project | `basalt-stack/inference/vllm/` | LLM inference engine (MoE + MXFP4) |
| LiteLLM | `ghcr.io/berriai/litellm-database` | `main-v1.41.14` | BerriAI | `basalt-stack/inference/litellm/` | LLM gateway / routing / caching |
| LiteLLM Postgres | `postgres` | `15.2-alpine` | PostgreSQL Global Dev Group | `basalt-stack/inference/litellm/` | LiteLLM metadata store |
| LiteLLM Redis | `redis` | `alpine` | Redis Ltd | `basalt-stack/inference/litellm/` | LiteLLM cache backend |
| Langfuse Web | `langfuse/langfuse` | `3.40.0` | Langfuse GmbH | `basalt-stack/inference/langfuse/` | Observability UI |
| Langfuse Worker | `langfuse/langfuse-worker` | `3.40.0` | Langfuse GmbH | `basalt-stack/inference/langfuse/` | Background trace processing |
| Langfuse Postgres | `postgres` | `15.2-alpine` | PostgreSQL Global Dev Group | `basalt-stack/inference/langfuse/` | Langfuse metadata store |
| Langfuse Redis | `redis` | `alpine` | Redis Ltd | `basalt-stack/inference/langfuse/` | Langfuse cache |
| Langfuse ClickHouse | `clickhouse/clickhouse-server` | `25.2.1.3085-alpine` | ClickHouse Inc | `basalt-stack/inference/langfuse/` | Analytics / OLAP backend |
| Langfuse MinIO | `minio/minio` | `RELEASE.2025-02-28T09-55-16Z` | MinIO Inc | `basalt-stack/inference/langfuse/` | S3-compatible object storage |

### 1.2 Web / Auth Tier

| Component | Image | Version | Supplier | Compose Location | Purpose |
|-----------|-------|---------|----------|-----------------|---------|
| Authentik Server | `ghcr.io/goauthentik/server` | `2026.2.1` | Authentik Security Inc | `basalt-stack/web/authentik/` | SSO / OIDC provider + embedded outpost |
| Authentik Worker | `ghcr.io/goauthentik/server` | `2026.2.1` | Authentik Security Inc | `basalt-stack/web/authentik/` | Background task worker |
| Authentik Postgres | `postgres` | `16-alpine` | PostgreSQL Global Dev Group | `basalt-stack/web/authentik/` | Authentik metadata store |
| Authentik Redis | `redis` | `7.4-alpine` | Redis Ltd | `basalt-stack/web/authentik/` | Session store / cache |
| Open-WebUI | `ghcr.io/open-webui/open-webui` | `main` | Open WebUI Community | `basalt-stack/web/open-webui/` | Chat interface (Svelte + Python) |

### 1.3 AI Platform Tier (Onyx)

| Component | Image | Version | Supplier | Compose Location | Purpose |
|-----------|-------|---------|----------|-----------------|---------|
| Onyx Backend | `onyxdotapp/onyx-backend` | `latest` | OnyxDotApp Inc | `onyx/deployment/docker_compose/` | API server + background worker |
| Onyx Web | `onyxdotapp/onyx-web-server` | `latest` | OnyxDotApp Inc | `onyx/deployment/docker_compose/` | Next.js frontend |
| Onyx Model Server | `onyxdotapp/onyx-model-server` | `latest` | OnyxDotApp Inc | `onyx/deployment/docker_compose/` | Embedding / reranking inference |
| Onyx Postgres | `postgres` | `15.2-alpine` | PostgreSQL Global Dev Group | `onyx/deployment/docker_compose/` | Onyx relational database |
| Onyx Vespa | `vespaengine/vespa` | `8.526.15` | Yahoo / Vespa.ai | `onyx/deployment/docker_compose/` | Vector search index |
| Onyx Nginx | `nginx` | `1.23.4-alpine` | F5 / Nginx Inc | `onyx/deployment/docker_compose/` | Reverse proxy |
| Onyx Redis | `redis` | `7.4-alpine` | Redis Ltd | `onyx/deployment/docker_compose/` | Session / cache store |
| Onyx MinIO | `minio/minio` | `RELEASE.2025-07-23T15-54-02Z-cpuv1` | MinIO Inc | `onyx/deployment/docker_compose/` | Document object storage |

### 1.4 Version Pinning Status

| Status | Count | Details |
|--------|-------|---------|
| Pinned (exact tag) | 14 | vLLM, LiteLLM, Langfuse, ClickHouse, MinIO (x2), Authentik, Vespa, Nginx, Postgres (x4), Redis (x2 at 7.4-alpine) |
| Floating tag | 3 | Open-WebUI (`main`), Onyx images (`latest`), Redis (`alpine` — no minor pin) |

> **Action Required:** Pin Open-WebUI and Onyx images to exact version tags before production deployment. Floating tags are non-reproducible and violate SSDF PW.4.1 (verify provenance of each component).

---

## 2. Python Dependencies

### 2.1 RMF Document Generator (first-party)

**Location:** `basalt-stack/tools/rmf-generator/requirements.txt`

| Package | Version Constraint | Supplier | Purpose |
|---------|--------------------|----------|---------|
| `pydantic` | `>=2.0,<3.0` | Samuel Colvin / Pydantic | Data validation / schemas |
| `docxtpl` | `>=0.18,<1.0` | Eric Lapouyade | .docx Jinja2 template rendering |
| `openai` | `>=1.0,<2.0` | OpenAI | OpenAI-compatible API client |
| `pyyaml` | `>=6.0,<7.0` | Kirill Simonov | YAML parsing |

### 2.2 Open-WebUI Backend

**Location:** `open-webui/backend/requirements.txt` — 36 direct dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `fastapi` | 0.111.0 | Web framework |
| `uvicorn[standard]` | 0.29.0 | ASGI server |
| `pydantic` | 2.7.1 | Data validation |
| `flask` | 3.0.3 | Legacy web framework |
| `python-socketio` | 5.11.2 | WebSocket support |
| `python-jose` | 3.3.0 | JWT handling |
| `passlib[bcrypt]` | 1.7.4 | Password hashing |
| `requests` | 2.32.2 | HTTP client |
| `aiohttp` | 3.9.5 | Async HTTP client |
| `peewee` | 3.17.5 | ORM |
| `bcrypt` | 4.1.3 | Password hashing |
| `litellm` | 1.30.7 | Unified LLM API |
| `argon2-cffi` | 23.1.0 | Password hashing |
| `chromadb` | 0.5.0 | Vector database |
| `transformers` | 4.43.3 | ML model support |
| `sentence_transformers` | 2.7.0 | Embedding models |
| `langchain` | 0.2.0 | LLM chain framework |
| `langchain-community` | 0.2.0 | LangChain integrations |
| `pypdf` | 4.2.0 | PDF parsing |
| `unstructured` | 0.14.0 | Document parsing |
| `markdown` | 3.6 | Markdown processing |
| `pandas` | 2.2.2 | Data analysis |
| `opencv-python-headless` | 4.9.0.80 | Image processing |
| `faster-whisper` | 1.0.2 | Speech-to-text |
| `PyJWT` | 2.8.0 | JWT tokens |
| `black` | 24.4.2 | Code formatter |

<details>
<summary>Full list (10 additional packages)</summary>

| Package | Version | Purpose |
|---------|---------|---------|
| `python-multipart` | 0.0.9 | Form data parsing |
| `flask_cors` | 4.0.1 | CORS support |
| `uuid` | 1.30 | UUID generation |
| `apscheduler` | 3.10.4 | Task scheduling |
| `google-generativeai` | 0.5.4 | Google AI client |
| `fake_useragent` | 1.5.1 | User-agent spoofing |
| `docx2txt` | 0.8 | Word doc extraction |
| `pypandoc` | 1.13 | Document conversion |
| `openpyxl` | 3.1.2 | Excel support |
| `xlrd` | 2.0.1 | Legacy Excel support |
| `pyxlsb` | 1.0.10 | Excel binary format |
| `rapidocr-onnxruntime` | 1.3.22 | OCR engine |

</details>

### 2.3 Onyx Backend

**Location:** `onyx/backend/requirements/` — split across 4 files

| File | Direct Deps | Key Packages (security-relevant) |
|------|-------------|----------------------------------|
| `default.txt` | ~117 | `fastapi` 0.116.1, `openai` 1.107.1, `litellm` 1.76.2, `SQLAlchemy` 2.0.15, `pydantic` 2.11.7, `cryptodome` 3.19.1, `python3-saml` 1.15.0, `xmlsec` 1.3.14, `passlib` 1.7.4 |
| `model_server.txt` | ~20 | `torch` 2.6.0, `transformers` 4.53.0, `sentence-transformers` 4.0.2, `safetensors` 0.5.3, `accelerate` 1.6.0 |
| `dev.txt` | ~30 | `pytest` 8.3.5, `mypy` 1.13.0, `ruff` 0.12.0, `black` 25.1.0 |
| `ee.txt` | 2 | `cohere` 5.6.1, `posthog` 3.7.4 |

> **Note:** Onyx is deployed as-is (not developed in this repo). Full dependency lists at `onyx/backend/requirements/*.txt`. Total: **~169 direct Python dependencies**.

---

## 3. JavaScript / Node.js Dependencies

### 3.1 Onyx Web Frontend

**Location:** `onyx/web/package.json`

| Category | Count | Key Packages |
|----------|-------|-------------|
| Production | ~65 | `next` ^15.5.2, `react` ^18.3.1, `zustand` ^5.0.7, `swr` ^2.1.5, `tailwindcss` ^3.3.1 |
| UI Components | ~18 | `@radix-ui/*` ^1.x (18 packages), `@headlessui/react` ^2.2.0, `bits-ui` |
| Dev | ~20 | `typescript` 5.0.3, `eslint` ^8.57.1, `jest` ^29.7.0, `prettier` 3.1.0 |

### 3.2 Open-WebUI Frontend

**Location:** `open-webui/package.json`

| Category | Count | Key Packages |
|----------|-------|-------------|
| Production | ~20 | `svelte` ^4.0.5, `@sveltejs/kit` ^1.30.0, `marked` ^9.1.0, `katex` ^0.16.9, `highlight.js` ^11.9.0, `tailwindcss` ^3.3.3 |
| Dev | ~15 | `typescript` ^5.0.0, `vite` ^4.4.2, `eslint` ^8.56.0, `prettier` ^2.8.0 |

> **Note:** `node_modules` are built into Docker images at build time. No npm/yarn operations occur at runtime on the air-gapped target.

---

## 4. LLM Model Artifacts

| Model | Format | Size (approx) | Source | Purpose |
|-------|--------|---------------|--------|---------|
| `openai/gpt-oss-20b` | SafeTensors (HuggingFace) | ~16 GB (MXFP4) | HuggingFace Hub | Primary inference model |
| Onyx embedding models | HuggingFace | TBD | HuggingFace Hub | RAG embedding + reranking |

> **Pre-staging required:** Model weights must be downloaded on an internet-connected machine and transferred to the air-gapped target. vLLM requires weights on a Linux-native filesystem (not Windows 9p mount).

---

## 5. Telemetry Suppression

All telemetry and phone-home behavior is disabled for air-gap compliance.

| Service | Setting | Value | Enforcement |
|---------|---------|-------|-------------|
| vLLM | `VLLM_NO_USAGE_STATS` | `1` | Compose environment |
| Langfuse | `TELEMETRY_ENABLED` | `false` | `.env` |
| Authentik | `AUTHENTIK_DISABLE_UPDATE_CHECK` | `true` | Compose environment |
| Authentik | `AUTHENTIK_ERROR_REPORTING__ENABLED` | `false` | Compose environment |
| Authentik | `AUTHENTIK_DISABLE_STARTUP_ANALYTICS` | `true` | Compose environment |
| Open-WebUI | `SCARF_NO_ANALYTICS` | `true` | Compose environment |
| Open-WebUI | `DO_NOT_TRACK` | `true` | Compose environment |
| Open-WebUI | `ANONYMIZED_TELEMETRY` | `false` | Compose environment |
| Onyx | `HF_HUB_OFFLINE` | `1` | `.env` (planned) |

---

## 6. Cryptographic Materials

| Material | Algorithm | Key Size | Validity | Location |
|----------|-----------|----------|----------|----------|
| Basalt TLS Certificate | RSA | 4096-bit | 10 years | `basalt-stack/web/authentik/certs/` |
| SAN Coverage | — | — | — | `*.basalt.local`, `basalt.local`, `host.docker.internal`, `localhost`, `127.0.0.1` |

> **Note:** Self-signed certificate. Production deployment should use an internal CA. Certificate and private key are gitignored.

---

## 7. Aggregate Counts

| Category | Count |
|----------|-------|
| Container images (unique) | 17 |
| Distinct base images | 4 (postgres, redis, nginx, minio) |
| Application images | 13 |
| Python packages (RMF generator) | 4 |
| Python packages (Open-WebUI) | 36 |
| Python packages (Onyx — all files) | ~169 |
| JavaScript packages (Onyx web) | ~85 |
| JavaScript packages (Open-WebUI) | ~35 |
| LLM model artifacts | 1 confirmed + TBD (Onyx embeddings) |
| Telemetry kill switches | 8 |

---

## 8. NIST Compliance Notes

### NTIA Minimum Elements Coverage

| NTIA Element | Status | Notes |
|--------------|--------|-------|
| Supplier name | Covered | Listed per component in Sections 1-3 |
| Component name | Covered | Image names, package names |
| Version | Covered | Pinned tags and version constraints |
| Unique identifier | Partial | Docker image digests not captured; use `docker inspect --format='{{.RepoDigests}}'` at deployment time |
| Dependency relationship | Partial | Direct dependencies listed; transitive deps in lock files within container images |
| Author of SBOM | Covered | Metadata header |
| Timestamp | Covered | Metadata header |

### NIST SP 800-218 (SSDF) Alignment

| Practice | Status | Evidence |
|----------|--------|----------|
| **PW.4.1** — Verify provenance | Partial | 14/17 images version-pinned; 3 use floating tags (`main`, `latest`, `alpine`) |
| **PW.4.4** — Archive/protect SBOM | Manual | This document is committed to repo; update on each dependency change |
| **PS.3.1** — Protect software integrity | Covered | Air-gap staging via `docker save/load`; no runtime downloads |
| **PO.1.1** — Specify security requirements | Covered | Telemetry suppression table; TLS configuration documented |

### Recommended Follow-Up Actions

1. **Pin floating tags** — Open-WebUI (`main`), Onyx (`latest`), Redis (`alpine`) should use exact version tags
2. **Capture image digests** — Run `docker images --digests` at deployment time and append to this document
3. **Generate machine-readable SBOM** — Use `syft` or `trivy sbom` against each image for CycloneDX/SPDX JSON output
4. **Vulnerability scan** — Run `trivy image` or `grype` against all 17 images before deployment
5. **Transitive dependency audit** — Python `pip freeze` and Node `npm ls --all` inside containers for full dependency trees

---

*Last updated: 2026-03-19 | Next review: before each production deployment*
