# Build script for Magic CLI (PowerShell)
# Functionally mirrors scripts/build-magic-cli.sh for Windows PowerShell

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Formatting helpers ---
function Write-Info    { param([string]$m) Write-Host "ℹ️  $m" -ForegroundColor Cyan }
function Write-Success { param([string]$m) Write-Host "✔ $m"  -ForegroundColor Green }
function Write-Warn    { param([string]$m) Write-Host "⚠️  $m" -ForegroundColor Yellow }
function Write-ErrorMsg{ param([string]$m) Write-Host "✖ $m"  -ForegroundColor Red }
function Write-Step    { param([string]$m) Write-Host "➤ $m"  -ForegroundColor Blue }
function Write-Complete{ param([string]$m) Write-Host "✅ $m" -ForegroundColor Green }
function Write-Header  {
  param([string]$m)
  Write-Host ('─' * 70) -ForegroundColor Magenta
  Write-Host ("  $m") -ForegroundColor Magenta
  Write-Host ('─' * 70) -ForegroundColor Magenta
}

function Restore-Files {
  Write-Info "Restoring original cjpm.toml files..."
  if (Test-Path -LiteralPath $script:BackupMagicCjpm) {
    Move-Item -Force -LiteralPath $script:BackupMagicCjpm -Destination $script:OriginalMagicCjpm
    Write-Success "Restored $script:OriginalMagicCjpm"
  }
  if (Test-Path -LiteralPath $script:BackupLocalCjpm) {
    Move-Item -Force -LiteralPath $script:BackupLocalCjpm -Destination $script:OriginalLocalCjpm
    Write-Success "Restored $script:OriginalLocalCjpm"
  }
}

function Run-External {
  param(
    [Parameter(Mandatory=$true)][string]$FilePath,
    [string[]]$ArgumentList = @(),
    [switch]$Quiet
  )
  if ($Quiet) {
    & $FilePath @ArgumentList *> $null
  } else {
    & $FilePath @ArgumentList
  }
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed ($LASTEXITCODE): $FilePath $([string]::Join(' ', $ArgumentList))"
  }
}

# --- Environment checks ---
if (-not $env:CANGJIE_HOME) {
  Write-ErrorMsg "CANGJIE_HOME is not set!"
  exit 1
}

# Attempt to load Cangjie env if a PowerShell setup exists; otherwise continue.
$envSetupPs1 = Join-Path $env:CANGJIE_HOME 'envsetup.ps1'
if (Test-Path -LiteralPath $envSetupPs1) {
  . $envSetupPs1
}

# Ensure cjpm is available on PATH
if (-not (Get-Command cjpm -ErrorAction SilentlyContinue)) {
  Write-ErrorMsg "cjpm was not found on PATH. Ensure Cangjie tools are installed and available."
  exit 1
}

# --- Paths ---
$scriptDir = $PSScriptRoot

$magicPath = $env:MAGIC_PATH
if (-not $magicPath) {
  Write-ErrorMsg "MAGIC_PATH environment variable is not set"
  exit 1
}

$targetDir = Join-Path -Path (Get-Location).Path -ChildPath 'target\release\bin'
$binaryDir = Join-Path -Path (Get-Location).Path -ChildPath 'binary'

$OriginalMagicCjpm = Join-Path $magicPath 'cjpm.toml'
$OriginalLocalCjpm = Join-Path -Path (Get-Location).Path -ChildPath 'cjpm.toml'
$BackupMagicCjpm   = Join-Path $magicPath 'cjpm.toml.backup'
$BackupLocalCjpm   = Join-Path -Path (Get-Location).Path -ChildPath 'cjpm.toml.backup'

$script:OriginalMagicCjpm = $OriginalMagicCjpm
$script:OriginalLocalCjpm = $OriginalLocalCjpm
$script:BackupMagicCjpm   = $BackupMagicCjpm
$script:BackupLocalCjpm   = $BackupLocalCjpm

$magicStatic = Join-Path $scriptDir 'magic-static.toml'
$cliStatic   = Join-Path $scriptDir 'cli-static.toml'

if (-not (Test-Path -LiteralPath $magicStatic)) {
  Write-ErrorMsg "$magicStatic not found"
  exit 1
}
if (-not (Test-Path -LiteralPath $cliStatic)) {
  Write-ErrorMsg "$cliStatic not found"
  exit 1
}

Write-Header "Starting Magic CLI Build Process"
Write-Host ""
Write-Info  "Script directory: $scriptDir"
Write-Info  "Magic path: $magicPath"
Write-Host ""

$script:buildSucceeded = $false
$script:finalBinaryPath = $null

try {
  # Step 1: Backup original MAGIC_PATH/cjpm.toml and copy static version
  Write-Step "Step 1: Setting up static configuration for $OriginalMagicCjpm"
  if (Test-Path -LiteralPath $OriginalMagicCjpm) {
    Copy-Item -Force -LiteralPath $OriginalMagicCjpm -Destination $BackupMagicCjpm
    Write-Success "Backed up $OriginalMagicCjpm to $BackupMagicCjpm"
  }
  Copy-Item -Force -LiteralPath $magicStatic -Destination $OriginalMagicCjpm
  Write-Success "Copied $magicStatic to $OriginalMagicCjpm"
  Write-Host ""

  # Step 2: Backup original local cjpm.toml and copy static version
  Write-Step "Step 2: Setting up static configuration for local cjpm.toml"
  if (Test-Path -LiteralPath $OriginalLocalCjpm) {
    Copy-Item -Force -LiteralPath $OriginalLocalCjpm -Destination $BackupLocalCjpm
    Write-Success "Backed up $OriginalLocalCjpm to $BackupLocalCjpm"
  }
  Copy-Item -Force -LiteralPath $cliStatic -Destination $OriginalLocalCjpm
  Write-Success "Copied $cliStatic to $OriginalLocalCjpm"
  Write-Host ""

  # Step 3.1: Clean up ffi directory
  Write-Step "Step 3.1: Cleaning up ffi directory..."
  if (Test-Path -LiteralPath './ffi') {
    Write-Info "Removing .a, .so, and .dylib files from ./ffi directory..."
    Get-ChildItem -Path './ffi' -Recurse -Include *.a,*.so,*.dylib -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Success "Cleanup completed"
  } else {
    Write-Warn "./ffi directory not found, skipping cleanup"
  }
  Write-Host ""

  # Step 3.2: Clean existing project
  Write-Step "Step 3.2: Cleaning up existing project..."
  Run-External -FilePath 'cjpm' -ArgumentList @('clean') -Quiet
  Write-Host ""

  # Step 3.3: Build project
  Write-Step "Step 3.3: Building project with static configuration..."
  Run-External -FilePath 'cjpm' -ArgumentList @('build')
  Write-Host ""

  # Step 4: Copy binary to target location
  Write-Step "Step 4: Copying binary..."
  if (-not (Test-Path -LiteralPath $binaryDir)) {
    New-Item -ItemType Directory -Force -Path $binaryDir | Out-Null
    Write-Success "Created directory: $binaryDir"
  }

  $cliNoExt = Join-Path $targetDir 'metis'
  $cliExe   = Join-Path $targetDir 'metis.exe'
  if (Test-Path -LiteralPath $cliNoExt) {
    $dest = Join-Path $binaryDir 'magic-cli'
    Copy-Item -Force -LiteralPath $cliNoExt -Destination $dest
    $script:finalBinaryPath = $dest
    Write-Success "Copied $cliNoExt to $dest"
  } elseif (Test-Path -LiteralPath $cliExe) {
    $dest = Join-Path $binaryDir 'magic-cli.exe'
    Copy-Item -Force -LiteralPath $cliExe -Destination $dest
    $script:finalBinaryPath = $dest
    Write-Success "Copied $cliExe to $dest"
  } else {
    Write-ErrorMsg "Binary not found at $cliNoExt or $cliExe"
    throw "Build output binary not found"
  }
  Write-Host ""

  $script:buildSucceeded = $true
}
catch {
  Write-ErrorMsg ("Error: " + $_.Exception.Message)
}
finally {
  Write-Step "Step 5: Cleaning up and restoring original files..."
  Restore-Files
  Write-Host ""
  if ($script:buildSucceeded -and $script:finalBinaryPath) {
    Write-Complete "Build completed successfully!"
    Write-Success  "Binary available at: $script:finalBinaryPath"
    exit 0
  } else {
    exit 1
  }
}
