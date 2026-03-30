#!/usr/bin/env bash
# stage-images.sh — Pull, verify, and export Authentik images for air-gap transfer
#
# Usage (internet-connected machine):
#   ./stage-images.sh pull     # Pull images from registry
#   ./stage-images.sh save     # Export to .tar files in ./images/
#   ./stage-images.sh verify   # Print image digests for post-transfer verification
#
# Usage (air-gapped target):
#   ./stage-images.sh load     # Import .tar files into local Docker
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_DIR="$SCRIPT_DIR/../images"

# Image list — update versions here when upgrading
AUTHENTIK_IMAGE="ghcr.io/goauthentik/server:2026.2.1"
POSTGRES_IMAGE="docker.io/library/postgres:16-alpine"
REDIS_IMAGE="docker.io/library/redis:7.4-alpine"

ALL_IMAGES=("$AUTHENTIK_IMAGE" "$POSTGRES_IMAGE" "$REDIS_IMAGE")

# Friendly tar filenames (no slashes or colons)
tar_name() {
  echo "$1" | sed 's|[/:]|_|g'
}

cmd_pull() {
  echo "Pulling images..."
  for img in "${ALL_IMAGES[@]}"; do
    echo "  $img"
    docker pull "$img"
  done
  echo "Done. Run '$0 verify' to record digests, then '$0 save' to export."
}

cmd_save() {
  mkdir -p "$IMAGE_DIR"
  echo "Saving images to $IMAGE_DIR ..."
  for img in "${ALL_IMAGES[@]}"; do
    local tarfile="$IMAGE_DIR/$(tar_name "$img").tar"
    echo "  $img → $(basename "$tarfile")"
    docker save -o "$tarfile" "$img"
  done
  echo ""
  echo "Transfer the $IMAGE_DIR/ directory to the air-gapped host."
  echo "Then run '$0 load' on the target."
}

cmd_load() {
  if [ ! -d "$IMAGE_DIR" ]; then
    echo "ERROR: $IMAGE_DIR not found. Copy the images/ directory from the staging machine first."
    exit 1
  fi
  echo "Loading images from $IMAGE_DIR ..."
  for tarfile in "$IMAGE_DIR"/*.tar; do
    echo "  $(basename "$tarfile")"
    docker load -i "$tarfile"
  done
  echo "Done. Run '$0 verify' to confirm digests match."
}

cmd_verify() {
  echo "Image digests (compare before and after transfer):"
  echo "---------------------------------------------------"
  for img in "${ALL_IMAGES[@]}"; do
    local digest
    digest=$(docker image inspect --format '{{.Id}}' "$img" 2>/dev/null || echo "NOT FOUND")
    printf "  %-50s %s\n" "$img" "$digest"
  done
}

case "${1:-help}" in
  pull)   cmd_pull   ;;
  save)   cmd_save   ;;
  load)   cmd_load   ;;
  verify) cmd_verify ;;
  *)
    echo "Usage: $0 {pull|save|load|verify}"
    echo ""
    echo "  pull    Pull images from registry (internet-connected machine)"
    echo "  save    Export images to .tar files in ./images/"
    echo "  load    Import .tar files into Docker (air-gapped target)"
    echo "  verify  Print image digests for comparison"
    exit 1
    ;;
esac
