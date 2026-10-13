#Requires -Version 5.1
<#
.SYNOPSIS
  openconnectsg - Unified CLI tool for OpenConnect VPN profile management and service orchestration.
.DESCRIPTION
  Entry point syntax: `openconnectsg <verb> [arguments]`.
  Provides end-to-end profile lifecycle management, DPAPI-backed daemon execution,
  and single-tunnel enforcement on Windows systems.
.NOTES
  Save encoding: UTF-8 with BOM, CRLF line endings.
  Exit codes: 0 Success, 1 Runtime error, 2 Usage error.
#>
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$script:Version = '0.1.2'

$ocRoot      = 'C:\Program Files\OpenConnect'
$root        = Join-Path $ocRoot 'profiles'
$nssm        = 'C:\Program Files\nssm\nssm.exe'
$defaultFile = Join-Path $root 'default.txt'

function Get-Profiles {
  $list = @()
  if (-not (Test-Path $root)) { return $list }
  $defaultName = ''
  if (Test-Path $defaultFile) { $defaultName = (Get-Content $defaultFile -Raw).Trim() }
  $i = 0
  foreach ($d in (Get-ChildItem -Path $root -Directory | Sort-Object Name)) {
    $i++
    $name   = $d.Name
    $server = ''
    $conf   = Join-Path $d.FullName 'openconnect.conf'
    if (Test-Path $conf) {
      $line = Get-Content $conf -ErrorAction SilentlyContinue | Where-Object { $_ -match '^server=' } | Select-Object -First 1
      if ($line) { $server = ($line -replace '^server=', '').Trim() -replace '^https?://', '' }
    }
    $user = ''
    $uf = Join-Path $d.FullName 'user.txt'
    if (Test-Path $uf) { $user = (Get-Content $uf -Raw).Trim() }
    $alias = ''
    $lf = Join-Path $d.FullName 'label.txt'
    if (Test-Path $lf) { $alias = (Get-Content $lf -Raw).Trim() }
    $status = 'N/A'
    $s = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($s) { $status = [string]$s.Status }
    $list += [pscustomobject]@{
      Index     = $i
      Name      = $name
      User      = $user
      Server    = $server
      Alias     = $alias
      Status    = $status
      IsDefault = ($name -eq $defaultName)
    }
  }
  return $list
}

function Show-List {
  param($profiles)
  if (@($profiles).Count -eq 0) {
    Write-Host 'No registered profiles found. Run: openconnectsg setup'
    return
  }
  Write-Host ('{0,-2}{1,-3} {2,-18} {3,-24} {4,-12} {5}' -f '', '#', 'User', 'Server', 'Alias', 'Status')
  foreach ($p in $profiles) {
    Write-Host ('{0,-2}{1,-3} {2,-18} {3,-24} {4,-12} {5}' -f ($(if ($p.IsDefault) { '*' } else { '' })), $p.Index, $p.User, $p.Server, $p.Alias, $p.Status)
  }
}

function Resolve-Profile {
  param($profiles, $token)
  if ([string]::IsNullOrWhiteSpace($token)) {
    # If no token given, fallback to default profile if present
    if (Test-Path $defaultFile) {
      $def = (Get-Content $defaultFile -Raw).Trim()
      $hit = @($profiles | Where-Object { $_.Name -eq $def })
      if ($hit.Count -eq 1) { return $hit[0] }
    }
    throw 'Please specify a profile. Syntax: openconnectsg connect <profile>'
  }
  if ($token -match '^\d+$') {
    $hit = @($profiles | Where-Object { $_.Index -eq [int]$token })
    if ($hit.Count -eq 0) { throw "Profile index out of range: $token" }
    return $hit[0]
  }
  # Exact match on alias
  $hit = @($profiles | Where-Object { $_.Alias -and $_.Alias -eq $token })
  if ($hit.Count -eq 1) { return $hit[0] }
  if ($hit.Count -gt 1) { throw ("Alias '{0}' is ambiguous across multiple profiles. Specify by index: {1}" -f $token, (($hit | ForEach-Object { $_.Index }) -join ', ')) }
  # Exact match on username
  $hit = @($profiles | Where-Object { $_.User -and $_.User -eq $token })
  if ($hit.Count -eq 1) { return $hit[0] }
  if ($hit.Count -gt 1) { throw ("User account '{0}' is ambiguous across multiple profiles. Specify by index: {1}" -f $token, (($hit | ForEach-Object { $_.Index }) -join ', ')) }
  # Substring match
  $pat = '*' + [System.Management.Automation.WildcardPattern]::Escape($token) + '*'
  $hit = @($profiles | Where-Object {
    ($_.Alias  -and $_.Alias  -like $pat) -or
    ($_.User   -and $_.User   -like $pat) -or
    ($_.Server -and $_.Server -like $pat) -or
    ($_.Name   -like $pat)
  })
  if ($hit.Count -eq 1) { return $hit[0] }
  if ($hit.Count -eq 0) { throw "No matching profile found: $token" }
  throw ("Multiple profiles match '{0}'. Please be more specific: {1}" -f $token, (($hit | ForEach-Object { $_.Name }) -join ', '))
}

function Assert-Nssm {
  if (-not (Test-Path $nssm)) {
    throw "NSSM binary not found at $nssm. Please run 'openconnectsg setup' first."
  }
}

function Invoke-Nssm {
  param([string[]]$Argv)
  Assert-Nssm
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'SilentlyContinue'
  & $nssm @Argv 2>$null | Out-Null
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  return $code
}

function Wait-ServiceStatus {
  param([string]$Name, [string]$Want, [int]$TimeoutSec = 15)
  for ($n = 0; $n -lt $TimeoutSec; $n++) {
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $s) { return 'N/A' }
    if ([string]$s.Status -eq $Want) { return $Want }
    Start-Sleep -Seconds 1
  }
  $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
  if ($s) { return [string]$s.Status } else { return 'N/A' }
}

function Do-Connect {
  param($profiles, $token)
  $t = Resolve-Profile $profiles $token
  # Single active connection policy: disconnect any other active tunnels
  foreach ($p in $profiles) {
    if ($p.Name -ne $t.Name -and $p.Status -eq 'Running') {
      Write-Host "disconnect $($p.Name)"
      [void](Invoke-Nssm @('stop', $p.Name))
    }
  }
  $cur = Get-Service -Name $t.Name -ErrorAction SilentlyContinue
  if ($cur -and [string]$cur.Status -eq 'Running') {
    Write-Host "Already connected: $($t.Name)"
  } else {
    Write-Host "connect $($t.Name)"
    [void](Invoke-Nssm @('start', $t.Name))
  }
  Set-Content $defaultFile $t.Name -NoNewline -Encoding ascii
  $final = Wait-ServiceStatus $t.Name 'Running' 15
  if ($final -ne 'Running') {
    Write-Host "Warning: Service failed to reach Running state (Current: $final)"
    $errFile = "$root\$($t.Name)\logs\err.log"
    $outFile = "$root\$($t.Name)\logs\out.log"
    $combined = ""
    if (Test-Path $errFile) { $combined += "`n" + ((Get-Content $errFile -Tail 5 -ErrorAction SilentlyContinue) -join "`n") }
    if (Test-Path $outFile) { $combined += "`n" + ((Get-Content $outFile -Tail 5 -ErrorAction SilentlyContinue) -join "`n") }
    if ($combined -match 'sslvpn_login_permission_denied|Permission denied') {
      Write-Warning "Authentication failed: VPN server returned 'Permission denied'."
      Write-Host "  Possible causes: Server-side account authorization policy, user group restrictions, or invalid credentials."
    } elseif ($combined -match 'Too many bad login attempts') {
      Write-Warning "Authentication blocked: Too many bad login attempts. Please wait a few minutes before trying again."
    } elseif ($combined -match 'Failed to complete authentication|fgetws') {
      Write-Warning "Authentication failed: VPN server rejected credentials or interactive prompt timed out."
    } elseif (-not [string]::IsNullOrWhiteSpace($combined.Trim())) {
      Write-Host "  Error detail:"
      Write-Host "  $($combined.Trim())"
    }
    Write-Host "  Log files: $errFile | $outFile"
    return 1
  }
  Write-Host "Status: Running"
  return 0
}

function Do-Disconnect {
  param($profiles, $token)
  if ([string]::IsNullOrWhiteSpace($token) -or $token -eq 'all') {
    $rc = 0
    foreach ($p in $profiles) {
      if ($p.Status -eq 'Running') {
        Write-Host "disconnect $($p.Name)"
        [void](Invoke-Nssm @('stop', $p.Name))
        if ((Wait-ServiceStatus $p.Name 'Stopped' 15) -ne 'Stopped') {
          Write-Host "Warning: Service $($p.Name) failed to stop gracefully."
          $rc = 1
        }
      }
    }
    return $rc
  }
  $t = Resolve-Profile $profiles $token
  Write-Host "disconnect $($t.Name)"
  [void](Invoke-Nssm @('stop', $t.Name))
  $final = Wait-ServiceStatus $t.Name 'Stopped' 15
  if ($final -ne 'Stopped') {
    Write-Host "Warning: Failed to stop service (Current: $final)"
    return 1
  }
  Write-Host "Status: Stopped"
  return 0
}

function Do-Status {
  param($profiles, $token)
  if ([string]::IsNullOrWhiteSpace($token)) {
    if (Test-Path $defaultFile) {
      $def = (Get-Content $defaultFile -Raw).Trim()
      $hit = @($profiles | Where-Object { $_.Name -eq $def })
      if ($hit.Count -eq 1) { $token = $hit[0].Name }
    }
    if ([string]::IsNullOrWhiteSpace($token)) {
      $running = @($profiles | Where-Object { $_.Status -eq 'Running' })
      if ($running.Count -eq 1) { $token = $running[0].Name }
    }
  }

  if ([string]::IsNullOrWhiteSpace($token)) {
    Show-List $profiles
    return 0
  }

  $t = Resolve-Profile $profiles $token
  $s = Get-Service -Name $t.Name -ErrorAction SilentlyContinue
  $status = if ($s) { [string]$s.Status } else { 'N/A' }

  Write-Host "Profile Details:"
  Write-Host "  Name       : $($t.Name)"
  Write-Host "  Index      : $($t.Index)"
  Write-Host "  Alias      : $(if ($t.Alias) { $t.Alias } else { '(none)' })"
  Write-Host "  User       : $($t.User)"
  Write-Host "  Server     : $($t.Server)"
  Write-Host "  Status     : $status"
  Write-Host "  Default    : $(if ($t.IsDefault) { 'Yes' } else { 'No' })"

  $profDir = Join-Path $root $t.Name
  $hbFile = Join-Path $profDir 'heartbeat.status'
  if ($status -eq 'Running') {
    if (Test-Path $hbFile) {
      $hbRaw = Get-Content $hbFile -Raw -ErrorAction SilentlyContinue
      $lastRecv = if ($hbRaw -match 'LastReceived=([^\r\n]+)') { $matches[1].Trim() } else { $null }
      $hbCount  = if ($hbRaw -match 'Count=(\d+)') { $matches[1].Trim() } else { '0' }
      if ($lastRecv) {
        try {
          $secAgo = [math]::Max(0, [int]((Get-Date) - [DateTime]::Parse($lastRecv)).TotalSeconds)
          if ($secAgo -le 30) {
            Write-Host "  Heartbeat  : ALIVE ($secAgo s ago, packets: $hbCount)" -ForegroundColor Green
          } elseif ($secAgo -le 90) {
            Write-Host "  Heartbeat  : IDLE ($secAgo s ago, packets: $hbCount)" -ForegroundColor Yellow
          } else {
            Write-Host "  Heartbeat  : STALE ($secAgo s ago, packets: $hbCount)" -ForegroundColor Red
          }
        } catch {
          Write-Host "  Heartbeat  : Recorded ($lastRecv, packets: $hbCount)"
        }
      }
    } else {
      Write-Host "  Heartbeat  : Waiting for keepalive..." -ForegroundColor DarkGray
    }
  }

  $errFile = Join-Path $profDir 'logs\err.log'
  if (Test-Path $errFile) {
    $errLen = (Get-Item $errFile).Length
    if ($errLen -gt 0) {
      $recentErr = (Get-Content $errFile -Tail 3 -ErrorAction SilentlyContinue) -join "`n"
      if (-not [string]::IsNullOrWhiteSpace($recentErr.Trim())) {
        Write-Host "  Recent Error:" -ForegroundColor Red
        $recentErr.Split("`n") | ForEach-Object {
          if (-not [string]::IsNullOrWhiteSpace($_)) { Write-Host "    $_" -ForegroundColor DarkRed }
        }
      }
    }
  }

  return 0
}

function Do-Default {
  param($profiles, $token)
  if ([string]::IsNullOrWhiteSpace($token)) {
    if (Test-Path $defaultFile) {
      $def = (Get-Content $defaultFile -Raw).Trim()
      $hit = @($profiles | Where-Object { $_.Name -eq $def })
      if ($hit.Count -eq 1) {
        Write-Host "default = $($hit[0].Name) (Alias: $($hit[0].Alias), User: $($hit[0].User))"
        return 0
      }
    }
    Write-Host "No default profile set. Syntax: openconnectsg default <profile>"
    return 1
  }
  $t = Resolve-Profile $profiles $token
  Set-Content $defaultFile $t.Name -NoNewline -Encoding ascii
  Write-Host "default = $($t.Name)"
  return 0
}

function Do-Alias {
  param($profiles, $token, $alias)
  if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($alias)) {
    throw 'Please provide both profile and alias. Syntax: openconnectsg alias <profile> <alias_name>'
  }
  $t = Resolve-Profile $profiles $token
  Set-Content (Join-Path (Join-Path $root $t.Name) 'label.txt') $alias -NoNewline -Encoding utf8
  Write-Host "alias '$alias' -> $($t.Name)"
  return 0
}

function Do-Remove {
  param($profiles, $token)
  if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Please specify a profile to remove. Syntax: openconnectsg remove <profile>'
  }
  $t = Resolve-Profile $profiles $token
  Write-Host "Target: $($t.Name) (User: $($t.User))"
  if ($t.Status -eq 'Running') { Write-Host '  Notice: Service is active. Will be terminated prior to removal.' }
  $ans = (Read-Host "This will stop the service, unregister it, and purge the profile directory. Type 'yes' to proceed").Trim()
  if ($ans -ne 'yes') { Write-Host 'Cancelled.'; return 0 }
  [void](Invoke-Nssm @('stop', $t.Name))
  [void](Invoke-Nssm @('remove', $t.Name, 'confirm'))
  Remove-Item (Join-Path $root $t.Name) -Recurse -Force -ErrorAction SilentlyContinue
  if ((Test-Path $defaultFile) -and ((Get-Content $defaultFile -Raw).Trim() -eq $t.Name)) {
    Remove-Item $defaultFile -Force -ErrorAction SilentlyContinue
  }
  Write-Host "Removed profile and service: $($t.Name)"
  return 0
}

function Do-Setup {
  param([string[]]$Extra)
  $init = Join-Path $PSScriptRoot 'init-openconnectsg.ps1'
  if (-not (Test-Path $init)) { throw "Setup wizard script not found: $init" }
  Write-Host "Launching interactive setup wizard..."
  & $init @Extra | Out-Host
  return $LASTEXITCODE
}

function Do-Uninstall {
  param([string]$ScopeArg)

  # Check administrative privileges
  $isAdmin = $false
  try {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    $isAdmin = $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { }

  if (-not $isAdmin) {
    throw "Administrative privileges are required to uninstall. Please run in an elevated administrator shell."
  }

  Write-Host "========================================"
  Write-Host "    openconnectsg Uninstaller"
  Write-Host "========================================"
  Write-Host ""

  # Determine scope
  $mode = $null
  if ($ScopeArg -match '^(full|all|--all|--full)$') {
    $mode = 'full'
  } elseif ($ScopeArg -match '^(app|only|--app|--app-only|--only-app)$') {
    $mode = 'app'
  } else {
    Write-Host "Select uninstallation scope:"
    Write-Host "  [1] openconnectsg only (Recommended)"
    Write-Host "      - Stops and removes all openconnectsg profiles and services"
    Write-Host "      - Removes openconnectsg files and removes from System PATH"
    Write-Host "      - Keeps OpenConnect CLI and NSSM binaries intact"
    Write-Host ""
    Write-Host "  [2] Full Purge"
    Write-Host "      - Stops and removes all openconnectsg profiles and services"
    Write-Host "      - Completely uninstalls OpenConnect CLI (C:\Program Files\OpenConnect)"
    Write-Host "      - Completely removes NSSM (C:\Program Files\nssm)"
    Write-Host "      - Purges all associated directories and PATH entries"
    Write-Host ""
    Write-Host "  [q] Cancel / Abort"
    Write-Host ""

    $choice = (Read-Host "Enter your choice [1/2/q]").Trim().ToLower()
    if ($choice -eq '1') {
      $mode = 'app'
    } elseif ($choice -eq '2') {
      $mode = 'full'
    } else {
      Write-Host "Uninstallation cancelled."
      return 0
    }
  }

  $confirm = (Read-Host "Are you sure you want to proceed with uninstallation? (Type 'yes' to proceed)").Trim()
  if ($confirm -ne 'yes') {
    Write-Host "Uninstallation cancelled."
    return 0
  }

  Write-Host ""
  Write-Host "[1/3] Terminating active tunnels and unregistering services..."
  $services = @(Get-Service -Name "openconnect*" -ErrorAction SilentlyContinue)
  foreach ($s in $services) {
    Write-Host "  Stopping service: $($s.Name)"
    try {
      if (Test-Path $nssm) {
        & $nssm stop $s.Name 2>&1 | Out-Null
        & $nssm remove $s.Name confirm 2>&1 | Out-Null
      } else {
        Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue
        & sc.exe delete $s.Name 2>&1 | Out-Null
      }
    } catch {
      Write-Warning "Failed to stop/remove service $($s.Name): $($_.Exception.Message)"
    }
  }

  Write-Host "[2/3] Cleaning openconnectsg profiles and System PATH..."
  # Clean profiles
  if (Test-Path $root) {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Purged profiles directory: $root"
  }

  # Clean bin from PATH
  $binDir = Join-Path $ocRoot 'bin'
  $mp = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  if ($mp) {
    $paths = ($mp -split ';') | Where-Object {
      $p = $_.Trim()
      $p -and ($p.TrimEnd('\') -ne $binDir.TrimEnd('\'))
    }
    $newPath = ($paths -join ';')
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
    Write-Host "  Removed $binDir from System PATH."
  }

  # Clean bin folder
  if (Test-Path $binDir) {
    Remove-Item $binDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Purged binary directory: $binDir"
  }

  # Clean repo folder if exists inside OpenConnect
  $repoDir = Join-Path $ocRoot 'repo'
  if (Test-Path $repoDir) {
    Remove-Item $repoDir -Recurse -Force -ErrorAction SilentlyContinue
  }

  if ($mode -eq 'full') {
    Write-Host "[3/3] Purging OpenConnect CLI and NSSM..."
    # NSSM directory
    $nssmDir = 'C:\Program Files\nssm'
    if (Test-Path $nssmDir) {
      Remove-Item $nssmDir -Recurse -Force -ErrorAction SilentlyContinue
      Write-Host "  Removed NSSM directory: $nssmDir"
    }

    # Clean NSSM and OpenConnect from System PATH
    $mpFull = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($mpFull) {
      $pathsFull = ($mpFull -split ';') | Where-Object {
        $p = $_.Trim().TrimEnd('\')
        $p -and ($p -ne $ocRoot.TrimEnd('\')) -and ($p -ne $nssmDir.TrimEnd('\')) -and ($p -ne $binDir.TrimEnd('\'))
      }
      [Environment]::SetEnvironmentVariable('Path', ($pathsFull -join ';'), 'Machine')
      Write-Host "  Cleaned OpenConnect and NSSM from System PATH."
    }

    # OpenConnect Uninstaller if present
    $ocUninstaller = Join-Path $ocRoot 'Uninstall OpenConnect.exe'
    if (Test-Path $ocUninstaller) {
      Write-Host "  Running OpenConnect CLI uninstaller..."
      Start-Process $ocUninstaller -ArgumentList "/S" -Wait -ErrorAction SilentlyContinue
    }
    # Remaining OpenConnect directory
    if (Test-Path $ocRoot) {
      Remove-Item $ocRoot -Recurse -Force -ErrorAction SilentlyContinue
      Write-Host "  Purged OpenConnect directory: $ocRoot"
    }
    Write-Host ""
    Write-Host "Full uninstallation completed successfully. All components were removed."
  } else {
    Write-Host "[3/3] Preserving OpenConnect CLI and NSSM binaries."
    Write-Host ""
    Write-Host "openconnectsg uninstallation completed successfully."
    Write-Host "OpenConnect CLI and NSSM have been preserved."
  }

  return 0
}

function Do-Upgrade {
  param($token)
  $binDir = 'C:\Program Files\OpenConnect\bin'
  $installedFile = Join-Path $binDir '.installed'

  $wp = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  $isAdmin = $wp.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Host "Administrative privileges are required to upgrade openconnectsg."
    Write-Host "Requesting elevation via User Account Control (UAC)..."
    $selfPath = $MyInvocation.MyCommand.Definition
    if ([string]::IsNullOrWhiteSpace($selfPath) -or -not (Test-Path $selfPath)) {
      $selfPath = Join-Path $binDir 'openconnectsg.ps1'
    }
    $argStr = "-NoProfile -ExecutionPolicy Bypass -Command `"& '$selfPath' upgrade"
    if (-not [string]::IsNullOrWhiteSpace($token)) { $argStr += " '$token'" }
    $argStr += "; Write-Host ''; Read-Host 'Press Enter to close this window...'`""

    try {
      $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $argStr -PassThru
      Write-Host "Elevation requested (Process ID: $($p.Id)). Please approve the UAC prompt."
      return 0
    } catch {
      try {
        $sh = New-Object -ComObject Shell.Application
        $sh.ShellExecute("powershell.exe", $argStr, "", "runas", 1)
        Write-Host "Elevation requested via ShellExecute. Please approve the UAC prompt."
        return 0
      } catch {
        throw "Failed to elevate process. Please run 'openconnectsg upgrade' from an elevated administrator console."
      }
    }
  }

  Write-Host "=== openconnectsg System Upgrade ==="
  $sourceDir = $token
  if ([string]::IsNullOrWhiteSpace($sourceDir) -and (Test-Path $installedFile)) {
    $line = Get-Content $installedFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '^source=' } | Select-Object -First 1
    if ($line) { $sourceDir = ($line -replace '^source=', '').Trim() }
  }
  if ([string]::IsNullOrWhiteSpace($sourceDir) -or -not (Test-Path $sourceDir)) {
    $candidate = Split-Path -Parent $PSScriptRoot
    if (Test-Path (Join-Path $candidate 'src\openconnectsg.ps1')) {
      $sourceDir = $candidate
    } elseif (Test-Path 'C:\Program Files\OpenConnect\repo') {
      $sourceDir = 'C:\Program Files\OpenConnect\repo'
    }
  }
  if ([string]::IsNullOrWhiteSpace($sourceDir) -or -not (Test-Path $sourceDir)) {
    throw "Source repository directory could not be determined. Please specify source path: openconnectsg upgrade <path_to_repo>"
  }

  Write-Host "Source directory: $sourceDir"

  if (Test-Path (Join-Path $sourceDir '.git')) {
    if (Get-Command git -ErrorAction SilentlyContinue) {
      Write-Host "Checking for latest changes from Git repository..."
      try {
        $gitOut = (git -C $sourceDir pull --ff-only 2>&1 | Out-String).Trim()
        Write-Host "  $gitOut"
      } catch {
        Write-Warning "Git pull skipped or encountered warning: $_"
      }
    }
  }

  $srcBin = Join-Path $sourceDir 'src'
  $srcPs1 = Join-Path $srcBin 'openconnectsg.ps1'
  $srcCmd = Join-Path $srcBin 'openconnectsg.cmd'
  $initPs1 = Join-Path $srcBin 'init-openconnectsg.ps1'
  $installPs1 = Join-Path $sourceDir 'install\install-openconnectsg.ps1'

  if (-not (Test-Path $srcPs1)) { throw "Required file not found: $srcPs1" }

  $newVer = $script:Version
  $vLine = Get-Content $srcPs1 -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\$script:Version\s*=\s*[''"]([^''"]+)[''"]' } | Select-Object -First 1
  if ($vLine -and $vLine -match '^\$script:Version\s*=\s*[''"]([^''"]+)[''"]') {
    $newVer = $matches[1]
  }

  Write-Host "Deploying openconnectsg $newVer to $binDir..."
  Copy-Item $srcPs1 $binDir -Force
  if (Test-Path $srcCmd)     { Copy-Item $srcCmd $binDir -Force }
  if (Test-Path $initPs1)    { Copy-Item $initPs1 $binDir -Force }
  if (Test-Path $installPs1) { Copy-Item $installPs1 $binDir -Force }

  $dateStr = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $marker = "version=$newVer`r`nsource=$sourceDir`r`ninstalled=$dateStr`r`n"
  [System.IO.File]::WriteAllText($installedFile, $marker, (New-Object System.Text.UTF8Encoding($false)))

  $profDir = Join-Path $ocRoot 'profiles'
  if (Test-Path $profDir) {
    Get-ChildItem -Path $profDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $errPath = Join-Path $_.FullName 'logs\err.log'
      if (Test-Path $errPath) {
        $sample = Get-Content $errPath -Tail 10 -ErrorAction SilentlyContinue
        if ($sample -match 'Unexpected pre-PPP packet header|GFtype\.heartbeat') {
          Write-Host "  Clearing legacy heartbeat logs from $($_.Name)..."
          Set-Content -Path $errPath -Value $null -Force
        }
      }
    }
  }

  $activeServices = @(Get-Service -Name openconnect* -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' })
  if ($activeServices.Count -gt 0) {
    foreach ($svc in $activeServices) {
      Write-Host "Restarting active service: $($svc.Name)..."
      Restart-Service -Name $svc.Name -Force
    }
  }

  Write-Host "Upgrade to openconnectsg $newVer completed successfully."
  return 0
}

# --- Service Daemon Runner (Internal entry point invoked by NSSM) ---
function Do-ServiceRun {
  param([string]$ServiceName)
  if ([string]::IsNullOrWhiteSpace($ServiceName)) {
    Write-Error "service-run requires a ServiceName argument."
    exit 1
  }
  $dir = Join-Path $root $ServiceName
  if (-not (Test-Path $dir)) {
    Write-Error "Profile directory not found: $dir"
    exit 1
  }
  $mutex = New-Object System.Threading.Mutex($false, "Global\$ServiceName")
  if (-not $mutex.WaitOne(0)) {
    Write-Error "Service $ServiceName is already running (Mutex held)."
    exit 1
  }
  try {
    Add-Type -AssemblyName System.Security
    $pwFile = Join-Path $dir 'pw.bin'
    $confFile = Join-Path $dir 'openconnect.conf'
    if (-not (Test-Path $pwFile))   { throw "Password artifact not found: $pwFile" }
    if (-not (Test-Path $confFile)) { throw "Configuration file not found: $confFile" }

    $enc = [System.IO.File]::ReadAllBytes($pwFile)
    $raw = [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, 'LocalMachine')
    $enc = $null
    $pw = [System.Text.Encoding]::Unicode.GetString($raw)
    [System.Array]::Clear($raw, 0, $raw.Length)

    $logsDir = Join-Path $dir 'logs'
    if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
    $errLog = Join-Path $logsDir 'err.log'
    $hbStatus = Join-Path $dir 'heartbeat.status'

    if (-not ('OpenConnectSg.StderrFilter' -as [type])) {
      $filterCs = @'
namespace OpenConnectSg {
  using System;
  using System.IO;
  using System.Text.RegularExpressions;
  using System.Threading;

  public static class StderrFilter {
    private static readonly Regex HeartbeatRegex = new Regex(
      @"Unexpected pre-PPP packet header|GFtype\.heartbeat|< 00[0-9a-fA-F]{2}:",
      RegexOptions.Compiled | RegexOptions.IgnoreCase
    );

    public static Thread StartProcessing(StreamReader reader, string errLogPath, string hbStatusPath) {
      Thread thread = new Thread(() => {
        long count = 0;
        string line;
        DateTime lastStatusWrite = DateTime.MinValue;

        using (StreamWriter errWriter = new StreamWriter(errLogPath, true, System.Text.Encoding.UTF8)) {
          errWriter.AutoFlush = true;

          while ((line = reader.ReadLine()) != null) {
            if (HeartbeatRegex.IsMatch(line)) {
              count++;
              DateTime now = DateTime.Now;
              if ((now - lastStatusWrite).TotalSeconds >= 2) {
                lastStatusWrite = now;
                try {
                  string content = string.Format(
                    "LastReceived={0:yyyy-MM-dd HH:mm:ss}\r\nCount={1}\r\nStatus=ALIVE\r\n",
                    now, count
                  );
                  File.WriteAllText(hbStatusPath, content, System.Text.Encoding.UTF8);
                } catch {}
              }
            } else {
              try {
                errWriter.WriteLine(line);
              } catch {}
            }
          }
        }

        if (count > 0) {
          try {
            string content = string.Format(
              "LastReceived={0:yyyy-MM-dd HH:mm:ss}\r\nCount={1}\r\nStatus=STOPPED\r\n",
              DateTime.Now, count
            );
            File.WriteAllText(hbStatusPath, content, System.Text.Encoding.UTF8);
          } catch {}
        }
      });
      thread.IsBackground = true;
      thread.Start();
      return thread;
    }
  }
}
'@
      Add-Type -TypeDefinition $filterCs -Language CSharp
    }

    $ocExe = Join-Path $ocRoot 'openconnect.exe'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ocExe
    $psi.Arguments = "--config `"$confFile`" --passwd-on-stdin"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $writer = New-Object System.IO.StreamWriter($proc.StandardInput.BaseStream, (New-Object System.Text.UTF8Encoding($false)))
    $writer.WriteLine($pw)
    $writer.Flush()
    $writer.Close()

    $hbThread = [OpenConnectSg.StderrFilter]::StartProcessing($proc.StandardError, $errLog, $hbStatus)

    $proc.WaitForExit()
    if ($hbThread) { $hbThread.Join(2000) }
    exit $proc.ExitCode
  } finally {
    $pw = $null
    $mutex.ReleaseMutex()
  }
}

function Show-Usage {
  $usage = @'
openconnectsg - Unified OpenConnect VPN Management CLI

Usage:
  openconnectsg                           List profiles (= list, * indicates default)
  openconnectsg list                      List all profiles and status
  openconnectsg status [<profile>]        Show detailed status of a profile
  openconnectsg connect [<profile>]       Connect to profile (single-tunnel enforcement)
  openconnectsg disconnect [<profile|all>] Disconnect profile (or all active tunnels)
  openconnectsg setup                     Add new profile via interactive wizard
  openconnectsg alias <profile> <alias>   Assign friendly alias to profile
  openconnectsg default <profile>         Set default profile
  openconnectsg remove <profile>          Remove profile and unregister Windows service
  openconnectsg upgrade [<source>]        Upgrade openconnectsg system binaries to latest version
  openconnectsg uninstall [<scope>]       Uninstall openconnectsg (scope: app or full)
  openconnectsg version                   Display tool version
  openconnectsg help                      Display this help screen

Aliases:
  ls -> list, up/start -> connect, down/stop -> disconnect, add -> setup, rm -> remove, un/purge -> uninstall, update -> upgrade

Identifier:
  <profile> = Index (#) | Alias | Account name | Service name substring
  <scope>   = app (openconnectsg only) | full (purge CLI & NSSM)
'@
  Write-Host $usage
}

# --- Entry point dispatch ---
$action = if ($args.Count -ge 1) { [string]$args[0] } else { 'list' }
$a1     = if ($args.Count -ge 2) { [string]$args[1] } else { $null }
$a2     = if ($args.Count -ge 3) { [string]$args[2] } else { $null }

$exitCode = 0
try {
  switch ($action.ToLower()) {
    'list'         { Show-List (Get-Profiles) }
    'ls'           { Show-List (Get-Profiles) }
    'status'       { $exitCode = Do-Status     (Get-Profiles) $a1 }
    'connect'      { $exitCode = Do-Connect    (Get-Profiles) $a1 }
    'start'        { $exitCode = Do-Connect    (Get-Profiles) $a1 }
    'up'           { $exitCode = Do-Connect    (Get-Profiles) $a1 }
    'disconnect'   { $exitCode = Do-Disconnect (Get-Profiles) $a1 }
    'stop'         { $exitCode = Do-Disconnect (Get-Profiles) $a1 }
    'down'         { $exitCode = Do-Disconnect (Get-Profiles) $a1 }
    'setup'        { $exitCode = Do-Setup @($args | Select-Object -Skip 1) }
    'add'          { $exitCode = Do-Setup @($args | Select-Object -Skip 1) }
    'install'      { $exitCode = Do-Setup @($args | Select-Object -Skip 1) } # Compatibility alias
    'alias'        { $exitCode = Do-Alias      (Get-Profiles) $a1 $a2 }
    'label'        { $exitCode = Do-Alias      (Get-Profiles) $a1 $a2 } # Compatibility alias
    'default'      { $exitCode = Do-Default    (Get-Profiles) $a1 }
    'remove'       { $exitCode = Do-Remove     (Get-Profiles) $a1 }
    'rm'           { $exitCode = Do-Remove     (Get-Profiles) $a1 }
    'delete'       { $exitCode = Do-Remove     (Get-Profiles) $a1 }
    'upgrade'      { $exitCode = Do-Upgrade    $a1 }
    'update'       { $exitCode = Do-Upgrade    $a1 }
    'uninstall'    { $exitCode = Do-Uninstall  $a1 }
    'un'           { $exitCode = Do-Uninstall  $a1 }
    'purge'        { $exitCode = Do-Uninstall  $a1 }
    'service-run'  { Do-ServiceRun $a1 } # Daemon runner invoked by Windows Service
    'version'      { Write-Host "openconnectsg $script:Version" }
    '-v'           { Write-Host "openconnectsg $script:Version" }
    '--version'    { Write-Host "openconnectsg $script:Version" }
    'help'         { Show-Usage }
    '-h'           { Show-Usage }
    '--help'       { Show-Usage }
    default        { Write-Host "Error: Unknown command '$action'"; Show-Usage; $exitCode = 2 }
  }
} catch {
  Write-Host "Error: $($_.Exception.Message)"
  $exitCode = 1
}
exit $exitCode

