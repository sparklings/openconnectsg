#Requires -Version 5.1
<#
.SYNOPSIS
  openconnectsg-tray - System tray GUI for OpenConnectSg.
.DESCRIPTION
  Small WinForms window + notification-area icon on top of the openconnectsg CLI.
  - Connect / disconnect profiles (calls `openconnectsg.ps1 connect|disconnect`)
  - Close button hides the window to the tray
  - Shows which network each connection uses: the physical adapter that reaches
    the VPN gateway, the tunnel IP, the subnets routed into the tunnel, and where
    all other traffic goes. A route lookup box answers "which network does X use?"
  - Optional auto-start at Windows logon (scheduled task, highest privileges, no UAC prompt)
.NOTES
  Save encoding: UTF-8 with BOM, CRLF line endings.
  Usage: openconnectsg tray   (or run this file with powershell -File)
  -Hidden : start minimized to the tray (used by the logon task)
#>
param([switch]$Hidden)
$ErrorActionPreference = 'Stop'

$programFiles = if ([string]::IsNullOrWhiteSpace($env:ProgramFiles)) { 'C:\Program Files' } else { $env:ProgramFiles }
$ocRoot      = Join-Path $programFiles 'OpenConnect'
$root        = Join-Path $ocRoot 'profiles'
$binDir      = Join-Path $ocRoot 'bin'
$defaultFile = Join-Path $root 'default.txt'
$cliPs1      = Join-Path $PSScriptRoot 'openconnectsg.ps1'
if (-not (Test-Path $cliPs1)) { $cliPs1 = Join-Path $binDir 'openconnectsg.ps1' }
$taskName    = 'OpenConnectSg Tray'

# --- Elevation: service start/stop needs admin. Re-launch elevated once. ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $env:OCSG_TRAY_NOELEVATE) {
  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
  if ($Hidden) { $argList += '-Hidden' }
  try { Start-Process powershell.exe -Verb RunAs -ArgumentList $argList } catch { }
  exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if (-not ('OcsgTray.Native' -as [type])) {
  Add-Type -Namespace OcsgTray -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr handle);
'@
}
[void][OcsgTray.Native]::ShowWindow([OcsgTray.Native]::GetConsoleWindow(), 0)
[void][OcsgTray.Native]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()
# An exception escaping a WinForms event handler would end the process; log it and keep running.
$script:errLog = Join-Path $env:TEMP 'openconnectsg-tray-error.log'
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    param($s, $e)
    try { [System.IO.File]::AppendAllText($script:errLog, "$(Get-Date -Format 's') $($e.Exception | Out-String)`r`n") } catch { }
  })

# --- Single instance: a second launch just brings the existing window to front ---
$created = $false
$script:mutex = New-Object System.Threading.Mutex($true, 'Local\OpenConnectSgTray', [ref]$created)
$script:showEvt = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\OpenConnectSgTrayShow')
if (-not $created) { [void]$script:showEvt.Set(); exit }

# ============================================================================
#  Data helpers
# ============================================================================
function Get-ConfValue($lines, $key) {
  $l = $lines | Where-Object { $_ -match "^$key=" } | Select-Object -First 1
  if ($l) { return ($l -replace "^$key=", '').Trim() }
  return ''
}

function Get-TrayProfiles {
  $list = New-Object System.Collections.ArrayList
  if (-not (Test-Path $root)) { return ,$list }
  $def = ''
  if (Test-Path $defaultFile) { $def = (Get-Content $defaultFile -Raw).Trim() }
  foreach ($d in (Get-ChildItem -Path $root -Directory | Sort-Object Name)) {
    $conf = Join-Path $d.FullName 'openconnect.conf'
    if (-not (Test-Path $conf)) { continue }
    $c = @(Get-Content $conf -ErrorAction SilentlyContinue)
    $server = Get-ConfValue $c 'server'
    $hostName = $server; $port = 443
    try { $u = [Uri]$server; $hostName = $u.Host; $port = $u.Port } catch { }
    $proto = Get-ConfValue $c 'protocol'; if (-not $proto) { $proto = 'anyconnect' }
    $alias = ''; $lf = Join-Path $d.FullName 'label.txt'
    if (Test-Path $lf) { $alias = (Get-Content $lf -Raw).Trim() }
    $user = Get-ConfValue $c 'user'
    $uf = Join-Path $d.FullName 'user.txt'
    if (-not $user -and (Test-Path $uf)) { $user = (Get-Content $uf -Raw).Trim() }
    $svc = Get-Service -Name $d.Name -ErrorAction SilentlyContinue
    [void]$list.Add([pscustomobject]@{
      Name      = $d.Name
      Dir       = $d.FullName
      Host      = $hostName
      Port      = $port
      Proto     = if ($proto -eq 'anyconnect') { 'Cisco' } elseif ($proto -eq 'fortinet') { 'Fortinet' } else { $proto }
      User      = $user
      Alias     = $alias
      Display   = if ($alias) { $alias } else { "$user@$hostName" }
      SvcStatus = if ($svc) { [string]$svc.Status } else { 'N/A' }
      IsDefault = ($d.Name -eq $def)
    })
  }
  return ,$list
}

# The tunnel adapter is "OpenConnect Tunnel", named after the gateway host.
# Uses the .NET API (a few ms) instead of Get-NetAdapter (~200 ms) since it runs on every poll.
function Get-TunnelAdapter($p) {
  $all = @([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object {
      $_.Description -like 'OpenConnect Tunnel*' -and $_.OperationalStatus -eq 'Up' })
  $m = $all | Where-Object { $_.Name -eq $p.Host -or $_.Name -like "$($p.Host) *" } | Select-Object -First 1
  if (-not $m -and $all.Count -eq 1) { $m = $all[0] }
  if (-not $m) { return $null }
  $idx = 0
  try { $idx = $m.GetIPProperties().GetIPv4Properties().Index } catch { }
  return [pscustomobject]@{ Name = $m.Name; ifIndex = $idx }
}

# Connected = service running AND tunnel adapter up with an address.
function Get-ConnState($p) {
  if ($p.SvcStatus -ne 'Running') {
    if ($p.SvcStatus -match 'Pending') { return 'Connecting' }
    return 'Disconnected'
  }
  $a = Get-TunnelAdapter $p
  if ($a) { return 'Connected' }
  return 'Connecting'
}

function Get-StateText($s) {
  switch ($s) { 'Connected' { '연결됨' } 'Connecting' { '연결 중…' } default { '끊김' } }
}

function Resolve-IPv4($h) {
  $ip = $null
  if ([System.Net.IPAddress]::TryParse($h, [ref]$ip)) { return $ip.ToString() }
  try {
    $a = [System.Net.Dns]::GetHostAddresses($h) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
    if ($a) { return $a.ToString() }
  } catch { }
  return $null
}

# Which local adapter / network a destination IP leaves through.
function Get-PathTo($ip) {
  try {
    $r = @(Find-NetRoute -RemoteIPAddress $ip -ErrorAction Stop)
    $route = $r | Where-Object { $_.PSObject.Properties['NextHop'] } | Select-Object -First 1
    $addr  = $r | Where-Object { $_.PSObject.Properties['IPAddress'] } | Select-Object -First 1
    if (-not $route) { return $null }
    $ad  = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
    $net = Get-NetConnectionProfile -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue | Select-Object -First 1
    $isVpn = $ad -and $ad.InterfaceDescription -like 'OpenConnect Tunnel*'
    return [pscustomobject]@{
      Alias   = $route.InterfaceAlias
      Desc    = if ($ad) { $ad.InterfaceDescription } else { '' }
      NetName = if ($net) { $net.Name } else { '' }
      Source  = if ($addr) { $addr.IPAddress } else { '' }
      NextHop = $route.NextHop
      Prefix  = $route.DestinationPrefix
      IsVpn   = [bool]$isVpn
    }
  } catch { return $null }
}

function Format-Path($pt) {
  if (-not $pt) { return '경로를 찾을 수 없음' }
  $name = $pt.Alias
  if ($pt.NetName -and $pt.NetName -ne $pt.Alias) { $name += " [$($pt.NetName)]" }
  $hop = if ($pt.NextHop -and $pt.NextHop -ne '0.0.0.0') { " → 게이트웨이 $($pt.NextHop)" } else { ' (직접 연결)' }
  $tag = if ($pt.IsVpn) { 'VPN 터널' } else { '일반 네트워크' }
  return "$tag · $name · 출발 IP $($pt.Source)$hop"
}

function Get-TunnelRoutes($ad) {
  $ips = @(Get-NetIPAddress -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
  $own = @($ips | ForEach-Object { "$($_.IPAddress)/32" })
  $onlink = @($ips | ForEach-Object {
      $b = [System.Net.IPAddress]::Parse($_.IPAddress).GetAddressBytes(); [Array]::Reverse($b)
      $v = [BitConverter]::ToUInt32($b, 0)
      $mask = if ($_.PrefixLength -eq 0) { 0 } else { [uint32](([uint64]4294967295 -shl (32 - $_.PrefixLength)) -band 4294967295) }
      $nb = [BitConverter]::GetBytes([uint32]($v -band $mask)); [Array]::Reverse($nb)
      "$([System.Net.IPAddress]::new($nb))/$($_.PrefixLength)"
    })
  $routes = @(Get-NetRoute -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
      $d = $_.DestinationPrefix
      $d -ne '255.255.255.255/32' -and $d -ne '224.0.0.0/4' -and
      -not ($d -like '*.255/32') -and ($own -notcontains $d) -and ($onlink -notcontains $d)
    } | ForEach-Object { $_.DestinationPrefix } | Sort-Object -Unique)
  # sort numerically by network address
  $routes = @($routes | Sort-Object { $o = ($_ -split '/')[0] -split '\.'; '{0:D3}{1:D3}{2:D3}{3:D3}' -f [int]$o[0], [int]$o[1], [int]$o[2], [int]$o[3] })
  return [pscustomobject]@{ IPs = $ips; Routes = $routes }
}

#  Route hierarchy: groups the tunnel routes by containment under private ranges
#  (10/8, 172.16/12, 192.168/16) or their first octet, drawn as a text tree.
function ConvertTo-Net([string]$prefix) {
  $parts = $prefix -split '/'
  $b = [System.Net.IPAddress]::Parse($parts[0]).GetAddressBytes(); [Array]::Reverse($b)
  $len = [int]$parts[1]
  $mask = if ($len -eq 0) { [uint32]0 } else { [uint32](([uint64]4294967295 -shl (32 - $len)) -band 4294967295) }
  return [pscustomobject]@{ Prefix = $prefix; Net = [uint32]([BitConverter]::ToUInt32($b, 0) -band $mask); Len = $len; Mask = $mask }
}

function Test-NetContains($outer, $inner) {
  return $outer.Len -le $inner.Len -and (([uint32]($inner.Net -band $outer.Mask)) -eq $outer.Net)
}

function Get-RangeHint($n) {
  $o = $n.Prefix.Split('/')[0].Split('.')
  switch ($n.Len) {
    32 { return '단일 호스트' }
    24 { return "$($o[0]).$($o[1]).$($o[2]).x" }
    16 { return "$($o[0]).$($o[1]).x.x" }
    8  { return "$($o[0]).x.x.x" }
  }
  $last = [uint32]($n.Net -bor (-bnot $n.Mask -band 4294967295))
  $lb = [BitConverter]::GetBytes($last); [Array]::Reverse($lb)
  return "$($n.Prefix.Split('/')[0]) ~ $([System.Net.IPAddress]::new($lb))"
}

function Format-RouteTree([string[]]$routes) {
  $nodes = @($routes | ForEach-Object { ConvertTo-Net $_ } | Sort-Object Len, Net)
  # Virtual top-level groups
  $groups = New-Object System.Collections.ArrayList
  foreach ($g in @(@('10.0.0.0/8', '사설'), @('172.16.0.0/12', '사설'), @('192.168.0.0/16', '사설'))) {
    $gn = ConvertTo-Net $g[0]
    if ($nodes | Where-Object { Test-NetContains $gn $_ }) { [void]$groups.Add([pscustomobject]@{ N = $gn; Kind = $g[1] }) }
  }
  foreach ($n in $nodes) {
    if ($groups | Where-Object { Test-NetContains $_.N $n }) { continue }
    $first = "$($n.Prefix.Split('.')[0]).0.0.0/8"
    if (-not ($groups | Where-Object { $_.N.Prefix -eq $first })) {
      [void]$groups.Add([pscustomobject]@{ N = (ConvertTo-Net $first); Kind = '공인' })
    }
  }
  $groups = @($groups | Sort-Object { $_.N.Net })

  $tree = @{}   # prefix -> children list
  $all = @()
  foreach ($g in $groups) {
    $isRoute = [bool]($nodes | Where-Object { $_.Prefix -eq $g.N.Prefix })
    $all += [pscustomobject]@{ N = $g.N; Virtual = -not $isRoute; Kind = $g.Kind }
  }
  foreach ($n in $nodes) {
    if ($all | Where-Object { $_.N.Prefix -eq $n.Prefix }) { continue }
    $all += [pscustomobject]@{ N = $n; Virtual = $false; Kind = '' }
  }
  # Bundle 2+ subnets sharing the same /16 (when no /16 route exists) under a [x.y.0.0/16] node
  $by16 = $nodes | Where-Object { $_.Len -gt 16 } | Group-Object { $o = $_.Prefix.Split('.'); "$($o[0]).$($o[1]).0.0/16" }
  foreach ($g in $by16) {
    if ($g.Count -lt 2) { continue }
    $n16 = ConvertTo-Net $g.Name
    if ($all | Where-Object { $_.N.Len -le 16 -and $_.N.Len -gt 8 -and -not $_.Virtual -and (Test-NetContains $_.N $n16) }) { continue }
    $all += [pscustomobject]@{ N = $n16; Virtual = $true; Kind = '' }
  }
  # parent = deepest other node that contains it (a public /8 bundle never holds a private range)
  $roots = @()
  foreach ($x in $all) {
    $parent = $all | Where-Object { $_ -ne $x -and $_.N.Len -lt $x.N.Len -and (Test-NetContains $_.N $x.N) -and
        -not ($_.Kind -eq '공인' -and $x.Kind -eq '사설') -and
        -not ($_.Kind -eq '공인' -and ($all | Where-Object { $_.Kind -eq '사설' -and (Test-NetContains $_.N $x.N) })) } |
      Sort-Object { $_.N.Len } -Descending | Select-Object -First 1
    if ($parent) {
      if (-not $tree.ContainsKey($parent.N.Prefix)) { $tree[$parent.N.Prefix] = @() }
      $tree[$parent.N.Prefix] += $x
    } else { $roots += $x }
  }

  $out = New-Object System.Collections.ArrayList
  $label = {
    param($x)
    $hint = Get-RangeHint $x.N
    if ($x.Virtual) { "[$($x.N.Prefix)]  $("$($x.Kind) $hint".Trim())" }
    elseif ($x.Kind) { "$($x.N.Prefix)  ($($x.Kind) $hint 전체)" }
    else { "$($x.N.Prefix)  ($hint)" }
  }
  $walk = $null
  $walk = {
    param($x, [string]$indent, [bool]$isLast, [bool]$isRoot)
    if ($isRoot) { [void]$out.Add((& $label $x)); $childIndent = '' }
    else {
      $branch = if ($isLast) { '└─ ' } else { '├─ ' }
      [void]$out.Add("$indent$branch$(& $label $x)")
      $childIndent = $indent + $(if ($isLast) { '   ' } else { '│  ' })
    }
    $kids = @($tree[$x.N.Prefix] | Where-Object { $_ } | Sort-Object { $_.N.Net }, { $_.N.Len })
    for ($k = 0; $k -lt $kids.Count; $k++) { & $walk $kids[$k] $childIndent ($k -eq $kids.Count - 1) $false }
  }
  foreach ($r in ($roots | Sort-Object { $_.N.Net })) { & $walk $r '' $true $true }
  return $out
}

function Get-NetworkReport($p) {
  if (-not $p) { return '프로필을 선택하세요.' }
  $sb = New-Object System.Text.StringBuilder
  $state = Get-ConnState $p
  [void]$sb.AppendLine("■ $($p.Display)   ($($p.Proto) · $($p.Host):$($p.Port))")
  [void]$sb.AppendLine("  상태: $(Get-StateText $state)")
  [void]$sb.AppendLine('')

  $gw = Resolve-IPv4 $p.Host
  [void]$sb.AppendLine('▶ VPN 서버까지 사용하는 네트워크')
  if ($gw) { [void]$sb.AppendLine("  $(Format-Path (Get-PathTo $gw))") }
  else { [void]$sb.AppendLine("  $($p.Host) 주소를 확인할 수 없음 (DNS)") }
  [void]$sb.AppendLine('')

  $ad = if ($state -ne 'Disconnected') { Get-TunnelAdapter $p } else { $null }
  if ($ad) {
    $t = Get-TunnelRoutes $ad
    $ipStr = ($t.IPs | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }) -join ', '
    [void]$sb.AppendLine("▶ VPN 터널 어댑터: $($ad.Name)  (내 VPN IP: $ipStr)")
    $dns = @((Get-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
    if ($dns.Count -gt 0) { [void]$sb.AppendLine("  VPN DNS: $($dns -join ', ')") }
    $full = $t.Routes | Where-Object { $_ -eq '0.0.0.0/0' -or $_ -eq '0.0.0.0/1' -or $_ -eq '128.0.0.0/1' }
    [void]$sb.AppendLine('')
    if ($full) {
      [void]$sb.AppendLine('▶ 모든 트래픽이 VPN으로 갑니다 (Full tunnel)')
    } else {
      [void]$sb.AppendLine("▶ VPN으로 가는 대역 (Split tunnel, $($t.Routes.Count)개)")
      for ($i = 0; $i -lt $t.Routes.Count; $i += 4) {
        $row = @($t.Routes[$i..([Math]::Min($i + 3, $t.Routes.Count - 1))] | ForEach-Object { $_.PadRight(20) })
        [void]$sb.AppendLine(('  ' + ($row -join '')).TrimEnd())
      }
      [void]$sb.AppendLine('')
      $inet = Get-PathTo '8.8.8.8'
      $other = if ($inet) { Format-Path $inet } else { '경로 없음' }
      [void]$sb.AppendLine('▶ 그 외 트래픽 (인터넷 등)')
      [void]$sb.AppendLine("  $other")
      [void]$sb.AppendLine('')
      [void]$sb.AppendLine('▶ VPN 대역 계층도  ([ ] = 묶음 표시용, 나머지는 실제 VPN 경로)')
      foreach ($l in (Format-RouteTree $t.Routes)) { [void]$sb.AppendLine("  $l") }
    }
  } elseif ($state -eq 'Connecting') {
    [void]$sb.AppendLine('▶ 터널 어댑터가 아직 올라오지 않았습니다 (인증/재연결 중).')
  } else {
    [void]$sb.AppendLine('▶ 연결되어 있지 않아 모든 트래픽이 일반 네트워크를 사용합니다.')
  }
  return $sb.ToString()
}

# ============================================================================
#  Auto-start (scheduled task at logon, highest privileges → no UAC prompt)
# ============================================================================
function Test-AutoStart { [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) }

function Set-AutoStart([bool]$on) {
  if (-not $on) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    return
  }
  $target = Join-Path $binDir 'openconnectsg-tray.ps1'
  if (-not (Test-Path $target)) { $target = $PSCommandPath }
  $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  $act  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$target`" -Hidden"
  $trg  = New-ScheduledTaskTrigger -AtLogOn -User $user
  $prin = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
  $set  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  Register-ScheduledTask -TaskName $taskName -Action $act -Trigger $trg -Principal $prin -Settings $set -Force | Out-Null
}

# ============================================================================
#  UI
# ============================================================================
$font     = New-Object System.Drawing.Font('Malgun Gothic', 9)
$monoFont = New-Object System.Drawing.Font('Consolas', 9)

function New-StateIcon([System.Drawing.Color]$color) {
  $bmp = New-Object System.Drawing.Bitmap(32, 32)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(40, 40, 40))), 1, 1, 30, 30)
  $g.FillEllipse((New-Object System.Drawing.SolidBrush($color)), 5, 5, 22, 22)
  $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 3)
  $g.DrawArc($pen, 10, 10, 12, 12, -60, 300)
  $g.DrawLine($pen, 16, 8, 16, 16)
  $g.Dispose()
  $h = $bmp.GetHicon()
  $ico = [System.Drawing.Icon]::FromHandle($h).Clone()
  [void][OcsgTray.Native]::DestroyIcon($h)
  $bmp.Dispose()
  return $ico
}
$script:icons = @{
  Connected    = New-StateIcon ([System.Drawing.Color]::FromArgb(46, 160, 67))
  Connecting   = New-StateIcon ([System.Drawing.Color]::FromArgb(210, 153, 34))
  Disconnected = New-StateIcon ([System.Drawing.Color]::FromArgb(130, 130, 130))
}
$stateColors = @{
  Connected    = [System.Drawing.Color]::FromArgb(30, 130, 50)
  Connecting   = [System.Drawing.Color]::FromArgb(180, 120, 0)
  Disconnected = [System.Drawing.Color]::Gray
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'OpenConnectSg'
$form.Font = $font
$form.Icon = $script:icons.Disconnected
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(760, 600)
$form.MinimumSize = New-Object System.Drawing.Size(560, 460)
$form.AutoScaleMode = 'Dpi'

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'; $layout.Padding = '10,10,10,6'; $layout.ColumnCount = 1; $layout.RowCount = 5
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 150)))
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($layout)

# Row 0: profile list
$lv = New-Object System.Windows.Forms.ListView
$lv.Dock = 'Fill'; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.MultiSelect = $false; $lv.HideSelection = $false
[void]$lv.Columns.Add('상태', 80)
[void]$lv.Columns.Add('프로필', 200)
[void]$lv.Columns.Add('서버', 200)
[void]$lv.Columns.Add('종류', 80)
[void]$lv.Columns.Add('부팅 시 자동', 100)
$layout.Controls.Add($lv, 0, 0)

# Row 1: buttons
$btnBar = New-Object System.Windows.Forms.FlowLayoutPanel
$btnBar.Dock = 'Fill'; $btnBar.AutoSize = $true; $btnBar.Margin = '0,6,0,6'
function New-Btn($text) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $text; $b.AutoSize = $true; $b.Padding = '8,2,8,2'
  $btnBar.Controls.Add($b); return $b
}
$btnConnect    = New-Btn '연결'
$btnDisconnect = New-Btn '연결 해제'
$btnAdd        = New-Btn '새 프로필…'
$btnLog        = New-Btn '로그 보기'
$btnRefresh    = New-Btn '새로고침'
$layout.Controls.Add($btnBar, 0, 1)

# Row 2: network report
$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text = '이 연결이 사용하는 네트워크'; $grp.Dock = 'Fill'
$txt = New-Object System.Windows.Forms.TextBox
$txt.Multiline = $true; $txt.ReadOnly = $true; $txt.ScrollBars = 'Vertical'; $txt.Dock = 'Fill'
$txt.Font = $monoFont; $txt.BackColor = [System.Drawing.SystemColors]::Window; $txt.WordWrap = $false
$grp.Controls.Add($txt)
$layout.Controls.Add($grp, 0, 2)

# Row 3: route lookup
$lookBar = New-Object System.Windows.Forms.FlowLayoutPanel
$lookBar.Dock = 'Fill'; $lookBar.AutoSize = $true; $lookBar.Margin = '0,6,0,0'; $lookBar.WrapContents = $false
$lblLook = New-Object System.Windows.Forms.Label
$lblLook.Text = '주소 경로 확인:'; $lblLook.AutoSize = $true; $lblLook.Margin = '0,7,4,0'
$tbLook = New-Object System.Windows.Forms.TextBox
$tbLook.Width = 200
$btnLook = New-Object System.Windows.Forms.Button
$btnLook.Text = '확인'; $btnLook.AutoSize = $true
$lblLookRes = New-Object System.Windows.Forms.Label
$lblLookRes.AutoSize = $true; $lblLookRes.Margin = '6,7,0,0'
$lookBar.Controls.AddRange(@($lblLook, $tbLook, $btnLook, $lblLookRes))
$layout.Controls.Add($lookBar, 0, 3)

# Row 4: footer
$foot = New-Object System.Windows.Forms.FlowLayoutPanel
$foot.Dock = 'Fill'; $foot.AutoSize = $true; $foot.WrapContents = $false
$chkAuto = New-Object System.Windows.Forms.CheckBox
$chkAuto.Text = 'Windows 로그인 시 트레이 자동 실행'; $chkAuto.AutoSize = $true
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.AutoSize = $true; $lblStatus.Margin = '16,4,0,0'; $lblStatus.ForeColor = [System.Drawing.Color]::DimGray
$foot.Controls.AddRange(@($chkAuto, $lblStatus))
$layout.Controls.Add($foot, 0, 4)

# Tray icon + menu
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = $script:icons.Disconnected
$tray.Text = 'OpenConnectSg'
$tray.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Font = $font
$tray.ContextMenuStrip = $menu

# ============================================================================
#  State + actions
# ============================================================================
$script:profiles = @()
$script:stateSig = ''
$script:job = $null          # running CLI process
$script:jobLabel = ''
$script:jobOut = Join-Path $env:TEMP 'openconnectsg-tray.out'
$script:hintShown = $false
$script:quitting = $false
$script:rebuilding = $false
$script:refreshAt = @()       # pending report refreshes (routes arrive a few seconds after the tunnel comes up)
$script:lastReport = [DateTime]::MinValue

function Get-Selected {
  if ($lv.SelectedItems.Count -eq 0) { return $null }
  $n = $lv.SelectedItems[0].Tag
  return $script:profiles | Where-Object { $_.Name -eq $n } | Select-Object -First 1
}

function Exit-Tray {
  $script:quitting = $true
  $tray.Visible = $false
  $tray.Dispose()
  [System.Windows.Forms.Application]::Exit()
}

function Show-Main {
  $form.Show(); $form.WindowState = 'Normal'; $form.Activate(); $form.BringToFront()
}

function Update-Buttons {
  $p = Get-Selected
  $busy = [bool]$script:job
  $st = if ($p) { Get-ConnState $p } else { 'Disconnected' }
  $btnConnect.Enabled    = $isAdmin -and -not $busy -and $p -and $st -eq 'Disconnected'
  $btnDisconnect.Enabled = $isAdmin -and -not $busy -and $p -and $st -ne 'Disconnected'
  $btnAdd.Enabled        = $isAdmin -and -not $busy
  $btnLog.Enabled        = [bool]$p
  $chkAuto.Enabled       = $isAdmin
}

# The report queries routing/adapters (seconds on a cold start), so it runs in a
# background runspace; Complete-Report (500 ms timer) puts the result on screen.
$script:reportFns = @('Get-TunnelAdapter', 'Get-ConnState', 'Get-StateText', 'Resolve-IPv4', 'Get-PathTo', 'Format-Path',
  'Get-TunnelRoutes', 'ConvertTo-Net', 'Test-NetContains', 'Get-RangeHint', 'Format-RouteTree', 'Get-NetworkReport')
$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
foreach ($fn in $script:reportFns) {
  $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($fn, (Get-Command $fn -CommandType Function).Definition)))
}
$script:reportRs = [runspacefactory]::CreateRunspace($iss)
$script:reportRs.Open()
$script:reportPending = $false
# Warm up the networking modules (cold load takes seconds) while the window is being built.
$script:reportPs = [powershell]::Create()
$script:reportPs.Runspace = $script:reportRs
[void]$script:reportPs.AddScript('Import-Module NetTCPIP, NetAdapter, NetConnection, DnsClient -ErrorAction SilentlyContinue; $null = Find-NetRoute -RemoteIPAddress 127.0.0.1 -ErrorAction SilentlyContinue')
$script:reportFor = '<warmup>'
$script:reportAr = $script:reportPs.BeginInvoke()

function Update-Report {
  if ($script:reportAr) { $script:reportPending = $true; return }
  $p = Get-Selected
  $script:reportFor = if ($p) { $p.Name } else { '' }
  if (-not $txt.Text) { $txt.Text = '네트워크 정보를 확인하는 중…' }
  $ps = [powershell]::Create()
  $ps.Runspace = $script:reportRs
  [void]$ps.AddCommand('Get-NetworkReport').AddArgument($p)
  $script:reportPs = $ps
  $script:reportAr = $ps.BeginInvoke()
}

function Complete-Report {
  if (-not $script:reportAr -or -not $script:reportAr.IsCompleted) { return }
  try {
    $res = $script:reportPs.EndInvoke($script:reportAr)
    $new = ([string]($res | Select-Object -First 1)) -replace "`r?`n", "`r`n"
    if ($script:reportPs.Streams.Error.Count -gt 0 -and -not $new) { $new = "네트워크 정보 오류: $($script:reportPs.Streams.Error[0])" }
  } catch { $new = "네트워크 정보 오류: $($_.Exception.Message)" }
  $script:reportPs.Dispose(); $script:reportPs = $null; $script:reportAr = $null
  $sel = Get-Selected
  $selName = if ($sel) { $sel.Name } else { '' }
  if ($selName -eq $script:reportFor) {
    if ($new -ne $txt.Text) { $keep = $txt.SelectionStart; $txt.Text = $new; $txt.SelectionStart = [Math]::Min($keep, $new.Length) }
    $script:lastReport = Get-Date
    # Connected but routes not installed yet → look again shortly
    if ($new -match 'Split tunnel, 0개' -or $new -match '터널 어댑터가 아직') { $script:refreshAt += (Get-Date).AddSeconds(5) }
  } else { $script:reportPending = $true }
  if ($script:reportPending) { $script:reportPending = $false; Update-Report }
}

# Called every tick: catch up on routes/DNS that appear after the state change.
function Update-ReportIfDue {
  $now = Get-Date
  $due = @($script:refreshAt | Where-Object { $_ -le $now })
  $connected = [bool]($script:profiles | Where-Object { $_.State -ne 'Disconnected' })
  if ($due.Count -gt 0 -or ($connected -and ($now - $script:lastReport).TotalSeconds -ge 60)) {
    $script:refreshAt = @($script:refreshAt | Where-Object { $_ -gt $now })
    Update-Report
  }
}

function Invoke-Cli([string]$label, [string[]]$cliArgs) {
  if ($script:job) { return }
  $q = @($cliArgs | ForEach-Object { "`"$_`"" }) -join ' '
  $script:job = Start-Process powershell.exe -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $script:jobOut `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$cliPs1`" $q"
  [void]$script:job.Handle   # PS 5.1: without touching Handle now, ExitCode is $null after exit
  $script:jobLabel = $label
  $lblStatus.Text = "$label 진행 중…"
  Update-Buttons
}

function Complete-Job {
  $code = $script:job.ExitCode
  $out = ''
  try { $out = (Get-Content $script:jobOut -Raw -ErrorAction SilentlyContinue) } catch { }
  $label = $script:jobLabel
  $script:job = $null
  if ($null -eq $code) { $code = if ($out -match 'Status: (Running|Disconnected)') { 0 } else { 1 } }
  Update-All -Force
  if ($code -eq 0) {
    $lblStatus.Text = "$label 완료 ($(Get-Date -Format 'HH:mm:ss'))"
    $tray.ShowBalloonTip(3000, 'OpenConnectSg', "$label 완료", 'Info')
  } else {
    $reason = ''
    if ($out) {
      $lines = @($out -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^=+$|^-+$' })
      $reason = ($lines | Select-Object -Last 8) -join "`n"
    }
    $lblStatus.Text = "$label 실패 (코드 $code)"
    $tray.ShowBalloonTip(5000, 'OpenConnectSg', "$label 실패", 'Error')
    $owner = if ($form.Visible) { $form } else { $null }
    [void][System.Windows.Forms.MessageBox]::Show($owner, "$label 실패 (코드 $code)`n`n$reason", 'OpenConnectSg', 'OK', 'Warning')
  }
}

function Do-ConnectProfile($p) {
  if (-not $p) { return }
  Invoke-Cli "'$($p.Display)' 연결" @('connect', $p.Name)
}
function Do-DisconnectProfile($p) {
  if ($p) { Invoke-Cli "'$($p.Display)' 연결 해제" @('disconnect', $p.Name) }
  else { Invoke-Cli '모든 연결 해제' @('disconnect', 'all') }
}

function Rebuild-Menu {
  $menu.Items.Clear()
  $active = $script:profiles | Where-Object { $_.State -ne 'Disconnected' }
  $head = if ($active) { ($active | ForEach-Object { "$(Get-StateText $_.State): $($_.Display)" }) -join ', ' } else { 'VPN 연결 안 됨' }
  $hi = $menu.Items.Add($head); $hi.Enabled = $false
  [void]$menu.Items.Add('-')
  foreach ($p in $script:profiles) {
    $it = New-Object System.Windows.Forms.ToolStripMenuItem("$($p.Display)  ($($p.Host))")
    $it.Tag = $p.Name
    $it.Checked = $p.State -eq 'Connected'
    $it.Enabled = $isAdmin -and -not $script:job
    $it.Add_Click({
        $n = $this.Tag
        $pp = $script:profiles | Where-Object { $_.Name -eq $n } | Select-Object -First 1
        if ($pp.State -eq 'Disconnected') { Do-ConnectProfile $pp } else { Do-DisconnectProfile $pp }
      })
    [void]$menu.Items.Add($it)
  }
  [void]$menu.Items.Add('-')
  $d = $menu.Items.Add('모두 연결 해제'); $d.Enabled = $isAdmin -and [bool]$active -and -not $script:job
  $d.Add_Click({ Do-DisconnectProfile $null })
  $o = $menu.Items.Add('창 열기'); $o.Font = New-Object System.Drawing.Font($font, [System.Drawing.FontStyle]::Bold)
  $o.Add_Click({ Show-Main })
  $x = $menu.Items.Add('종료')
  $x.Add_Click({ Exit-Tray })
}

function Update-All([switch]$Force) {
  $list = Get-TrayProfiles
  foreach ($p in $list) { $p | Add-Member -NotePropertyName State -NotePropertyValue (Get-ConnState $p) -Force }
  $sig = ($list | ForEach-Object { "$($_.Name)|$($_.State)|$($_.IsDefault)|$($_.Alias)" }) -join ';'
  $script:profiles = $list
  if (-not $Force -and $sig -eq $script:stateSig) { Update-Buttons; return }
  $script:stateSig = $sig
  $now = Get-Date
  $script:refreshAt = @($now.AddSeconds(5), $now.AddSeconds(15), $now.AddSeconds(30))

  $sel = Get-Selected
  $selName = if ($sel) { $sel.Name } else { $null }
  $script:rebuilding = $true   # suppress SelectedIndexChanged reports while the list is rebuilt
  $lv.BeginUpdate(); $lv.Items.Clear()
  foreach ($p in $list) {
    $it = New-Object System.Windows.Forms.ListViewItem((Get-StateText $p.State))
    [void]$it.SubItems.Add($p.Display)
    [void]$it.SubItems.Add("$($p.Host):$($p.Port)")
    [void]$it.SubItems.Add($p.Proto)
    [void]$it.SubItems.Add($(if ($p.IsDefault) { '예' } else { '' }))
    $it.Tag = $p.Name
    $it.ForeColor = $stateColors[$p.State]
    if ($p.State -eq 'Connected') { $it.Font = New-Object System.Drawing.Font($font, [System.Drawing.FontStyle]::Bold) }
    [void]$lv.Items.Add($it)
    if ($p.Name -eq $selName) { $it.Selected = $true }
  }
  if ($lv.SelectedItems.Count -eq 0 -and $lv.Items.Count -gt 0) {
    $first = $list | Where-Object { $_.State -ne 'Disconnected' } | Select-Object -First 1
    if (-not $first) { $first = $list | Where-Object { $_.IsDefault } | Select-Object -First 1 }
    $idx = if ($first) { [array]::IndexOf(@($list.Name), $first.Name) } else { 0 }
    $lv.Items[[Math]::Max(0, $idx)].Selected = $true
  }
  $lv.EndUpdate()
  $script:rebuilding = $false

  $overall = if ($list | Where-Object { $_.State -eq 'Connected' }) { 'Connected' }
             elseif ($list | Where-Object { $_.State -eq 'Connecting' }) { 'Connecting' } else { 'Disconnected' }
  $tray.Icon = $script:icons[$overall]; $form.Icon = $script:icons[$overall]
  $act = $list | Where-Object { $_.State -ne 'Disconnected' } | Select-Object -First 1
  $tip = if ($act) { "OpenConnectSg - $(Get-StateText $act.State): $($act.Display)" } else { 'OpenConnectSg - 연결 안 됨' }
  $tray.Text = $tip.Substring(0, [Math]::Min(63, $tip.Length))
  if (-not $script:job) {
    if ($isAdmin) { $lblStatus.Text = "갱신 $(Get-Date -Format 'HH:mm:ss')" }
    else { $lblStatus.Text = '관리자 권한이 아니어서 보기 전용입니다.' }
  }
  Rebuild-Menu
  Update-Buttons
  Update-Report
}

# ============================================================================
#  Events
# ============================================================================
$lv.Add_SelectedIndexChanged({ if (-not $script:rebuilding -and $lv.SelectedItems.Count -gt 0) { Update-Buttons; Update-Report } })
$lv.Add_DoubleClick({
    $p = Get-Selected
    if ($p -and $isAdmin -and -not $script:job) { if ($p.State -eq 'Disconnected') { Do-ConnectProfile $p } }
  })
$btnConnect.Add_Click({ Do-ConnectProfile (Get-Selected) })
$btnDisconnect.Add_Click({ Do-DisconnectProfile (Get-Selected) })
$btnRefresh.Add_Click({ Update-All -Force })
$btnLog.Add_Click({
    $p = Get-Selected; if (-not $p) { return }
    $log = Join-Path $p.Dir 'logs\out.log'
    if (Test-Path $log) { Start-Process notepad.exe -ArgumentList "`"$log`"" }
    else { [void][System.Windows.Forms.MessageBox]::Show($form, "로그 파일이 없습니다:`n$log", 'OpenConnectSg') }
  })
$btnAdd.Add_Click({
    # The setup wizard is interactive (password prompt), so it runs in a visible console.
    $cmd = "& '$cliPs1' setup; Write-Host ''; Read-Host '완료되었습니다. Enter 키를 누르면 창이 닫힙니다'"
    Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd
  })
$doLookup = {
  $q = $tbLook.Text.Trim()
  if (-not $q) { return }
  $ip = Resolve-IPv4 $q
  if (-not $ip) { $lblLookRes.Text = '주소를 확인할 수 없음'; $lblLookRes.ForeColor = [System.Drawing.Color]::Firebrick; return }
  $pt = Get-PathTo $ip
  $lblLookRes.Text = "$ip → $(Format-Path $pt)"
  $lblLookRes.ForeColor = if ($pt -and $pt.IsVpn) { $stateColors.Connected } else { [System.Drawing.Color]::Black }
}
$btnLook.Add_Click($doLookup)
$tbLook.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; & $doLookup } })

$chkAuto.Add_Click({
    try { Set-AutoStart $chkAuto.Checked }
    catch {
      [void][System.Windows.Forms.MessageBox]::Show($form, "자동 실행 설정 실패: $($_.Exception.Message)", 'OpenConnectSg')
    }
    $chkAuto.Checked = Test-AutoStart
  })

$tray.Add_MouseClick({ if ($_.Button -eq 'Left') { Show-Main } })
$tray.Add_BalloonTipClicked({ Show-Main })

$form.Add_FormClosing({
    # Hide to tray on any close except the tray's own Exit, Windows shutdown or Task Manager
    $reason = [string]$_.CloseReason
    if (-not $script:quitting -and $reason -notin @('WindowsShutDown', 'TaskManagerClosing', 'ApplicationExitCall')) {
      $_.Cancel = $true
      $form.Hide()
      if (-not $script:hintShown) {
        $script:hintShown = $true
        $tray.ShowBalloonTip(2500, 'OpenConnectSg', '트레이에서 계속 실행 중입니다. 아이콘을 클릭하면 창이 열립니다.', 'Info')
      }
    }
  })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({
    if ($script:showEvt.WaitOne(0)) { Show-Main }
    if ($script:job -and $script:job.HasExited) { Complete-Job; return }
    try { Update-All; Update-ReportIfDue } catch { $lblStatus.Text = "갱신 오류: $($_.Exception.Message)" }
  })

# Faster tick just for the "bring to front" signal from a second launch
$showTimer = New-Object System.Windows.Forms.Timer
$showTimer.Interval = 500
$showTimer.Add_Tick({
    if ($script:showEvt.WaitOne(0)) { Show-Main }
    Complete-Report
  })

$form.Add_Shown({
    $timer.Start(); $showTimer.Start()
    try { Update-All -Force } catch { $lblStatus.Text = "갱신 오류: $($_.Exception.Message)" }
  })
$chkAuto.Checked = Test-AutoStart

if ($Hidden) {
  # Build state without showing the window
  $timer.Start(); $showTimer.Start(); Update-All -Force
  [System.Windows.Forms.Application]::Run()
} else {
  [System.Windows.Forms.Application]::Run($form)
}
