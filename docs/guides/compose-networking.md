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
