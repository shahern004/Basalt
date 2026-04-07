# gen-cert.ps1 — Generate self-signed TLS certificate for Basalt Stack (wildcard)
# Covers *.basalt.local so all current and future subdomains work without regen.
# Run once before first `docker compose up`.  Safe to re-run (overwrites).
#
# Usage (from web/authentik/):
#   powershell -ExecutionPolicy Bypass -File scripts\gen-cert.ps1
# or simply:
#   .\scripts\gen-cert.ps1

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Resolve paths relative to this script, regardless of caller's CWD.
$ScriptDir = $PSScriptRoot
$CertDir   = Join-Path $ScriptDir '..\certs' | Resolve-Path -ErrorAction SilentlyContinue
if (-not $CertDir) {
    $CertDir = New-Item -ItemType Directory -Force -Path (Join-Path $ScriptDir '..\certs')
}
$CertDir = (Resolve-Path $CertDir).Path

# Locate openssl.exe — prefer PATH, fall back to Git for Windows install.
# Note: Get-Command returns $null when not found; under Set-StrictMode we must
# null-check the result *before* touching .Source, or strict mode will throw.
$openssl = $null
$opensslCmd = Get-Command openssl.exe -ErrorAction SilentlyContinue
if ($opensslCmd) {
    $openssl = $opensslCmd.Source
}
if (-not $openssl) {
    $gitOpenssl = 'C:\Program Files\Git\usr\bin\openssl.exe'
    if (Test-Path $gitOpenssl) {
        $openssl = $gitOpenssl
    } else {
        Write-Error @'
openssl.exe not found.

Install one of:
  - Git for Windows (bundles openssl at C:\Program Files\Git\usr\bin\openssl.exe)
  - Win32/Win64 OpenSSL: https://slproweb.com/products/Win32OpenSSL.html
Then re-run this script.
'@
        exit 1
    }
}

$KeyFile  = Join-Path $CertDir 'basalt.local-key.pem'
$CertFile = Join-Path $CertDir 'basalt.local.pem'

# Build openssl arg list as an array — avoids Windows quoting headaches.
$opensslArgs = @(
    'req', '-x509', '-nodes',
    '-newkey', 'rsa:4096',
    '-days',   '3650',
    '-keyout', $KeyFile,
    '-out',    $CertFile,
    '-subj',   '/CN=basalt.local',
    '-addext', 'subjectAltName=DNS:*.basalt.local,DNS:basalt.local,DNS:host.docker.internal,DNS:localhost,IP:127.0.0.1'
)

& $openssl @opensslArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "openssl failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

# Lock down the private key — Windows ACL equivalent of `chmod 600`.
# Strip inheritance, then grant read/write only to the current user.
try {
    icacls $KeyFile /inheritance:r        | Out-Null
    icacls $KeyFile /grant:r "$($env:USERNAME):(R,W)" | Out-Null
} catch {
    Write-Warning "Could not tighten ACL on private key: $_"
}

Write-Host ''
Write-Host 'Certificate written to:'
Write-Host "  $CertFile      (fullchain)"
Write-Host "  $KeyFile  (private key)"
Write-Host ''
Write-Host 'SANs: *.basalt.local, basalt.local, host.docker.internal, localhost, 127.0.0.1'
Write-Host ''
Write-Host 'After first Authentik boot:'
Write-Host "  1. Admin UI > System > Brands > edit 'authentik-default'"
Write-Host "  2. Set 'Web certificate' to the imported basalt.local cert"
Write-Host '  3. Outpost config: set authentik_host_insecure: true (self-signed)'
