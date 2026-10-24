# Changelog

All notable changes to the **OpenConnectSg** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
