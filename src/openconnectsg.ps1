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
$script:Version = '3.0.0'

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
    Write-Host "  Error Log: $root\$($t.Name)\logs\err.log"
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
  if ([string]::IsNullOrWhiteSpace($token)) { Show-List $profiles; return }
  $t = Resolve-Profile $profiles $token
  $s = Get-Service -Name $t.Name -ErrorAction SilentlyContinue
  $status = if ($s) { [string]$s.Status } else { 'N/A' }
  Write-Host ('{0}  {1}  {2}  {3}' -f $t.Name, $t.User, $t.Alias, $status)
}

function Do-Default {
  param($profiles, $token)
  $t = Resolve-Profile $profiles $token
  Set-Content $defaultFile $t.Name -NoNewline -Encoding ascii
  Write-Host "default = $($t.Name)"
  return 0
}

function Do-Alias {
  param($profiles, $token, $alias)
  if ([string]::IsNullOrWhiteSpace($alias)) { throw 'Please provide an alias. Syntax: openconnectsg alias <profile> <alias_name>' }
  $t = Resolve-Profile $profiles $token
  Set-Content (Join-Path (Join-Path $root $t.Name) 'label.txt') $alias -NoNewline -Encoding utf8
  Write-Host "alias '$alias' -> $($t.Name)"
  return 0
}

function Do-Remove {
  param($profiles, $token)
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

    $ocExe = Join-Path $ocRoot 'openconnect.exe'
    $pw | & $ocExe --config $confFile --passwd-on-stdin
    exit $LASTEXITCODE
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
  openconnectsg version                   Display tool version
  openconnectsg help                      Display this help screen

Aliases:
  ls -> list, up/start -> connect, down/stop -> disconnect, add -> setup, rm -> remove

Identifier:
  <profile> = Index (#) | Alias | Account name | Service name substring
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
