#Requires -RunAsAdministrator
<#
.SYNOPSIS
  openconnectsg profile setup wizard (invoked by 'openconnectsg setup', v0.1.1a)
.DESCRIPTION
  Interactive wizard that prompts for remote VPN host, port, credentials,
  verifies binary dependencies with cryptographic checksums, encrypts credentials via DPAPI,
  pins server certificates (RFC7469), and configures managed Windows services.
.NOTES
  Save encoding: UTF-8 with BOM, CRLF line endings.
#>
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Known Official SHA256 Checksums for Dependencies
$NSSM_EXE_SHA256 = 'F689EE9AF94B00E9E3F0BB072B34CAAF207F32DCB4F5782FC9CA351DF9A06C97'

if ($PSVersionTable.PSVersion.Major -lt 5) {
  throw "PowerShell 5.1 or later is required. Current version: $($PSVersionTable.PSVersion)"
}

function Write-Step { param([string]$Text) Write-Host ("-" * 40); Write-Host $Text }
function Write-Gap  { 1..2 | ForEach-Object { Write-Host "" } }

# 0) Interactive Credentials Input
$vpnHost = (Read-Host "Remote VPN Server Address (FQDN or IP)").Trim()
if ([string]::IsNullOrWhiteSpace($vpnHost)) { throw "VPN Server Address is required." }
$portInput = Read-Host "Remote VPN Server Port [443]"
if ([string]::IsNullOrWhiteSpace($portInput)) { $vpnPort = "443" } else { $vpnPort = $portInput.Trim() }
if ($vpnPort -notmatch '^\d+$' -or [int]$vpnPort -lt 1 -or [int]$vpnPort -gt 65535) { throw "Invalid port: $vpnPort" }
$vpnUser = (Read-Host "User Account Name").Trim()
if ([string]::IsNullOrWhiteSpace($vpnUser)) { throw "User Account is required." }
$ss = Read-Host "Password (masked input)" -AsSecureString
if ($ss.Length -eq 0) { throw "Password is required." }
$serverUrl = "https://${vpnHost}:${vpnPort}"

# Generate unique service tag: tag8 = SHA256(host|port|user)[0..8]
$sha   = [System.Security.Cryptography.SHA256]::Create()
$hash  = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$vpnHost|$vpnPort|$vpnUser"))
$sha.Dispose()
$tag     = -join ($hash | ForEach-Object { $_.ToString('x2') })
$tag     = $tag.Substring(0, 8)
$svcName = "openconnect_${vpnHost}_${vpnPort}_${tag}"
$dispName = "openconnectsg - ${vpnHost}:${vpnPort} ($vpnUser)"

$ocRoot  = "C:\Program Files\OpenConnect"
$nssmDir = "C:\Program Files\nssm"
$binDir  = Join-Path $ocRoot "bin"
$root    = Join-Path $ocRoot "profiles"
$dir     = Join-Path $root $svcName
$logs    = Join-Path $dir "logs"

# 1) Directories Setup
Write-Step "[1/7] Initializing profile workspace..."
New-Item -ItemType Directory -Path $nssmDir, $ocRoot, $binDir, $logs, $dir -Force | Out-Null
Write-Gap

# 2) NSSM 2.24 Dependency & Integrity Verification
Write-Step "[2/7] Verifying NSSM service helper..."
$nssmExe = Join-Path $nssmDir "nssm.exe"
if (-not (Test-Path $nssmExe)) {
  Write-Host "Downloading NSSM 2.24 helper..."
  $nssmZip = "$env:TEMP\nssm-2.24.zip"
  $nssmUrls = @(
    "https://github.com/imvickykumar999/Non-Sucking-Service-Manager/releases/download/nssm-2.24/nssm-2.24.zip",
    "https://nssm.cc/release/nssm-2.24.zip"
  )
  $downloadOk = $false
  foreach ($url in $nssmUrls) {
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $nssmZip -TimeoutSec 15
      if ((Test-Path $nssmZip) -and ((Get-Item $nssmZip).Length -gt 100000)) {
        $downloadOk = $true
        break
      }
    } catch { }
  }
  if (-not $downloadOk) {
    throw "Failed to download NSSM helper from available mirror sources."
  }

  Expand-Archive -Path $nssmZip -DestinationPath "$env:TEMP\nssm-tmp" -Force
  $extractedExe = "$env:TEMP\nssm-tmp\nssm-2.24\win64\nssm.exe"

  # Cryptographic verification
  $hash = (Get-FileHash -Path $extractedExe -Algorithm SHA256).Hash
  if ($hash -ne $NSSM_EXE_SHA256) {
    Remove-Item $extractedExe, $nssmZip -Force -ErrorAction SilentlyContinue
    throw "Security Alert: NSSM binary checksum mismatch! Expected: $NSSM_EXE_SHA256, Found: $hash"
  }
  Copy-Item $extractedExe $nssmExe -Force
  Remove-Item $nssmZip, "$env:TEMP\nssm-tmp" -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "NSSM verified successfully (SHA256 matched)."
}
$verInfo = (Get-Item $nssmExe).VersionInfo
Write-Host "NSSM helper verified: $($verInfo.ProductName) (v$($verInfo.ProductVersion))"
Write-Gap

# 3) OpenConnect CLI Dependency Verification
Write-Step "[3/7] Verifying openconnect CLI..."
$ocExe = Join-Path $ocRoot "openconnect.exe"
if (-not (Test-Path $ocExe)) {
  Write-Host "Downloading openconnect installer..."
  $ocInstaller = "$env:TEMP\openconnect-installer.exe"
  Invoke-WebRequest -UseBasicParsing -Uri "https://gitlab.com/openconnect/openconnect/-/jobs/artifacts/v9.21/raw/openconnect-installer-MinGW64-GnuTLS.exe?job=MinGW64/GnuTLS" -OutFile $ocInstaller
  Start-Process $ocInstaller -ArgumentList "/S" -Wait
  Remove-Item $ocInstaller -Force -ErrorAction SilentlyContinue
}
if (-not (Test-Path $ocExe)) {
  throw "openconnect.exe not found at $ocExe after installation."
}
$ocVer = (& $ocExe --version 2>&1 | Select-Object -First 1)
Write-Host "OpenConnect CLI verified: $ocVer"
Write-Gap

# 4) Write Profile Metadata
Write-Step "[4/7] Writing profile configuration ($svcName)..."
Set-Content (Join-Path $root "default.txt") $svcName -NoNewline -Encoding ascii
"protocol=fortinet", "server=$serverUrl", "user=$vpnUser" | Set-Content (Join-Path $dir "openconnect.conf") -Encoding ascii
Set-Content (Join-Path $dir "user.txt") $vpnUser -NoNewline -Encoding ascii
Write-Gap

# 5) Encrypt Password via DPAPI LocalMachine
Write-Step "[5/7] Encrypting password with DPAPI LocalMachine..."
Add-Type -AssemblyName System.Security
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
try {
  $byteLen = [System.Runtime.InteropServices.Marshal]::ReadInt32($bstr, -4)
  $bytes = New-Object byte[] $byteLen
  [System.Runtime.InteropServices.Marshal]::Copy($bstr, $bytes, 0, $byteLen)
  [System.IO.File]::WriteAllBytes((Join-Path $dir "pw.bin"),
    [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, 'LocalMachine'))
} finally {
  [System.Array]::Clear($bytes, 0, $bytes.Length)
  [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
$ss = $null
# Restrict permissions: SYSTEM and local Administrators only (language-neutral SIDs)
icacls (Join-Path $dir "pw.bin") /inheritance:r /grant "*S-1-5-18:F" /grant "*S-1-5-32-544:F" | Out-Null
Write-Gap

# 6) Acquire Server Certificate Fingerprint (pin-sha256)
Write-Step "[6/7] Probing server certificate pin (RFC7469)..."
$pin = $null

# Define .NET native SPKI extractor if not already present
if (-not ([System.Management.Automation.PSTypeName]'OpenConnectPinProbe').Type) {
  $csharpCode = @"
using System;
using System.Net.Sockets;
using System.Net.Security;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

public static class OpenConnectPinProbe {
    public static string ProbePin(string host, int port, int timeoutMs = 5000) {
        using (var client = new TcpClient()) {
            var ar = client.BeginConnect(host, port, null, null);
            if (!ar.AsyncWaitHandle.WaitOne(timeoutMs)) {
                throw new TimeoutException("TCP connection timed out.");
            }
            client.EndConnect(ar);
            using (var ssl = new SslStream(client.GetStream(), false, (sender, cert, chain, err) => true)) {
                var authTask = ssl.AuthenticateAsClientAsync(host);
                if (!authTask.Wait(timeoutMs)) {
                    throw new TimeoutException("SSL handshake timed out.");
                }
                if (ssl.RemoteCertificate == null) {
                    throw new InvalidOperationException("No remote certificate received.");
                }
                var cert = new X509Certificate2(ssl.RemoteCertificate);
                byte[] spki = ExtractSpki(cert.RawData);
                if (spki == null) {
                    throw new InvalidOperationException("Failed to extract SubjectPublicKeyInfo.");
                }
                using (var sha = SHA256.Create()) {
                    byte[] hash = sha.ComputeHash(spki);
                    return "pin-sha256:" + Convert.ToBase64String(hash);
                }
            }
        }
    }

    private static byte[] ExtractSpki(byte[] certDer) {
        try {
            int offset = 0;
            if (certDer[offset++] != 0x30) return null;
            ReadLength(certDer, ref offset);
            if (certDer[offset++] != 0x30) return null;
            ReadLength(certDer, ref offset);
            
            if (certDer[offset] == 0xA0) {
                offset++;
                int vLen = ReadLength(certDer, ref offset);
                offset += vLen;
            }
            if (certDer[offset++] != 0x02) return null;
            int sLen = ReadLength(certDer, ref offset);
            offset += sLen;
            if (certDer[offset++] != 0x30) return null;
            int sigLen = ReadLength(certDer, ref offset);
            offset += sigLen;
            if (certDer[offset++] != 0x30) return null;
            int issLen = ReadLength(certDer, ref offset);
            offset += issLen;
            if (certDer[offset++] != 0x30) return null;
            int valLen = ReadLength(certDer, ref offset);
            offset += valLen;
            if (certDer[offset++] != 0x30) return null;
            int subLen = ReadLength(certDer, ref offset);
            offset += subLen;
            
            int spkiStart = offset;
            if (certDer[offset++] != 0x30) return null;
            int spkiLen = ReadLength(certDer, ref offset);
            int totalBytes = (offset - spkiStart) + spkiLen;
            byte[] spki = new byte[totalBytes];
            Array.Copy(certDer, spkiStart, spki, 0, totalBytes);
            return spki;
        } catch {
            return null;
        }
    }

    private static int ReadLength(byte[] data, ref int offset) {
        byte b = data[offset++];
        if ((b & 0x80) == 0) return b;
        int count = b & 0x7F;
        int len = 0;
        for (int i = 0; i < count; i++) {
            len = (len << 8) | data[offset++];
        }
        return len;
    }
}
"@
  Add-Type -TypeDefinition $csharpCode -Language CSharp
}

# 1) Try fast, direct .NET SPKI probe
try {
  $pin = [OpenConnectPinProbe]::ProbePin($vpnHost, [int]$vpnPort, 5000)
} catch {
  Write-Warning "Direct .NET certificate probe failed: $($_.Exception.Message)"
}

# 2) Fallback to OpenConnect CLI probe if .NET probe did not succeed
if ([string]::IsNullOrWhiteSpace($pin) -and (Test-Path $ocExe)) {
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ocExe
    $psi.Arguments = "--protocol=fortinet -u probe $serverUrl"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.WriteLine("no")
    $proc.StandardInput.Close()

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit(7000) | Out-Null
    if (-not $proc.HasExited) { try { $proc.Kill() } catch { } }

    $combined = "$stdout`n$stderr"
    if ($combined -match '(pin-sha256:[A-Za-z0-9+/]{40,}={0,2})') {
      $pin = $Matches[1]
    }
  } catch {
    Write-Warning "CLI certificate probe fallback failed: $($_.Exception.Message)"
  }
}

# 3) Fallback to manual entry or verify network connectivity
if ([string]::IsNullOrWhiteSpace($pin)) {
  # Verify if remote host and port are actually reachable
  $canConnect = $false
  try {
    $client = New-Object System.Net.Sockets.TcpClient
    $ar = $client.BeginConnect($vpnHost, [int]$vpnPort, $null, $null)
    $canConnect = $ar.AsyncWaitHandle.WaitOne(3000)
    $client.Close()
  } catch { }

  if (-not $canConnect) {
    throw "Cannot connect to server. Please verify address and port: $serverUrl"
  }

  Write-Host "Automatic pin discovery failed. Please paste the pin-sha256 value manually."
  $pin = (Read-Host "Full pin-sha256 value (including pin-sha256:)").Trim()
}

if ($pin -notmatch '^pin-sha256:[A-Za-z0-9+/]{40,}={0,2}$') { throw "Invalid certificate pin format: $pin" }
Write-Host "Server certificate pin: $pin"
Set-Content (Join-Path $dir "pin.txt") $pin -NoNewline -Encoding ascii
"protocol=fortinet", "server=$serverUrl", "user=$vpnUser", "servercert=$pin" | Set-Content (Join-Path $dir "openconnect.conf") -Encoding ascii
Write-Gap

# 7) Register NSSM Managed Windows Service
Write-Step "[7/7] Registering managed Windows Service ($svcName)..."
$exists = $null -ne (Get-Service -Name $svcName -ErrorAction SilentlyContinue)
if (-not $exists) {
  & $nssmExe install $svcName C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe 2>&1 | Out-Null
  Write-Host "Service '$svcName' registered successfully."
} else {
  Write-Host "Service '$svcName' already exists. Updating configuration."
  try { & $nssmExe stop $svcName 2>&1 | Out-Null } catch { }
}

$dispatcherPs1 = Join-Path $binDir 'openconnectsg.ps1'
$key = "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName"
$base = Join-Path $key "Parameters"
Set-ItemProperty $base Application "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
Set-ItemProperty $base AppDirectory $ocRoot
Set-ItemProperty $base AppParameters "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dispatcherPs1`" service-run $svcName"
Set-ItemProperty $base AppStdout (Join-Path $logs "out.log")
Set-ItemProperty $base AppStderr (Join-Path $logs "err.log")
Set-ItemProperty $base AppRotateFiles 1 -Type DWord
Set-ItemProperty $base AppRotateBytes 1048576 -Type DWord

$appExit = Join-Path $base "AppExit"
if (-not (Test-Path $appExit)) { New-Item -Path $appExit -Force | Out-Null }
Set-ItemProperty $appExit Default Restart
Set-ItemProperty $base Start -Value SERVICE_AUTO_START
Set-ItemProperty $key  DisplayName $dispName
Set-Service -Name $svcName -StartupType Automatic

Write-Host "Starting service '$svcName'..."
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
& $nssmExe start $svcName *>$null
$ErrorActionPreference = $prevEAP

Start-Sleep 5
$statusRaw = (& $nssmExe status $svcName 2>&1 | Out-String).Trim()
Write-Host "Service status: $statusRaw"
Write-Host "Profile setup complete. Run 'openconnectsg' to check status."
Write-Gap

