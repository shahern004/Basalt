#Requires -Version 5.1
<#
.SYNOPSIS
    Validates Windows host prerequisites for the basalt-host WSL2 distro.
.DESCRIPTION
    Checks: WSL2 version, NVIDIA driver, .wslconfig mirrored networking,
    distro name availability, D:\WSL\ path.
    Run from the Windows host before creating the basalt-host distro.
#>

$ErrorActionPreference = 'Continue'
$allPassed = $true

function Write-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    if ($Passed) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Name - $Detail" -ForegroundColor Red
        $script:allPassed = $false
    }
}

Write-Host "`n=== Basalt Host Prerequisites ===" -ForegroundColor Cyan
Write-Host ""

# 1. WSL2 installed and version 2.0+
try {
    $wslOutput = wsl --version 2>&1
    $versionLine = ($wslOutput | Select-String 'WSL version').ToString()
    $verString = ($versionLine -replace '.*:\s*', '').Trim()
    $ver = [version]$verString
    Write-Check "WSL2 version ($ver)" ($ver -ge [version]'2.0.0') "Requires 2.0+. Run: wsl --update"
} catch {
    Write-Check "WSL2 installed" $false "WSL2 not found. Enable via: wsl --install"
}

# 2. NVIDIA driver visible from host
try {
    $driverVersion = (& nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>&1).Trim()
    Write-Check "NVIDIA driver ($driverVersion)" $true ""
} catch {
    Write-Check "NVIDIA driver" $false "nvidia-smi not found. Install NVIDIA Game Ready or Studio driver."
}

# 3. .wslconfig exists with mirrored networking
$wslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path $wslConfigPath) {
    $content = Get-Content $wslConfigPath -Raw
    $hasMirrored = $content -match 'networkingMode\s*=\s*mirrored'
    Write-Check ".wslconfig exists" $true ""
    Write-Check ".wslconfig has networkingMode=mirrored" $hasMirrored `
        "Add under [wsl2]: networkingMode=mirrored  (see U4 in spec)"
} else {
    Write-Check ".wslconfig exists" $false "Create $wslConfigPath with [wsl2] section. See U4/U5 in spec."
}

# 4. Distro name 'basalt-host' not already taken
$distros = (wsl --list --quiet 2>&1) | ForEach-Object { $_.Trim() }
$taken = $distros -contains 'basalt-host'
Write-Check "Distro name 'basalt-host' available" (-not $taken) `
    "Already exists. Unregister first: wsl --unregister basalt-host"

# 5. D:\WSL\ parent directory exists
$parentExists = Test-Path 'D:\WSL'
Write-Check "D:\WSL\ directory exists" $parentExists "Create D:\WSL\ for WSL2 distro storage"

# Summary
Write-Host ""
if ($allPassed) {
    Write-Host "All checks passed. Ready to create basalt-host distro." -ForegroundColor Green
} else {
    Write-Host "Some checks failed. Fix the issues above before proceeding." -ForegroundColor Yellow
}
Write-Host ""
