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
  [string]$SourceDir
)
$ErrorActionPreference = 'Stop'

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
    throw 'git command not found. Please install Git or run installer with -SkipClone from a downloaded directory.'
  }
  if (Test-Path $Dest) {
    Write-Host "Target repository directory exists. Pulling latest: $Dest"
    git -C $Dest pull --ff-only
  } else {
    New-Item -ItemType Directory -Path (Split-Path $Dest) -Force | Out-Null
    git clone $RepoUrl $Dest
  }
  $SourceDir = $Dest
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
  $ver = '0.1.0'
  $marker = "version=$ver`r`nsource=$SourceDir`r`ninstalled=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"
  [System.IO.File]::WriteAllText((Join-Path $BinDir '.installed'), $marker, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "Installed openconnectsg $ver."
  Write-Host "Verifying command execution:"
  & $cmd version
}

Write-Host "Installation completed successfully."
Write-Host "Next step: Open a new terminal and run 'openconnectsg setup' to add a profile."
