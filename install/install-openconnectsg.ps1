#Requires -RunAsAdministrator
<#
.SYNOPSIS
  openconnectsg system installer - Deploys openconnectsg binaries to C:\Program Files\OpenConnect\bin
  and registers the directory in the system PATH.
.DESCRIPTION
  Execute once in an administrative PowerShell session.
  Detects local repository files or optionally clones from a remote Git URL.
.NOTES
  Save encoding: UTF-8 with BOM.
.PARAMETER RepoUrl
  Remote Git repository URL to clone if performing remote setup.
.PARAMETER Dest
  Destination directory for cloned source (Default: C:\Program Files\OpenConnect\repo).
.PARAMETER BinDir
  Target deployment binary directory (Default: C:\Program Files\OpenConnect\bin).
.PARAMETER SkipClone
  Skips git clone and uses local repository source.
.PARAMETER SourceDir
  Source repository root directory.
#>
[CmdletBinding()]
param(
  [string]$RepoUrl,
  [string]$Dest = 'C:\Program Files\OpenConnect\repo',
  [string]$BinDir = 'C:\Program Files\OpenConnect\bin',
  [switch]$SkipClone,
  [string]$SourceDir,
  [switch]$Uninstall,
  [string]$Scope
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

if ($Uninstall) {
  $targetPs1 = Join-Path $BinDir 'openconnectsg.ps1'
  if (-not (Test-Path $targetPs1)) {
    $targetPs1 = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src') 'openconnectsg.ps1'
  }
  if (Test-Path $targetPs1) {
    & $targetPs1 uninstall $Scope
    exit $LASTEXITCODE
  } else {
    throw "openconnectsg.ps1 not found to perform uninstallation."
  }
}

# Auto-detect local source directory
if (-not $SkipClone -and [string]::IsNullOrWhiteSpace($RepoUrl)) {
  $candidate = Split-Path -Parent $PSScriptRoot
  if (Test-Path (Join-Path $candidate 'src\openconnectsg.ps1')) {
    $SkipClone = $true
    $SourceDir = $candidate
  }
}

# Acquire source files
if ($SkipClone) {
  if ([string]::IsNullOrWhiteSpace($SourceDir)) { $SourceDir = Split-Path -Parent $PSScriptRoot }
  if ([string]::IsNullOrWhiteSpace($SourceDir)) { $SourceDir = (Get-Location).Path }
  Write-Host "Installing from local source: $SourceDir"
} else {
  if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
    $RepoUrl = (Read-Host "Git repository URL to clone").Trim()
  }
  if ([string]::IsNullOrWhiteSpace($RepoUrl)) { throw 'Repository URL is required.' }
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "git command not found. Downloading repository archive via HTTPS..."
    $zipUrl = 'https://github.com/sparklings/openconnectsg/archive/refs/heads/main.zip'
    $zipFile = Join-Path $env:TEMP ('openconnectsg_install_' + [guid]::NewGuid().ToString('N') + '.zip')
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    try {
      Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing -TimeoutSec 30
    } catch {
      $wc = New-Object System.Net.WebClient
      $wc.DownloadFile($zipUrl, $zipFile)
    }
    if (-not (Test-Path $zipFile)) { throw 'Failed to download installer archive from GitHub.' }
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    Expand-Archive -Path $zipFile -DestinationPath $Dest -Force
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    $candidate = Join-Path $Dest 'openconnectsg-main'
    if (Test-Path (Join-Path $candidate 'src\openconnectsg.ps1')) {
      $SourceDir = $candidate
    } else {
      $SourceDir = $Dest
    }
  } else {
    if (Test-Path $Dest) {
      Remove-Item $Dest -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path (Split-Path $Dest) -Force | Out-Null
    git clone $RepoUrl $Dest
    $SourceDir = $Dest
  }
}

# Verify and deploy
$srcBin = Join-Path $SourceDir 'src'
$initSrc = Join-Path $srcBin 'init-openconnectsg.ps1'
if (-not (Test-Path (Join-Path $srcBin 'openconnectsg.ps1'))) { throw "Required binary not found in $srcBin" }
if (-not (Test-Path $initSrc))                               { throw "Setup wizard script not found in $srcBin" }

New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
Copy-Item (Join-Path $srcBin 'openconnectsg.ps1')     $BinDir -Force
Copy-Item (Join-Path $srcBin 'openconnectsg.cmd')     $BinDir -Force
Copy-Item $initSrc                                     $BinDir -Force
Copy-Item (Join-Path $PSScriptRoot 'install-openconnectsg.ps1') $BinDir -Force
Write-Host "Files deployed successfully to $BinDir"

# Register system PATH (duplicate prevention)
$mp = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if (-not (($mp -split ';') -contains $BinDir)) {
  [Environment]::SetEnvironmentVariable('Path', ($mp.TrimEnd(';') + ';' + $BinDir), 'Machine')
  Write-Host "Added $BinDir to System PATH."
} else {
  Write-Host "$BinDir is already in System PATH."
}

# Verification and installation marker
$cmd = Join-Path $BinDir 'openconnectsg.cmd'
if (Test-Path $cmd) {
  $ver = '0.1.2d'
  $marker = "version=$ver`r`nsource=$SourceDir`r`ninstalled=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"
  [System.IO.File]::WriteAllText((Join-Path $BinDir '.installed'), $marker, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "Installed openconnectsg $ver."
  Write-Host "Verifying command execution:"
  & $cmd version
}

# Detect dependency versions if installed
$detectedNssm = 'Pending Setup'
$nssmPath = 'C:\Program Files\nssm\nssm.exe'
if (Test-Path $nssmPath) {
  try {
    $vi = (Get-Item $nssmPath).VersionInfo.ProductVersion
    if (-not [string]::IsNullOrWhiteSpace($vi)) { $detectedNssm = "v$vi" }
  } catch { }
}

$detectedOc = 'Pending Setup'
$ocPath = 'C:\Program Files\OpenConnect\openconnect.exe'
if (Test-Path $ocPath) {
  try {
    $rawOcVer = (& $ocPath --version 2>&1 | Select-Object -First 1)
    if ($rawOcVer -match 'v[\d\.]+') {
      $detectedOc = $Matches[0]
    } elseif (-not [string]::IsNullOrWhiteSpace($rawOcVer)) {
      $detectedOc = ($rawOcVer -split ' ')[1]
    }
  } catch { }
}

Write-Host ""
Write-Host "   ____                   ______                            __   _____       " -ForegroundColor Cyan
Write-Host "  / __ \____  ___  ____  / ____/___  ____  ____  ___  _____/ /_ / ___/____ _ " -ForegroundColor Cyan
Write-Host " / / / / __ \/ _ \/ __ \/ /   / __ \/ __ \/ __ \/ _ \/ ___/ __/ \__ \/ __ `/ " -ForegroundColor Cyan
Write-Host "/ /_/ / /_/ /  __/ / / / /___/ /_/ / / / / / / /  __/ /__/ /_   ___/ / /_/ /  " -ForegroundColor Cyan
Write-Host "\____/ .___/\___/_/ /_/\____/\____/_/ /_/_/ /_/\___/\___/\__/  /____/\__, /   " -ForegroundColor Cyan
Write-Host "    /_/                                                             /____/    " -ForegroundColor Cyan
Write-Host " ==============================================================================" -ForegroundColor DarkGray
Write-Host "  OpenConnectSg :: Windows Background Daemon & DPAPI Automation Wrapper (v$ver)" -ForegroundColor White
Write-Host " ==============================================================================" -ForegroundColor DarkGray
Write-Host "  [DEPLOY]   Target   : $BinDir" -ForegroundColor DarkCyan
Write-Host "  [SYSTEM]   PATH     : Successfully registered (Machine Scope)" -ForegroundColor DarkCyan
Write-Host "  [PACKAGES] Required : OpenConnect CLI $detectedOc, NSSM $detectedNssm" -ForegroundColor DarkCyan
Write-Host "  [FEATURES] Windows DPAPI Encrypted Credential (pw.bin), Wintun Kernel Tunnel Adapter" -ForegroundColor Gray
Write-Host ""
Write-Host " ------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  QUICK START INSTRUCTIONS" -ForegroundColor Green
Write-Host " ------------------------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  1. Reload PATH in current session (or open a new terminal):" -ForegroundColor White
Write-Host "     `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +" -ForegroundColor Yellow
Write-Host "                 [Environment]::GetEnvironmentVariable('Path','User')" -ForegroundColor Yellow
Write-Host ""
Write-Host "  2. Run the interactive setup wizard:" -ForegroundColor White
Write-Host "     openconnectsg setup" -ForegroundColor Yellow
Write-Host ""
Write-Host "  3. Connect and verify service status:" -ForegroundColor White
Write-Host "     openconnectsg connect" -ForegroundColor Yellow
Write-Host "     openconnectsg status" -ForegroundColor Yellow
Write-Host ""
Write-Host "  For all subcommands and syntax: openconnectsg help" -ForegroundColor DarkGray
Write-Host " ==============================================================================" -ForegroundColor DarkGray
Write-Host ""

