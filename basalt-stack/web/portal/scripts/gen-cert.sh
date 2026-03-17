#!/usr/bin/env bash
# gen-cert.sh — Generate self-signed TLS certificate for Basalt Portal
# Run once before first `docker compose up`.  Safe to re-run (overwrites).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_DIR="$SCRIPT_DIR/../certs"

mkdir -p "$CERT_DIR"

openssl req -x509 -nodes \
  -newkey rsa:4096 \
  -days 3650 \
  -keyout "$CERT_DIR/portal.key" \
  -out    "$CERT_DIR/portal.crt" \
  -subj   "/CN=basalt-portal" \
  -addext "subjectAltName=IP:127.0.0.1,DNS:localhost"

echo "Certificate written to $CERT_DIR/portal.{crt,key}"
