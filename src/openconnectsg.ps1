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
$script:Version = '0.1.2d'

$ocRoot      = 'C:\Program Files\OpenConnect'
$root        = Join-Path $ocRoot 'profiles'
$nssm        = 'C:\Program Files\nssm\nssm.exe'
$defaultFile = Join-Path $root 'default.txt'

function Show-Banner {
  param([string]$SubTitle = "Windows Background Daemon & DPAPI Automation Wrapper")
  Write-Host ""
  Write-Host "   ____                   ______                            __   _____       " -ForegroundColor Cyan
  Write-Host "  / __ \____  ___  ____  / ____/___  ____  ____  ___  _____/ /_ / ___/____ _ " -ForegroundColor Cyan
  Write-Host " / / / / __ \/ _ \/ __ \/ /   / __ \/ __ \/ __ \/ _ \/ ___/ __/ \__ \/ __ `/ " -ForegroundColor Cyan
  Write-Host "/ /_/ / /_/ /  __/ / / / /___/ /_/ / / / / / / /  __/ /__/ /_   ___/ / /_/ /  " -ForegroundColor Cyan
  Write-Host "\____/ .___/\___/_/ /_/\____/\____/_/ /_/_/ /_/\___/\___/\__/  /____/\__, /   " -ForegroundColor Cyan
  Write-Host "    /_/                                                             /____/    " -ForegroundColor Cyan
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "  OpenConnectSg :: $SubTitle (v$script:Version)" -ForegroundColor White
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host ""
}

function Show-Version {
  Show-Banner "System & Version Information"
  Write-Host "  Version       : openconnectsg $script:Version" -ForegroundColor Green
  Write-Host "  Binary Path   : $(Join-Path $ocRoot 'bin')" -ForegroundColor DarkCyan
  Write-Host "  Profiles Path : $root" -ForegroundColor DarkCyan
  Write-Host "  Repository    : https://github.com/sparklings/openconnectsg" -ForegroundColor DarkCyan
  Write-Host "  Documentation : https://github.com/sparklings/openconnectsg#readme" -ForegroundColor DarkCyan
  Write-Host ""
}

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
    Write-Host ""
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host "  OpenConnectSg :: Profiles" -ForegroundColor White
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host "  No registered profiles found. Run: openconnectsg setup" -ForegroundColor Yellow
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host ""
    return
  }
  Write-Host ""
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "  OpenConnectSg :: Profiles" -ForegroundColor White
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host ('  {0,-3} {1,-3} {2,-16} {3,-26} {4,-10} {5}' -f '#', 'DEF', 'USER', 'SERVER', 'ALIAS', 'STATUS') -ForegroundColor Cyan
  Write-Host " ------------------------------------------------------------------------------" -ForegroundColor DarkGray
  foreach ($p in $profiles) {
    $defMark = if ($p.IsDefault) { '*' } else { ' ' }
    $aliasStr = if ($p.Alias) { $p.Alias } else { '-' }
    $stColor = if ($p.Status -eq 'Running') { 'Green' } elseif ($p.Status -eq 'Stopped') { 'DarkGray' } else { 'Yellow' }
    Write-Host ('  {0,-3} {1,-3} {2,-16} {3,-26} {4,-10} ' -f $p.Index, $defMark, $p.User, $p.Server, $aliasStr) -NoNewline
    Write-Host $p.Status -ForegroundColor $stColor
  }
  Write-Host " ------------------------------------------------------------------------------" -ForegroundColor DarkGray
  if (Test-Path $defaultFile) {
    $defName = (Get-Content $defaultFile -Raw).Trim()
    Write-Host "  Default profile: $defName" -ForegroundColor DarkCyan
  }
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host ""
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
  $profConf = Join-Path (Join-Path $root $t.Name) 'openconnect.conf'
  if (Test-Path $profConf) {
    try {
      $cLines = @(Get-Content $profConf -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '^interface=' -and $_ -notmatch '^force-dpd=' })
      $isFortinet = $cLines | Where-Object { $_ -match '^protocol=fortinet' }
      if ($isFortinet -and -not ($cLines | Where-Object { $_ -match '^no-dtls' })) {
        $cLines += "no-dtls"
      }
      Set-Content -Path $profConf -Value $cLines -Encoding ascii
    } catch {}
  }

  Write-Host ""
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "  OpenConnectSg :: Connect" -ForegroundColor White
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host ""

  # Single active connection policy: disconnect any other active tunnels
  $otherRunning = @($profiles | Where-Object { $_.Name -ne $t.Name -and $_.Status -eq 'Running' })
  if ($otherRunning.Count -gt 0) {
    Write-Host " [1/2] Enforcing single-tunnel policy..." -ForegroundColor Cyan
    foreach ($p in $otherRunning) {
      Write-Host "   Disconnecting other active session: $($p.Name)..." -ForegroundColor Gray
      [void](Invoke-Nssm @('stop', $p.Name))
    }
    Write-Host "   Conflicting sessions closed." -ForegroundColor Green
    Write-Host ""
  }

  $cur = Get-Service -Name $t.Name -ErrorAction SilentlyContinue
  if ($cur -and [string]$cur.Status -eq 'Running') {
    Write-Host " Already connected: $($t.Name)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host "  Status: Running" -ForegroundColor Green
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host ""
    return 0
  }

  Write-Host " [2/2] Starting service..." -ForegroundColor Cyan
  Write-Host "   Target Service : $($t.Name)" -ForegroundColor White
  if ($cur -and [string]$cur.Status -ne 'Stopped' -and [string]$cur.Status -ne 'Running') {
    Write-Host "   Resetting previous session state ($($cur.Status))..." -ForegroundColor Gray
    [void](Invoke-Nssm @('stop', $t.Name))
    [void](Wait-ServiceStatus $t.Name 'Stopped' 10)
  }

  [void](Invoke-Nssm @('start', $t.Name))
  Set-Content $defaultFile $t.Name -NoNewline -Encoding ascii

  Write-Host "   Waiting for running status..." -ForegroundColor Gray
  $final = Wait-ServiceStatus $t.Name 'Running' 15
  if ($final -ne 'Running') {
    $errFile = "$root\$($t.Name)\logs\err.log"
    $outFile = "$root\$($t.Name)\logs\out.log"
    $combined = ""
    if (Test-Path $errFile) { $combined += "`n" + ((Get-Content $errFile -Tail 5 -ErrorAction SilentlyContinue) -join "`n") }
    if (Test-Path $outFile) { $combined += "`n" + ((Get-Content $outFile -Tail 5 -ErrorAction SilentlyContinue) -join "`n") }

    Write-Host ""
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host "  OpenConnectSg :: Connection Error" -ForegroundColor Red
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host " [Failure Reason]" -ForegroundColor Cyan
    if ($combined -match 'sslvpn_login_permission_denied|Permission denied') {
      Write-Host "   Authentication failed: VPN server returned 'Permission denied'." -ForegroundColor Yellow
      Write-Host "   Server message: sslvpn_login_permission_denied" -ForegroundColor Gray
      Write-Host ""
      Write-Host " [Possible Causes]" -ForegroundColor Cyan
      Write-Host "   - Server-side account authorization policy or user group restriction" -ForegroundColor White
      Write-Host "   - Invalid or expired credentials" -ForegroundColor White
    } elseif ($combined -match 'Too many bad login attempts') {
      Write-Host "   Authentication blocked: Too many bad login attempts." -ForegroundColor Yellow
      Write-Host ""
      Write-Host " [Possible Causes]" -ForegroundColor Cyan
      Write-Host "   - Temporary lock by firewall security policy. Wait a few minutes." -ForegroundColor White
    } elseif ($combined -match 'Failed to complete authentication|fgetws') {
      Write-Host "   Authentication failed: VPN server rejected credentials." -ForegroundColor Yellow
      Write-Host ""
      Write-Host " [Possible Causes]" -ForegroundColor Cyan
      Write-Host "   - Invalid password or prompt timeout." -ForegroundColor White
    } else {
      Write-Host "   Service failed to reach Running state (Current: $final)" -ForegroundColor Yellow
      if (-not [string]::IsNullOrWhiteSpace($combined.Trim())) {
        Write-Host "   $($combined.Trim())" -ForegroundColor Gray
      }
    }
    Write-Host ""
    Write-Host " [Log Files]" -ForegroundColor Cyan
    Write-Host "   $outFile" -ForegroundColor DarkCyan
    Write-Host "   $errFile" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host ""
    return 1
  }

  Write-Host "   Service reached Running status." -ForegroundColor Green
  Write-Host ""
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "  Status: Running" -ForegroundColor Green
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host ""
  return 0
}

function Do-Disconnect {
  param($profiles, $token)
  Write-Host ""
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "  OpenConnectSg :: Disconnect" -ForegroundColor White
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host ""

  if ([string]::IsNullOrWhiteSpace($token) -or $token -eq 'all') {
    $rc = 0
    $runningProfiles = @($profiles | Where-Object { $_.Status -eq 'Running' })
    if ($runningProfiles.Count -eq 0) {
      Write-Host "  No active tunnels are currently running." -ForegroundColor DarkGray
    } else {
      Write-Host " Stopping active tunnels:" -ForegroundColor Cyan
      foreach ($p in $runningProfiles) {
        Write-Host "   - $($p.Name) ... " -NoNewline
        [void](Invoke-Nssm @('stop', $p.Name))
        if ((Wait-ServiceStatus $p.Name 'Stopped' 15) -ne 'Stopped') {
          Write-Host "Failed to stop." -ForegroundColor Yellow
          $rc = 1
        } else {
          $pDir = Join-Path $root $p.Name
          $errPath = Join-Path $pDir 'logs\err.log'
          if (Test-Path $errPath) { try { Set-Content -Path $errPath -Value $null -Force } catch {} }
          $hbPath = Join-Path $pDir 'heartbeat.status'
          if (Test-Path $hbPath) { try { Set-Content -Path $hbPath -Value "LastReceived=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`nCount=0`r`nStatus=STOPPED`r`n" -Force } catch {} }
          Write-Host "Stopped." -ForegroundColor Green
        }
      }
    }
    Write-Host ""
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host "  Status: Disconnected" -ForegroundColor Green
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host ""
    return $rc
  }

  $t = Resolve-Profile $profiles $token
  Write-Host " Stopping tunnel:" -ForegroundColor Cyan
  Write-Host "   - $($t.Name) ... " -NoNewline
  [void](Invoke-Nssm @('stop', $t.Name))
  $final = Wait-ServiceStatus $t.Name 'Stopped' 15
  if ($final -ne 'Stopped') {
    Write-Host "Failed (Current: $final)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host "  Warning: Service did not stop gracefully." -ForegroundColor Yellow
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host ""
    return 1
  }
  # Clean up stale error logs and update heartbeat on graceful stop
  $pDir = Join-Path $root $t.Name
  $errPath = Join-Path $pDir 'logs\err.log'
  if (Test-Path $errPath) {
    try { Set-Content -Path $errPath -Value $null -Force } catch {}
  }
  $hbPath = Join-Path $pDir 'heartbeat.status'
  if (Test-Path $hbPath) {
    try { Set-Content -Path $hbPath -Value "LastReceived=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`nCount=0`r`nStatus=STOPPED`r`n" -Force } catch {}
  }

  Write-Host "Stopped." -ForegroundColor Green
  Write-Host ""
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "  Status: Disconnected" -ForegroundColor Green
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host ""
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

  Write-Host ""
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "  OpenConnectSg :: Profile Status" -ForegroundColor White
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host " [Profile Details]" -ForegroundColor Cyan
  Write-Host "   Name       : $($t.Name)" -ForegroundColor White
  Write-Host "   Index      : $($t.Index)" -ForegroundColor White
  Write-Host "   Alias      : $(if ($t.Alias) { $t.Alias } else { '(none)' })" -ForegroundColor White
  Write-Host "   User       : $($t.User)" -ForegroundColor White
  Write-Host "   Server     : $($t.Server)" -ForegroundColor White
  Write-Host "   Status     : $status" -ForegroundColor $(if ($status -eq 'Running') { 'Green' } else { 'DarkGray' })
  Write-Host "   Default    : $(if ($t.IsDefault) { 'Yes' } else { 'No' })" -ForegroundColor White

  $profDir = Join-Path $root $t.Name
  $hbFile = Join-Path $profDir 'heartbeat.status'
  if ($status -eq 'Running') {
    Write-Host ""
    Write-Host " [Heartbeat Monitor]" -ForegroundColor Cyan
    if (Test-Path $hbFile) {
      $hbRaw = Get-Content $hbFile -Raw -ErrorAction SilentlyContinue
      $lastRecv = if ($hbRaw -match 'LastReceived=([^\r\n]+)') { $matches[1].Trim() } else { $null }
      $hbCount  = if ($hbRaw -match 'Count=(\d+)') { [int]$matches[1].Trim() } else { 0 }
      $hbState  = if ($hbRaw -match 'Status=([^\r\n]+)') { $matches[1].Trim() } else { 'UNKNOWN' }
      if ($hbState -eq 'STARTING' -or $hbCount -eq 0) {
        Write-Host "   Status     : INITIALIZING (Awaiting first keepalive packet)" -ForegroundColor Yellow
      } elseif ($lastRecv) {
        try {
          $secAgo = [math]::Max(0, [int]((Get-Date) - [DateTime]::Parse($lastRecv)).TotalSeconds)
          if ($secAgo -le 30) {
            Write-Host "   Status     : ALIVE ($secAgo s ago, packets: $hbCount)" -ForegroundColor Green
          } elseif ($secAgo -le 90) {
            Write-Host "   Status     : IDLE ($secAgo s ago, packets: $hbCount)" -ForegroundColor Yellow
          } else {
            Write-Host "   Status     : STALE ($secAgo s ago, packets: $hbCount)" -ForegroundColor Red
          }
        } catch {
          Write-Host "   Status     : Recorded ($lastRecv, packets: $hbCount)" -ForegroundColor DarkCyan
        }
      } elseif ($hbState -eq 'STOPPED') {
        Write-Host "   Status     : STOPPED (Terminated)" -ForegroundColor Red
      }
    } else {
      Write-Host "   Status     : Waiting for keepalive packets..." -ForegroundColor DarkGray
    }
  }

  $errFile = Join-Path $profDir 'logs\err.log'
  $hasErr = $false
  if ($status -eq 'Stopped') {
    Write-Host ""
    Write-Host " [Recent Error]" -ForegroundColor Cyan
    Write-Host "   None (Service is stopped)" -ForegroundColor DarkGray
  } else {
    if (Test-Path $errFile) {
      $errLen = (Get-Item $errFile).Length
      if ($errLen -gt 0) {
        $recentErrLines = @(Get-Content $errFile -Tail 10 -ErrorAction SilentlyContinue | Where-Object {
          $_ -notmatch 'WARNING: Support for Wintun is experimental|install the TAP-Windows driver instead|Using Wintun device|https://www\.infradead\.org' -and -not [string]::IsNullOrWhiteSpace($_.Trim())
        })
        if ($recentErrLines.Count -gt 0) {
          $hasErr = $true
          Write-Host ""
          Write-Host " [Recent Error]" -ForegroundColor Red
          $recentErrLines | Select-Object -Last 3 | ForEach-Object {
            Write-Host "   $_" -ForegroundColor DarkRed
          }
        }
      }
    }
    if (-not $hasErr) {
      Write-Host ""
      Write-Host " [Recent Error]" -ForegroundColor Cyan
      Write-Host "   None (Logs are clean)" -ForegroundColor DarkGray
    }
  }

  Write-Host ""
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host ""
  return 0
}

function Do-Default {
  param($profiles, $token)
  if ([string]::IsNullOrWhiteSpace($token)) {
    if (Test-Path $defaultFile) {
      $def = (Get-Content $defaultFile -Raw).Trim()
      $hit = @($profiles | Where-Object { $_.Name -eq $def })
      if ($hit.Count -eq 1) {
        Write-Host ""
        Write-Host " ==============================================================================" -ForegroundColor DarkGray
        Write-Host "  OpenConnectSg :: Current Default Profile" -ForegroundColor White
        Write-Host " ==============================================================================" -ForegroundColor DarkGray
        Write-Host "   Default Profile : $($hit[0].Name)" -ForegroundColor White
        Write-Host "   Alias / User    : $(if ($hit[0].Alias) { $hit[0].Alias } else { '(none)' }) ($($hit[0].User))" -ForegroundColor DarkCyan
        Write-Host " ==============================================================================" -ForegroundColor DarkGray
        Write-Host ""
        return 0
      }
    }
    Write-Host "No default profile set. Syntax: openconnectsg default <profile>" -ForegroundColor Yellow
    return 1
  }
  $t = Resolve-Profile $profiles $token
  Set-Content $defaultFile $t.Name -NoNewline -Encoding ascii
  Write-Host ""
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "  OpenConnectSg :: Set Default Profile" -ForegroundColor White
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "   Default Profile : $($t.Name)" -ForegroundColor White
  Write-Host "   Alias / User    : $(if ($t.Alias) { $t.Alias } else { '(none)' }) ($($t.User))" -ForegroundColor Green
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host ""
  return 0
}

function Do-Alias {
  param($profiles, $token, $alias)
  if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($alias)) {
    throw 'Please provide both profile and alias. Syntax: openconnectsg alias <profile> <alias_name>'
  }
  $t = Resolve-Profile $profiles $token
  Set-Content (Join-Path (Join-Path $root $t.Name) 'label.txt') $alias -NoNewline -Encoding utf8
  Write-Host ""
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "  OpenConnectSg :: Assign Alias" -ForegroundColor White
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "   Target Profile  : $($t.Name)" -ForegroundColor White
  Write-Host "   Assigned Alias  : $alias" -ForegroundColor Green
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host ""
  return 0
}

function Do-Remove {
  param($profiles, $token)
  if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Please specify a profile to remove. Syntax: openconnectsg remove <profile>'
  }
  $t = Resolve-Profile $profiles $token

  Write-Host ""
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "  OpenConnectSg :: Remove Profile" -ForegroundColor White
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host " Target Profile:" -ForegroundColor Cyan
  Write-Host "   Name   : $($t.Name)" -ForegroundColor White
  Write-Host "   User   : $($t.User)" -ForegroundColor White
  Write-Host "   Status : $($t.Status)$(if ($t.Status -eq 'Running') { ' (will be stopped before removal)' })" -ForegroundColor White
  Write-Host ""
  Write-Host " This will stop the service, unregister it, and purge the profile directory." -ForegroundColor Yellow
  $ans = (Read-Host " Type 'yes' to proceed").Trim()
  if ($ans -ne 'yes') {
    Write-Host " Removal cancelled." -ForegroundColor DarkGray
    return 0
  }

  Write-Host ""
  Write-Host " Removing profile and service..." -ForegroundColor Cyan
  [void](Invoke-Nssm @('stop', $t.Name))
  Write-Host "   - Service stopped" -ForegroundColor Gray
  [void](Invoke-Nssm @('remove', $t.Name, 'confirm'))
  Write-Host "   - Service unregistered" -ForegroundColor Gray
  Remove-Item (Join-Path $root $t.Name) -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "   - Profile files purged" -ForegroundColor Gray

  if ((Test-Path $defaultFile) -and ((Get-Content $defaultFile -Raw).Trim() -eq $t.Name)) {
    Remove-Item $defaultFile -Force -ErrorAction SilentlyContinue
  }

  Write-Host ""
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "  Profile removed successfully." -ForegroundColor Green
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host ""
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

  Write-Host ""
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
  Write-Host "  OpenConnectSg :: Uninstaller & Purge Utility" -ForegroundColor White
  Write-Host " ==============================================================================" -ForegroundColor DarkGray
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
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host "  Full uninstallation completed successfully. All components removed." -ForegroundColor Green
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host ""
  } else {
    Write-Host "[3/3] Preserving OpenConnect CLI and NSSM binaries." -ForegroundColor Gray
    Write-Host ""
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host "  openconnectsg uninstallation completed successfully." -ForegroundColor Green
    Write-Host "  OpenConnect CLI and NSSM have been preserved." -ForegroundColor White
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host ""
  }

  return 0
}

function Compare-VersionString ($vCurrent, $vTarget) {
  if ($vCurrent -eq $vTarget) { return 0 }
  $pattern = '^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?([a-zA-Z]?.*)$'
  $m1 = [regex]::Match($vCurrent, $pattern)
  $m2 = [regex]::Match($vTarget, $pattern)
  if ($m1.Success -and $m2.Success) {
    for ($i = 1; $i -le 3; $i++) {
      $p1 = if ($m1.Groups[$i].Success) { [int]$m1.Groups[$i].Value } else { 0 }
      $p2 = if ($m2.Groups[$i].Success) { [int]$m2.Groups[$i].Value } else { 0 }
      if ($p2 -gt $p1) { return 1 }
      if ($p2 -lt $p1) { return -1 }
    }
    $suf1 = if ($m1.Groups[4].Success) { $m1.Groups[4].Value } else { '' }
    $suf2 = if ($m2.Groups[4].Success) { $m2.Groups[4].Value } else { '' }
    if ($suf2 -gt $suf1) { return 1 }
    if ($suf2 -lt $suf1) { return -1 }
    return 0
  }
  return [string]::Compare($vTarget, $vCurrent, [System.StringComparison]::OrdinalIgnoreCase)
}

function Do-Upgrade {
  param($arg1, $arg2)
  $binDir = 'C:\Program Files\OpenConnect\bin'
  $installedFile = Join-Path $binDir '.installed'

  $force = $false
  $token = $null
  foreach ($a in @($arg1, $arg2)) {
    if ([string]::IsNullOrWhiteSpace($a)) { continue }
    if ($a -match '^(-f|--force|/f)$') {
      $force = $true
    } elseif (-not $token) {
      $token = $a
    }
  }

  $wp = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  $isAdmin = $wp.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Host ""
    Write-Host " [Elevation Required]" -ForegroundColor Yellow
    Write-Host "   Administrative privileges are required to upgrade openconnectsg." -ForegroundColor White
    Write-Host "   Requesting elevation via User Account Control (UAC)..." -ForegroundColor DarkCyan
    $selfPath = $MyInvocation.MyCommand.Definition
    if ([string]::IsNullOrWhiteSpace($selfPath) -or -not (Test-Path $selfPath)) {
      $selfPath = Join-Path $binDir 'openconnectsg.ps1'
    }
    $argStr = "-NoProfile -ExecutionPolicy Bypass -Command `"& '$selfPath' upgrade"
    if (-not [string]::IsNullOrWhiteSpace($token)) { $argStr += " '$token'" }
    if ($force) { $argStr += " --force" }
    $argStr += "; Write-Host ''; Read-Host 'Press Enter to close this window...'`""

    try {
      $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $argStr -PassThru
      Write-Host "   UAC prompt initiated (Process ID: $($p.Id)). Please approve to continue." -ForegroundColor DarkCyan
      Write-Host ""
      return 0
    } catch {
      try {
        $sh = New-Object -ComObject Shell.Application
        $sh.ShellExecute("powershell.exe", $argStr, "", "runas", 1)
        Write-Host "   UAC prompt initiated via ShellExecute. Please approve to continue." -ForegroundColor DarkCyan
        Write-Host ""
        return 0
      } catch {
        throw "Failed to elevate process. Please run 'openconnectsg upgrade' from an administrator PowerShell console."
      }
    }
  }

  Show-Banner "System Upgrade & Maintenance"

  $repoUrl = 'https://github.com/sparklings/openconnectsg.git'
  $zipUrl  = 'https://github.com/sparklings/openconnectsg/archive/refs/heads/main.zip'
  $tempWorkDir = Join-Path $env:TEMP ("openconnectsg_upgrade_" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tempWorkDir -Force | Out-Null
  $sourceDir = $null

  try {
    Write-Host " [Step 1/3] Fetching latest release package..." -ForegroundColor Cyan
    Write-Host ""

    # 1. If explicit local directory path provided and valid
    if (-not [string]::IsNullOrWhiteSpace($token) -and (Test-Path $token) -and (Test-Path (Join-Path $token 'src\openconnectsg.ps1'))) {
      $sourceDir = (Resolve-Path $token).Path
      Write-Host "   Source Type       : Local Directory" -ForegroundColor White
      Write-Host "   Source Path       : $sourceDir" -ForegroundColor DarkCyan
      Write-Host "   Status            : Local source directory verified." -ForegroundColor Green
    } else {
      # 2. Try git clone first if git command exists
      $hasGit = $null -ne (Get-Command git -ErrorAction SilentlyContinue)
      if ($hasGit) {
        Write-Host "   Source Type       : Remote Git Repository" -ForegroundColor White
        Write-Host "   Repository URL    : $repoUrl" -ForegroundColor DarkCyan
        Write-Host "   Cloning repository (depth 1)..." -ForegroundColor Gray
        $cloneDir = Join-Path $tempWorkDir 'repo'
        try {
          $gitProc = Start-Process -FilePath "git" -ArgumentList "clone", "--depth", "1", "--quiet", $repoUrl, "`"$cloneDir`"" -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
          if ($gitProc -and $gitProc.ExitCode -eq 0 -and (Test-Path (Join-Path $cloneDir 'src\openconnectsg.ps1'))) {
            $sourceDir = $cloneDir
            Write-Host "   Status            : Repository cloned successfully." -ForegroundColor Green
          } else {
            Write-Host "   Notice            : Git clone unavailable or failed. Switching to direct HTTPS archive." -ForegroundColor Yellow
          }
        } catch {
          Write-Host "   Notice            : Git clone error. Switching to direct HTTPS archive." -ForegroundColor Yellow
        }
      }

      # 3. Fallback to HTTPS archive download if git is not available or clone failed
      if ([string]::IsNullOrWhiteSpace($sourceDir)) {
        if (-not $hasGit) {
          Write-Host "   Source Type       : Direct HTTPS Archive (Git not detected)" -ForegroundColor White
        }
        Write-Host "   Download URL      : $zipUrl" -ForegroundColor DarkCyan
        Write-Host "   Downloading package archive..." -ForegroundColor Gray
        $zipFile = Join-Path $tempWorkDir 'openconnectsg-main.zip'
        $extractDir = Join-Path $tempWorkDir 'extracted'

        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        try {
          Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing -TimeoutSec 30
        } catch {
          $wc = New-Object System.Net.WebClient
          $wc.DownloadFile($zipUrl, $zipFile)
        }

        if (-not (Test-Path $zipFile)) {
          throw "Failed to download update archive from GitHub."
        }

        Write-Host "   Extracting package files..." -ForegroundColor Gray
        Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force
        $candidateDir = Join-Path $extractDir 'openconnectsg-main'
        if (-not (Test-Path (Join-Path $candidateDir 'src\openconnectsg.ps1'))) {
          $sub = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
          if ($sub) { $candidateDir = $sub.FullName }
        }

        if (Test-Path (Join-Path $candidateDir 'src\openconnectsg.ps1')) {
          $sourceDir = $candidateDir
          Write-Host "   Status            : Package archive downloaded and extracted successfully." -ForegroundColor Green
        } else {
          throw "Failed to locate source files in extracted archive."
        }
      }
    }

    $srcBin = Join-Path $sourceDir 'src'
    $srcPs1 = Join-Path $srcBin 'openconnectsg.ps1'
    $srcCmd = Join-Path $srcBin 'openconnectsg.cmd'
    $initPs1 = Join-Path $srcBin 'init-openconnectsg.ps1'
    $installPs1 = Join-Path $sourceDir 'install\install-openconnectsg.ps1'

    if (-not (Test-Path $srcPs1)) { throw "Required file not found in source: $srcPs1" }

    # Detect new version string
    $newVer = $script:Version
    $vLine = Get-Content $srcPs1 -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\$script:Version\s*=\s*[''"]([^''"]+)[''"]' } | Select-Object -First 1
    if ($vLine -and $vLine -match '^\$script:Version\s*=\s*[''"]([^''"]+)[''"]') {
      $newVer = $matches[1]
    }

    Write-Host ""
    Write-Host " [Step 2/3] Deploying updated binaries..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   Target Directory  : $binDir" -ForegroundColor White
    Write-Host "   Target Version    : openconnectsg $newVer (Current: $script:Version)" -ForegroundColor White

    $cmp = Compare-VersionString $script:Version $newVer
    if ($cmp -le 0 -and -not $force) {
      Write-Host "   Status            : Already up to date. No upgrade required." -ForegroundColor Green
      Write-Host ""
      Write-Host " ==============================================================================" -ForegroundColor DarkGray
      Write-Host "  Already up to date! (openconnectsg $script:Version)" -ForegroundColor Green
      Write-Host "  No changes were made to binaries or active background services." -ForegroundColor White
      Write-Host " ==============================================================================" -ForegroundColor DarkGray
      Write-Host ""
      return 0
    }

    if ($force -and $cmp -le 0) {
      Write-Host "   Notice            : Force flag specified. Reinstalling version $newVer..." -ForegroundColor Yellow
    }

    Write-Host "   Deploying scripts..." -ForegroundColor Gray

    Copy-Item $srcPs1 $binDir -Force
    if (Test-Path $srcCmd)     { Copy-Item $srcCmd $binDir -Force }
    if (Test-Path $initPs1)    { Copy-Item $initPs1 $binDir -Force }
    if (Test-Path $installPs1) { Copy-Item $installPs1 $binDir -Force }

    $dateStr = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $marker = "version=$newVer`r`nsource=https://github.com/sparklings/openconnectsg`r`ninstalled=$dateStr`r`n"
    [System.IO.File]::WriteAllText($installedFile, $marker, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "   Core scripts updated successfully." -ForegroundColor Green

    $profDir = Join-Path $ocRoot 'profiles'
    if (Test-Path $profDir) {
      Get-ChildItem -Path $profDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $errPath = Join-Path $_.FullName 'logs\err.log'
        if (Test-Path $errPath) {
          $sample = Get-Content $errPath -Tail 10 -ErrorAction SilentlyContinue
          if ($sample -match 'Unexpected pre-PPP packet header|GFtype\.heartbeat') {
            Write-Host "   Purging legacy heartbeat log from $($_.Name)..." -ForegroundColor Gray
            Set-Content -Path $errPath -Value $null -Force
          }
        }
        $confPath = Join-Path $_.FullName 'openconnect.conf'
        if (Test-Path $confPath) {
          $cLines = @(Get-Content $confPath -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '^interface=' -and $_ -notmatch '^force-dpd=' })
          $isFortinet = $cLines | Where-Object { $_ -match '^protocol=fortinet' }
          if ($isFortinet -and -not ($cLines | Where-Object { $_ -match '^no-dtls' })) {
            $cLines += "no-dtls"
          }
          Set-Content -Path $confPath -Value $cLines -Encoding ascii
        }
      }
    }
    Write-Host "   Status            : Binaries deployed and profile configurations sanitized." -ForegroundColor Green

    Write-Host ""
    Write-Host " [Step 3/3] Synchronizing background services..." -ForegroundColor Cyan
    Write-Host ""
    $activeServices = @(Get-Service -Name openconnect* -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' })
    if ($activeServices.Count -gt 0) {
      foreach ($svc in $activeServices) {
        Write-Host "   Restarting active service : $($svc.Name)..." -ForegroundColor White
        Restart-Service -Name $svc.Name -Force -WarningAction SilentlyContinue
        Write-Host "   Service state             : Running (active)" -ForegroundColor Green
      }
    } else {
      Write-Host "   No active VPN services running. Service restart not required." -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host "  Upgrade completed successfully! (openconnectsg $newVer)" -ForegroundColor Green
    Write-Host " ==============================================================================" -ForegroundColor DarkGray
    Write-Host ""
    return 0
  } finally {
    if (Test-Path $tempWorkDir) {
      Remove-Item -Path $tempWorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
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

    # Sanitize configuration: strip problematic interface= override causing Wintun adapter creation timeout
    try {
      $confLines = @(Get-Content $confFile -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '^interface=' -and $_ -notmatch '^force-dpd=' })
      $isFortinet = $confLines | Where-Object { $_ -match '^protocol=fortinet' }
      if ($isFortinet -and -not ($confLines | Where-Object { $_ -match '^no-dtls' })) {
        $confLines += "no-dtls"
      }
      Set-Content -Path $confFile -Value $confLines -Encoding ascii
    } catch {}

    # Clean up any stale/ghost Wintun devices in error state to prevent CM_PROB_DISABLED_SERVICE (0x20) / timeout (0x102)
    try {
      Get-PnpDevice -Class Net -ErrorAction SilentlyContinue | Where-Object {
        $_.InstanceId -like "*WINTUN*" -and ($_.Status -ne 'OK' -or $_.Problem -ne 'CM_PROB_NONE')
      } | ForEach-Object {
        & pnputil /remove-device $_.InstanceId 2>&1 | Out-Null
      }
    } catch {}

    $enc = [System.IO.File]::ReadAllBytes($pwFile)
    $raw = [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, 'LocalMachine')
    $enc = $null
    $pw = [System.Text.Encoding]::Unicode.GetString($raw)
    [System.Array]::Clear($raw, 0, $raw.Length)

    $logsDir = Join-Path $dir 'logs'
    if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
    $errLog = Join-Path $logsDir 'err.log'
    if (Test-Path $errLog) {
      try { Set-Content -Path $errLog -Value $null -Force } catch {}
    }
    $hbStatus = Join-Path $dir 'heartbeat.status'
    try {
      Set-Content -Path $hbStatus -Value "LastReceived=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`nCount=0`r`nStatus=STARTING`r`n" -Force
    } catch {}

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

    public static Thread StartProcessing(StreamReader reader, string hbStatusPath) {
      Thread thread = new Thread(() => {
        try {
          long count = 0;
          string line;
          DateTime lastStatusWrite = DateTime.MinValue;

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
                Console.Error.WriteLine(line);
              } catch {}
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
        } catch {}
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
    # Keep stdin stream open while openconnect is running to prevent EOF logout

    $hbThread = [OpenConnectSg.StderrFilter]::StartProcessing($proc.StandardError, $hbStatus)

    $proc.WaitForExit()
    if ($hbThread) { [void]$hbThread.Join(2000) }
    try { $writer.Close() } catch {}
    exit $proc.ExitCode
  } finally {
    $pw = $null
    try { $mutex.ReleaseMutex() } catch {}
  }
}

function Show-Usage {
  Show-Banner "Command Line Interface Reference"
  $usage = @'
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
  openconnectsg upgrade [<source>] [--force] Upgrade openconnectsg system binaries (skip if current)
  openconnectsg uninstall [<scope>]       Uninstall openconnectsg (scope: app or full)
  openconnectsg version                   Display tool version and system details
  openconnectsg banner                    Display welcome ASCII banner
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
    'upgrade'      { $exitCode = Do-Upgrade    $a1 $a2 }
    'update'       { $exitCode = Do-Upgrade    $a1 $a2 }
    'uninstall'    { $exitCode = Do-Uninstall  $a1 }
    'un'           { $exitCode = Do-Uninstall  $a1 }
    'purge'        { $exitCode = Do-Uninstall  $a1 }
    'service-run'  { Do-ServiceRun $a1 } # Daemon runner invoked by Windows Service
    'version'      { Show-Version }
    'banner'       { Show-Banner }
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

