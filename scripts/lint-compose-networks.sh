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

    # Coarse check: file must contain both 'proxy:' and 'external: true'.
    # Not a full YAML parse — sufficient for Basalt compose files where proxy
    # is the only external network. For precise validation, use yq.
    if grep -q 'proxy:' "$compose_file" && grep -q 'external: true' "$compose_file"; then
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
