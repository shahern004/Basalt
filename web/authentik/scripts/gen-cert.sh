#!/usr/bin/env bash
# gen-cert.sh — Generate self-signed TLS certificate for Basalt Stack (wildcard)
# Covers *.basalt.local so all current and future subdomains work without regen.
# Run once before first `docker compose up`.  Safe to re-run (overwrites).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_DIR="$SCRIPT_DIR/../certs"

mkdir -p "$CERT_DIR"

openssl req -x509 -nodes \
  -newkey rsa:4096 \
  -days 3650 \
  -keyout "$CERT_DIR/basalt.local-key.pem" \
  -out    "$CERT_DIR/basalt.local.pem" \
  -subj   "/CN=basalt.local" \
  -addext "subjectAltName=DNS:*.basalt.local,DNS:basalt.local,DNS:host.docker.internal,DNS:localhost,IP:127.0.0.1"

chmod 600 "$CERT_DIR/basalt.local-key.pem"

echo "Certificate written to:"
echo "  $CERT_DIR/basalt.local.pem      (fullchain)"
echo "  $CERT_DIR/basalt.local-key.pem  (private key)"
echo ""
echo "SANs: *.basalt.local, basalt.local, host.docker.internal, localhost, 127.0.0.1"
echo ""
echo "After first Authentik boot:"
echo "  1. Admin UI > System > Brands > edit 'authentik-default'"
echo "  2. Set 'Web certificate' to the imported basalt.local cert"
echo "  3. Outpost config: set authentik_host_insecure: true (self-signed)"
