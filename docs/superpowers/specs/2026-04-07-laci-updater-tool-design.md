---
title: "LACI Updater Tool — Design Spec"
date: 2026-04-07
status: draft
category: spec
tags:
  - laci
  - automation
  - workgroup-tool
  - tooling
related:
  - "[[basalt-development-roadmap|roadmap]]"
  - "[[2026-03-24-laci-v1.1-delta-analysis|laci-delta]]"
  - "[[2026-03-26-open-webui-custom-image-build-design|openwebui-build]]"
---

# LACI Updater Tool — Design Spec

## Problem

LACI AI Platform updates are often distributed to internal AI development teams as zip drops (compose files, env templates, db includes, docs, SBOMs). Downstream tools (Basalt, SAIL, SAFE-AI, etc.) face the recurring, laborious, error-prone task of re-personalizing each update. The process usually consists of at LEAST the following steps, depending on the integrating dev environment:

- Extract the zip
- Copy files into the consuming repo, being careful not to overwrite files containing tool-specific configurations and/or secrets
- Transfer to isolated network, commit, push, open a PR
- Line-by-line diff against current state to determine potentially functionality-breaking changes
- Re-apply or preserve all the standing customizations the project added during initial LACI setup (hostnames, model paths, port mappings, generated secrets, custom blueprints, image tag pins, etc.)

This is very time consuming, and potentially catastrophic when updates go wrong.

## Goals

1. **Tool-specific configuration preserved.** All standing configuration labor from the initial LACI install (secrets, hostnames, paths, ports, custom services, blueprints, image tag pins) is preserved across updates
2. **Single-command workflow.** The consumer runs one command with one argument and gets a git branch ready for PR review
3. **Zero per-project configuration.** No YAML files, no settings, no flags. The tool assumes the consuming repo follows LACI's native directory layout
4. **Single-file distribution.** A single Python script (optionally accompanied by a small README/CHANGELOG) that can be emailed as a zip and dropped into a `tools/` directory on any consumer's air-gapped machine
5. **Deployment validation.** A `validate` subcommand confirms the updated stack works by checking container health across all LACI compose stacks and running LACI's shipped test scripts (`test-vllm.sh`, `test-litellm.sh`)
6. **Air-gap safe.** No network calls at runtime. Python stdlib + `git` + `docker` CLI only. No `pip install`, no telemetry, no external services

## Out-of-Scope

- ❌ Restructuring a consumer repo to match LACI's layout. The tool assumes the consumer already follows the LACI directory layout described in [Output Directory Structure](#output-directory-structure); it will not move, rename, or reorganize existing files to reach that state
- ❌ Pulling Docker images — image distribution is a separate orthogonal pipeline (LACI handles via skopeo to artifactory; air-gapped consumers handle via `docker save`/`load` separately)
- ❌ Starting or stopping the stack as part of validation — `validate` assumes the consumer has already run `docker compose up -d` and the stack is live.
- ❌ Managing or generating documentation about LACI itself — LACI ships its own README, PDFs, and SBOM; the tool just preserves them
- ❌ Per-project documentation cleanup. Documentation is managed by each team to fit their specific requirements.
- ❌ Automatic pull requests for any specific git platform
- ❌ Cross-machine sync, central state, shared infrastructure
- ❌ Handling LACI structural reorganizations (e.g., LACI v2.0 moves files to new paths). Surfaced as a warning in the diff report, but auto-relocation is out of scope
- ❌ Resolving git merge conflicts automatically — conflicts surface as native git conflict markers and the consumer resolves them with their normal tools

## User Experience

### Standard Updates

```bash
# In the consuming repo's root directory:
$ python tools/laci-update.py absorb /path/to/laci-25apr.zip
```

### First-time bootstrap (one-time per project)

```bash
$ python tools/laci-update.py bootstrap /path/to/laci-24mar.zip
```

### Status / inspection

```bash
$ python tools/laci-update.py status
```

### Validate deployment (after merge + stack start)

```bash
$ python tools/laci-update.py validate
```

## LACI Updater Architecture

### Tool Components (single python script file)

```
tools/laci-update.py    ← single-file tool
├── Subcommands
│   ├── bootstrap       ← one-time: establish baseline
│   ├── absorb          ← normal: ingest a new LACI drop
│   ├── status          ← inspect: show baseline + customization state
│   └── validate        ← capstone: verify the deployed stack works
├── Core operations (absorb path)
│   ├── extract_zip()           ← stdlib zipfile
│   ├── detect_laci_version()   ← parse README, fall back to dir name
│   ├── compute_file_plan()     ← classify each file: add/update/remove/skip/archive
│   ├── apply_file_plan()       ← copy/delete files in working tree
│   ├── compute_three_way_diff()← baseline vs new vs current
│   ├── generate_diff_report()  ← markdown report
│   ├── update_baseline()       ← snapshot new LACI files into .laci-baseline/
│   └── git_branch_and_commit() ← subprocess to git binary
├── Core operations (validate path)
│   ├── discover_compose_stacks()  ← find all docker-compose.yaml files under inference/ and web/
│   ├── check_container_health()   ← parse `docker compose ps --format json` per stack
│   ├── run_laci_test_scripts()    ← locate + execute test-*.sh per inference stack
│   └── generate_validation_report()← markdown report (separate from absorb's diff report)
└── No external dependencies (stdlib + git on PATH + docker CLI for validate)
```

### Output Directory Structure

The tool creates and maintains the following directory structure, in alignment with the LACI architecture:

```
<consumer-repo>/
├── .laci-baseline/                ← created by bootstrap, updated by absorb
│   ├── VERSION                    ← single line: "v1.1" (latest absorbed)
│   ├── BOOTSTRAP_DATE             ← single line: "2026-04-07"
│   └── v1.1/                      ← exact unmodified copy of LACI v1.1 files
│       ├── inference/...
│       ├── web/...
│       └── utils/...
├── docs/
│   ├── laci/                      ← created by absorb
│   │   ├── v1.0/                  ← preserved LACI docs from each absorption
│   │   │   ├── README
│   │   │   ├── LACI_v1.0_SBOM.xlsx
│   │   │   └── LACI_Stack_Deployment_Considerations.pdf
│   │   └── v1.1/...
│   └── laci-updates/              ← created by absorb
│       ├── 2026-03-24-v1.1-report.md
│       └── 2026-04-25-v1.2-report.md
└── (the consumer's normal repo contents — inference/, web/, etc.)
```

### File classification rules

For each file in the new LACI zip, the tool decides what to do:

| Source path pattern | Action | Reason |
|---|---|---|
| `**/.env` | **SKIP** | Contains secrets — never overwrite consumer's working values |
| `**/.env.example` | **UPDATE** | Templates are safe to update; consumer's `.env` is unaffected |
| `**/docker-compose.yaml` | **UPDATE (merge-aware)** | Consumer customizations preserved by git's 3-way merge after the absorb commit |
| `**/include/*.yaml`, `**/db/include.yaml` | **UPDATE** | Same as above |
| `**/litellm-config.yaml` | **UPDATE** | Same as above |
| `README`, `*.pdf`, `*.xlsx`, `*.pptx` | **ARCHIVE** | Move to `docs/laci/<version>/` instead of overwriting |
| `utils/*.sh` | **UPDATE** | LACI's helper scripts; consumers may have customized — git handles |
| Files present in baseline but absent in new drop | **REMOVE** | LACI removed them |
| Files in new drop but not in baseline | **ADD** | LACI added them |

**`.env` files are never touched by the tool for security purposes.**

### Methodology

The tool sets up the conditions for git's native 3-way merge:

1. Creates branch `laci-update/<version>-<date>` from current `main`
2. Overlays the new LACI files onto that branch (skipping `.env`)
3. Commits the result with a descriptive message
4. Consumer pushes the branch and opens a PR
5. **When the consumer eventually runs `git merge laci-update/v1.2 main`**, git computes a 3-way merge using:
   - Common ancestor: the previous absorption commit (which had clean LACI v1.1 files)
   - Branch A (`main`): consumer's customized state (LACI v1.1 + their edits)
   - Branch B (`laci-update/v1.2`): clean LACI v1.2 + the consumer's `.env` files

## Diff Report Format

The LACI Updater generates a markdown report at `docs/laci-updates/<date>-<version>-report.md` for human and agentic-AI consumption (e.g., SAFE-AI). The report contains the following sections in stable order:

- Summary (previous version, new version, file counts, tool version)
- Files added (new files introduced by the LACI update)
- Files removed (files LACI deleted)
- Files updated (with per-file conflict flags for 3-way diff hotspots)
- Image version changes (tags that moved, requiring separate image pulls)
- `.env` template changes (new vars in `.env.example` the consumer may need to propagate)
- Likely conflicts (same-line edits by both LACI and the consumer)
- Structural warnings (paths LACI moved or renamed)
- LACI documentation archived (paths under `docs/laci/<version>/`)

## Deployment Validation

Run `validate` after the consumer has merged the update branch, pulled any new images, and started the stack. The tool inspects running container state — it does not start, stop, or restart anything.

Two stages, run in order:

1. **Container health checks.** Discover every `docker-compose.yaml` under `inference/` and `web/`; run `docker compose ps --format json` per stack; read each container's health field. A stack passes if every container reports `healthy` or `running`. Containers in `starting` state are rechecked for up to 60 seconds before being declared failed.
2. **LACI shipped test scripts.** For each stack under `inference/`, execute any `test-*.sh` script LACI ships (e.g., `test-vllm.sh`, `test-litellm.sh`) from the stack's directory. Capture exit codes and the last lines of output. Stage 2 is skipped if Stage 1 fails.

Results are written to `docs/laci-updates/<date>-<version>-validation.md`. HTTP endpoint probes and end-to-end tracing are out of scope for v1 and deferred as follow-on work.
