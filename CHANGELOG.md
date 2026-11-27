# Changelog

All notable changes to the **OpenConnectSg** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.5] - 2026-11-27

### Changed (Breaking: logging architecture)
- **Pure Windows Event Log (EVTX) logging ([#12](https://github.com/sparklings/openconnectsg/issues/12))**:
  - Text log files (`profiles\<service>\logs\out.log`, `err.log`) are no longer created. The Windows Event Log (`Application` channel, source `OpenConnectSg`) is now the single source of truth.
  - NSSM `AppStdout` / `AppStderr` / `AppRotate*` redirection is removed from the setup wizard; existing installations are migrated automatically (registry values removed, legacy `logs\` folder deleted) on the next `connect`, service start, or `upgrade`.
  - `Do-ServiceRun` now drains `openconnect.exe` stdout/stderr entirely in memory through a C# `StreamDrainer` (no pipe-buffer deadlock, no disk I/O) and translates meaningful lines into structured events.
  - `status` and `connect` failure diagnostics read the Event Log (`Get-WinEvent`) instead of `err.log`; no file permissions are needed for non-admin reads.
  - Tray GUI: the **Log** button was renamed **Event Viewer** and opens `eventvwr.msc` at the OpenConnectSg Custom View; a tray context-menu entry **Event Viewer** was added. Notepad is no longer used.

### Added
- **EventID taxonomy (15 IDs)**: `1000` service start, `1001` service stop, `1002` abnormal exit, `2000` connecting, `2001` tunnel established, `2002` tunnel disconnected, `3000` DTLS fallback, `3001` stale Wintun adapter cleanup, `3002` keepalive delay, `4000` authentication rejected, `4001` Wintun adapter timeout, `4002` account lockout, `4003` DPAPI decryption failure, `5000` profile created/changed, `5001` upgrade completed.
- **`openconnectsg logs` (alias `log`)**: colorized 80-column TUI over `Get-WinEvent` with `<profile>`, `--tail <n>`, `--level error|warn`, `--raw`, and `--gui` (launches Event Viewer).
- **`openconnectsg connect <profile> --debug`**: on-demand mode that runs `openconnect.exe` in the current console and streams the raw output without writing any file.
- **Event Source & Custom View deployment**: the installer, setup wizard, and upgrade register the `OpenConnectSg` event source and `%ProgramData%\Microsoft\Event Viewer\Views\OpenConnectSg.xml` (Event Viewer > Custom Views > OpenConnectSg); `uninstall` removes both.
- **`docs/evtx-technical-guide.md`**: engineering report on the EVTX architecture, EventID taxonomy, in-memory drainer, Custom View, and XPath/WEF/SIEM operations.

### Documentation
- Updated `README.md`, `docs/architecture.md`, `docs/subcommand-manual.md`, `docs/troubleshooting.md`, `docs/install-guide.md`, `docs/openconnectsg.md`, `llms.txt`, `llms-full.txt`, `CITATION.cff`, and the bug-report template for v1.0.5 and the Event Log workflow.

---

## [1.0.4c] - 2026-11-21

### Fixed
- **NSSM Status Line Break in Setup Wizard (`src/init-openconnectsg.ps1`)**:
  - Resolved an abnormal line wrap where the closing parenthesis `)` rendered on a separate line in the profile completion banner (`Profile setup completed successfully! (Service: SERVICE_RUNNING)`).
  - Sanitized NSSM status string output by stripping null bytes (`\0`) and trailing CRLF line breaks before terminal interpolation.
- **Dynamic Version Synchronization in Setup Wizard (`src/init-openconnectsg.ps1`)**:
  - Replaced legacy hardcoded version string (`v0.1.3b`) in the setup wizard header with dynamic version detection from the main CLI dispatcher (`openconnectsg.ps1`), with fallback to the release version (`1.0.4c`).
- **Metadata & Documentation Version Alignment**:
  - Synchronized all active version references and badges across `README.md`, `CITATION.cff`, `install/install-openconnectsg.ps1`, `docs/install-guide.md`, `docs/architecture.md`, and `docs/subcommand-manual.md` to release `v1.0.4c`.

---

## [1.0.4b] - 2026-11-20

### Fixed
- **One-Line Web Install Compatibility (`irm ... | iex`)**:
  - Fixed `ParameterArgumentValidationErrorEmptyStringNotAllowed` error when executing `install-openconnectsg.ps1` via `Invoke-Expression` (`iex`) where `$PSScriptRoot` is empty.
  - Added null/empty string guards before calling `Split-Path -Parent $PSScriptRoot` across local source detection and uninstallation routines.
  - Implemented robust fallback logic for installer self-copy (`$installerSrc`), sourcing from `$SourceDir\install\install-openconnectsg.ps1` when executed from an in-memory stream.
- **FIGlet Banner Standardization**:
  - Updated ASCII art banner from `OpenConnect Sg` to `OpenConnectSg` across CLI dispatcher, setup wizard, installer, and documentation.
- **Documentation**:
  - Updated `docs/install-guide.md` Method B with alternative one-line command and added troubleshooting FAQ entry Q6 explaining `$PSScriptRoot` evaluation under `iex`.

---

## [1.0.4a] - 2026-11-06

### Fixed
- **Tray GUI Deployment in `openconnectsg upgrade`**:
  - Resolved an issue where running `openconnectsg upgrade` bypassed copying `openconnectsg-tray.ps1` and Start Menu shortcuts due to matching version strings.
  - Added Start Menu shortcut (`%ProgramData%\Microsoft\Windows\Start Menu\Programs\OpenConnectSg.lnk`) creation/update directly into `Do-Upgrade`.
  - Added missing component detection in `Do-Upgrade` to ensure essential scripts (`openconnectsg-tray.ps1`, `init-openconnectsg.ps1`) are deployed even if versions match.
- **Documentation**:
  - Expanded `docs/install-guide.md` with complete technical specifications for the System Tray GUI, deployed artifacts table, logon scheduled task architecture, and upgrade troubleshooting.

---

## [1.0.4] - 2026-11-06

### Added
- **System Tray GUI (`src/openconnectsg-tray.ps1`, `openconnectsg tray`)**:
  - Lightweight WinForms notification-area tray application (`openconnectsg tray` / `openconnectsg gui`).
  - Real-time connection status icon (Green = Connected, Yellow = Connecting, Gray = Disconnected).
  - Profile connection and disconnection controls from both main window and notification tray context menu.
  - Close-to-tray window management: closing the UI window minimizes to the system tray rather than killing the tunnel.
  - Optional "Start at Windows logon" checkbox: registers a highest-privilege scheduled task (`RunLevel=Highest`) to launch the tray without UAC prompts at logon.
  - Integrated Start Menu shortcut (`OpenConnectSg`) generated upon installation.
- **Network & Route Hierarchy Visualization**:
  - Displays physical egress adapter details (Wi-Fi SSID, local IPv4, default gateway) utilized to reach the VPN gateway.
  - Full vs Split Tunnel classification with real-time tunnel IP, DNS servers, and routed subnet ranges.
  - Hierarchical CIDR subnet breakdown: groups private subnets (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) and public ranges into nested containment trees, bundling subnets sharing common `/16` blocks.
  - Address Route Resolver: interactive search box allowing users to input any IP or hostname to determine whether traffic routes over the VPN or the physical internet gateway.

### Fixed
- **Administrative Privilege Verification & Seamless UAC Elevation (`Ensure-AdminPrivilege`)**:
  - Implemented automatic administrative privilege verification across `connect`, `disconnect`, `setup`, `remove`, `upgrade`, and `uninstall` commands.
  - Automatically requests UAC elevation in standard (non-elevated) PowerShell sessions, eliminating silent `Access is denied (5)` Windows Service Control Manager failures (resolves #4).
- **Single Auto-Start Tunnel Policy (`Set-AutoStartProfile`)**:
  - Enforced that only the active/default profile maintains `Automatic` startup type; all other `openconnect_*` services are set to `Manual`, preventing multiple conflicting tunnels from auto-starting on system reboot.
- **Installer Self-Deletion Prevention (`install-openconnectsg.ps1`)**:
  - Fixed condition where default `-RepoUrl` parameter triggered a re-clone that deleted the active local repository folder the script was running from.
- **NSSM Error Visibility & Propagation (`Invoke-Nssm`)**:
  - Eliminated `2>$null` error silencing during NSSM command execution.
  - Captured standard error streams (`2>&1`) to directly surface descriptive failure causes (e.g. Access Denied, missing service, SCM communication timeout) to the user console.
- **Accurate Disconnection Status Reporting (`Do-Disconnect`)**:
  - Fixed misleading green `Status: Disconnected` display on service termination failure.
  - Now accurately reports red `Status: Failed to Disconnect` with non-zero exit codes whenever one or more services fail to stop gracefully.
- **Process Tree Cleanup & Orphan/Wintun Residual Prevention (`Stop-TunnelProcess`)**:
  - Implemented proactive 2-stage shutdown: queries and forcefully terminates (`Stop-Process -Force`) any lingering `openconnect.exe` child processes if NSSM does not reach Stopped state within 5 seconds.
  - Automatically scans and removes orphaned Wintun kernel tunnel adapters in error state (`CM_PROB_DISABLED_SERVICE`) via `pnputil /remove-device`.
  - Added child process kill guard and stdin stream closure in `Do-ServiceRun` `finally` block to prevent daemon runner terminations from leaving orphaned background processes.

---

## [v0.1.3b] - 2026-11-04

### Fixed
- **Port Argument Type Binding in `Detect-VpnGateway`**: Wrapped `-Port ([int]$vpnPort)` in explicit expression parentheses to prevent PowerShell parameter binder from interpreting `[int]443` as an invalid string literal during setup.
- **Installer Version Hardcoding (`install-openconnectsg.ps1`)**: Eliminated hardcoded `$ver = '0.1.2d'` in the system installer. Implemented dynamic version extraction from the deployed binary (`openconnectsg.ps1`) to ensure installation banners, metadata markers (`.installed`), and console verification accurately reflect the latest release (`v0.1.3b`).

### Improved
- **Path Dynamicization & Portability**: Replaced all hardcoded system drive paths (`C:\Program Files`, `C:\Windows\...`) across `openconnectsg.ps1` and `init-openconnectsg.ps1` with dynamic environment variables (`$env:ProgramFiles`, `$env:SystemRoot`) and active command resolution (`Get-Command powershell.exe`).
- **Flexible Tunnel Group Selection**: Enabled users to explicitly enter `-` or `none` during setup to opt out of an auto-detected tunnel group.
- **Documentation & Metadata Synchronization**: Synchronized all technical specifications, setup guides (`install-guide.md`, `subcommand-manual.md`, `architecture.md`), `CITATION.cff`, and `llms-full.txt` to `v0.1.3b`.

---

## [v0.1.3a] - 2026-11-04

### Added
- **Multi-Vendor Gateway Signature Auto-Detection (`Detect-VpnGateway`)**:
  - Implemented automatic classification of VPN gateways (Cisco AnyConnect / Firepower / ASA vs Fortinet FortiGate SSL-VPN) during `openconnectsg setup`.
  - Probes TLS certificate subjects/issuers, HTTP response headers, session cookies (`webvpn`, `samlPreauthSessionHash`, `SVPNCOOKIE`), redirect locations (`+CSCOE+`, `/remote/login`), and HTML payloads with zero prior user input.
- **Cisco Tunnel Group (`authgroup`) Discovery**:
  - Automatically queries and extracts available authentication groups from Cisco WebVPN logon portals (`/+CSCOE+/logon.html`) and OpenConnect authentication negotiation probes.
  - Dynamically prompts user with discovered tunnel groups (e.g. `Corporate_VPN`, `Engineering`, `General`, etc.).
- **Interactive Multi-Vendor Setup Flow**:
  - Integrated vendor selection in `init-openconnectsg.ps1` defaulting to auto-detected gateway with high confidence.
  - Automatically writes protocol-specific directives (`protocol=anyconnect` with optional `authgroup`, or `protocol=fortinet` with `no-dtls`) into `openconnect.conf`.
- **Protocol & AuthGroup Visibility**:
  - Extended profile metadata model in `openconnectsg.ps1` (`Get-Profiles`) to parse `protocol` and `authgroup`.
  - Added `PROTO` column to `openconnectsg list` table.
  - Added `Protocol` and `AuthGroup` fields to `openconnectsg status <profile>`.

---

## [v0.1.2d] - 2026-10-24

### Added
- **Documentation Architecture Hub**: Reorganized repository documentation by turning [`README.md`](README.md) into a streamlined navigation hub with structured artifact mapping tables.
- **Modularized Engineering Documentation**:
  - [`docs/architecture.md`](docs/architecture.md): Core system architecture, daemon lifecycle, and Wintun tunnel orchestration.
  - [`docs/security-credentials.md`](docs/security-credentials.md): DPAPI LocalMachine encryption, ACL locking, and RFC 7469 pinning specifications.
  - [`docs/dpapi-technical-guide.md`](docs/dpapi-technical-guide.md): Comprehensive technical report and reference covering Windows DPAPI architecture, internal key derivation, scope comparisons (`CurrentUser` vs `LocalMachine`), and NTFS ACL hardening.
  - [`docs/icacls-technical-guide.md`](docs/icacls-technical-guide.md): Exhaustive engineering specification on Windows icacls.exe engine, NTFS DACL security descriptors, inheritance stripping (`/inheritance:r`), and locale-agnostic Well-Known SID hardening.
- **Community Standards & Code of Conduct**: Added [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) adhering to Contributor Covenant v2.1 with a pragmatic, developer-first, and flexible collaboration tone.
  - [`docs/troubleshooting.md`](docs/troubleshooting.md): In-depth diagnostic workflows, log inspection guides, and error recovery procedures.
- **Version Verification in Upgrade (`Compare-VersionString`)**: `openconnectsg upgrade` compares the installed version with the target version before proceeding. If already up to date, it skips re-deployment and service restart to preserve active VPN sessions.
- **Force Upgrade Flag (`--force`, `-f`)**: Added `-f` / `--force` option to `openconnectsg upgrade` to allow re-deploying identical versions when necessary.

### Fixed
- **Fortinet DTLS Drop & Cookie Rejection (`no-dtls`)**: Resolved FortiGate SSL-VPN reconnection loops (`Cookie was rejected by server; exiting.`) by automatically sanitizing and injecting `no-dtls` into `openconnect.conf` during connect, upgrade, and daemon service runs.
- **NSSM Paused/Throttled Service Auto-Reset**: Added automatic recovery in `Do-Connect` to transition services from `Paused` or throttled states to `Stopped` prior to starting.
- **Session Error Log & Heartbeat State Isolation**: Automatically reset stale `err.log` and initialize `heartbeat.status` to `STARTING` on daemon startup, preventing previous session termination states from contaminating active connection monitoring.
- **Wintun Startup Warning Filter**: Enhanced `StderrFilter` and `Do-Status` to suppress benign informational notices (`WARNING: Support for Wintun is experimental...`), keeping `Recent Error` clean unless genuine runtime failures occur.
- **Graceful Disconnect Cleanup**: Cleaned up stale error logs and updated heartbeat status to `STOPPED` when tunnels are intentionally closed via `openconnectsg stop` / `disconnect`.
- **Installer Duplicate Banner Suppression**: Cleaned up `install-openconnectsg.ps1` verification routine to eliminate redundant banner rendering during deployment.

---

## [v0.1.2c] - 2026-10-15

### Added
- **Diagnostic Failure Block**: Added automated failure diagnosis in `Do-Connect` displaying log tail paths and potential remediation steps when tunnel connection fails.
- **English UI Standardization**: Normalized messages and error output across subcommands to eliminate encoding and localization friction in diverse terminal setups.

### Changed
- **Unified Terminal UI (TUI)**: Standardized visual formatting across all subcommands (`list`, `status`, `connect`, `disconnect`, `remove`, `alias`, `default`, `uninstall`, `upgrade`) using 80-column box borders (`====`, `----`) and step-by-step progress spacing.
- Synchronized manual documentation with the updated TUI layouts.

---

## [v0.1.2b] - 2026-10-14

### Added
- **Slant ASCII Welcome Banner**: Integrated Figlet ASCII banner in [`install/install-openconnectsg.ps1`](install/install-openconnectsg.ps1) and added the `openconnectsg banner` subcommand.
- **Environment & Architecture Briefing**: Post-install summary displaying `DEPLOY` path, system `PATH` registration, dependencies (`OpenConnect CLI`, `NSSM`), and core components (`DPAPI`, `Wintun`).
- **Interactive Quick Start**: Colorized onboarding guidance for terminal refresh and first-time `setup` execution.

### Changed
- Enhanced [`install/install-openconnectsg.ps1`](install/install-openconnectsg.ps1) completion routine.
- Synchronized versions across `CITATION.cff` and `llms-full.txt`.

---

## [v0.1.2a] - 2026-10-13

### Added
- **Wintun Stale Adapter Cleanup**: Added cleanup logic for stale or conflicting Wintun network interfaces to ensure smooth adapter instantiation.
- **Subcommand `upgrade` / `update`**: Automatic remote repository clone or ZIP download with Windows UAC self-elevation.
- **Heartbeat Status Aggregator**: Periodic health check mechanism to isolate VPN keepalive noise from `err.log`.
- **Scope-based Uninstaller**: Extended `openconnectsg uninstall` to support `-Scope app` (scripts only) and `-Scope full` (scripts + dependencies + profiles).
- **Machine-Readable LLM Specification**: Added [`llms.txt`](llms.txt) and [`llms-full.txt`](llms-full.txt) for AI agent context indexing.

### Fixed
- **Wintun Adapter Creation Timeout (`0x102`)**: Removed `interface=OpenConnectSg` hardcoded override and sanitized `openconnect.conf` in `Do-Connect` and `Do-ServiceRun` to let Wintun allocate interfaces dynamically.
- **Premature VPN Logout**: Maintained `.NET` standard input (`stdin`) stream open after transmitting credentials, preventing `openconnect.exe` from interpreting closed stdin as a termination signal.
- **Console Encoding**: Enforced UTF-8 BOM encoding across PowerShell scripts to prevent character corruption on localized Windows terminals.

---

## [v0.1.1b] - 2026-10-11

### Added
- **DPAPI LocalMachine Credential Security**: Encrypted password storage via `System.Security.Cryptography.ProtectedData` (`pw.bin`) with `icacls` access restricted strictly to `SYSTEM` and `Administrators`.
- **RFC 7469 Pin-SHA256 Server Fingerprinting**: Automated extraction and storage of server SSL certificate fingerprints to prevent MITM attacks without security prompt popups.
- **Profile Setup Wizard**: Interactive onboarding wizard via [`src/init-openconnectsg.ps1`](src/init-openconnectsg.ps1).
- **NSSM Service Daemon Integration**: Registered Windows background services under `openconnect_<host>_<port>_<tag8>` with automatic restart and logging.

---

## [v0.1.1a] - 2026-10-11

### Fixed
- Removed `--non-inter` flag and NSSM `AppThrottle` to prevent authentication handshake timeouts.

---

## [v0.1.0] - 2026-10-11

### Added
- Initial project prototype for PowerShell-based OpenConnect automation on Windows.
