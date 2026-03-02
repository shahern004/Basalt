---
title: "ClickHouse Alpine Health Check Failure on Docker Desktop"
date: 2026-02-17
tags: [clickhouse, docker, alpine, langfuse, health-check]
services: [langfuse]
---

# Problem

After starting the Langfuse stack, the ClickHouse container repeatedly failed its Docker health check and never reached a healthy state. Dependent services (Langfuse web, Langfuse worker) could not start because they depend on ClickHouse being healthy.

The health check command was:

```yaml
healthcheck:
  test: ["CMD", "wget", "--spider", "-q", "http://localhost:8123/ping"]
```

In some runs, the container would also crash-loop with the error `Address already in use` on port 9000 or 8123 during startup.

# Root Cause

Two independent issues combined to make ClickHouse unreliable on Docker Desktop with the Alpine-based image (`clickhouse/clickhouse-server:25.2.1.3085-alpine`).

## Issue 1: Alpine IPv6 Resolution

Alpine Linux resolves `localhost` to `::1` (IPv6) before `127.0.0.1` (IPv4). Docker containers typically have IPv6 disabled. The `wget` health check connected to `::1:8123`, which is unreachable, and the health check failed even though ClickHouse was listening correctly on `0.0.0.0:8123`.

## Issue 2: Entrypoint Dual-Start Bug

The ClickHouse Alpine Docker entrypoint script provisions users and databases by:

1. Starting a **temporary** ClickHouse server instance
2. Running `CREATE USER` / `CREATE DATABASE` SQL commands against it using the `CLICKHOUSE_DB`, `CLICKHOUSE_USER`, and `CLICKHOUSE_PASSWORD` environment variables
3. Stopping the temporary instance
4. Starting the **main** ClickHouse server

On fast systems (NVMe storage, modern CPUs), the temporary server does not fully release its listening ports before the main server attempts to bind them. This causes `Address already in use` errors and a crash-loop.

This only manifests when `CLICKHOUSE_DB`, `CLICKHOUSE_USER`, or `CLICKHOUSE_PASSWORD` environment variables are set, because the temporary server is only started when there is provisioning work to do.

# Solution

## Fix 1: Use `127.0.0.1` in Health Checks

Replaced `localhost` with `127.0.0.1` in the health check to bypass Alpine's IPv6 DNS resolution:

```yaml
healthcheck:
  test: ["CMD", "wget", "--spider", "-q", "http://127.0.0.1:8123/ping"]
```

This is a general best practice for any Alpine-based container health check.

## Fix 2: Provision User via XML Config File

Removed the `CLICKHOUSE_DB`, `CLICKHOUSE_USER`, and `CLICKHOUSE_PASSWORD` environment variables from the ClickHouse service definition. Instead, the user is provisioned via an XML config file mounted into the container:

**New file: `clickhouse-users.xml`**

This file is mounted to `/etc/clickhouse-server/users.d/clickhouse-users.xml` in the container. ClickHouse reads user definition files from `users.d/` on startup without needing a temporary server, completely eliminating the dual-start race condition.

## Fix 3: Relaxed Health Check Timing

The health check timing was tightened too aggressively for first-run scenarios. Updated to give ClickHouse adequate time to initialize:

```yaml
healthcheck:
  interval: 10s      # was 5s
  timeout: 5s
  retries: 15         # was 10
  start_period: 30s   # was 1s
```

## Fix 4: Removed Explicit User/Group

Removed `user: "101:101"` from the ClickHouse service definition. This was causing permission errors on data directories when the container tried to write to mounted volumes.

# Files Changed

| File | Change |
|------|--------|
| `basalt-stack/inference/langfuse/docker-compose.yaml` | Health check: `localhost` to `127.0.0.1`; removed `CLICKHOUSE_DB`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD` env vars; removed `user: "101:101"`; relaxed health check timing |
| `basalt-stack/inference/langfuse/clickhouse-users.xml` | **New file** - XML user provisioning config mounted to `/etc/clickhouse-server/users.d/` |

# Applicability

This fix applies to any deployment using the Alpine-based ClickHouse image (`clickhouse/clickhouse-server:*-alpine`). The IPv6 issue affects all Alpine-based containers using `localhost` in health checks, not just ClickHouse.
