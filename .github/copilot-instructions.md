# Copilot & AI Coding Agent Instructions for openconnectsg

You are assisting with development on the **OpenConnectSg** repository (`openconnectsg`).
Follow these strict architectural, cryptographic, and stylistic constraints:

## 1. Naming & Case Convention (Strict Policy)
- The user-facing tool command, script filenames, internal variables, and documentation references MUST be strictly lowercase: `openconnectsg`.
- The formal project title in headings or README title is `OpenConnectSg`.
- Never introduce PascalCase or mixed-case script names (e.g., do NOT create `OpenConnectSg.ps1` or `Install-OpenConnectSg.ps1`). The scripts MUST remain:
  - `openconnectsg.ps1`
  - `openconnectsg.cmd`
  - `init-openconnectsg.ps1`
  - `install-openconnectsg.ps1`

## 2. Character Encoding & Line Endings
- **All PowerShell scripts (`.ps1`) MUST be saved in UTF-8 with BOM (`[System.Text.Encoding]::UTF8`) and CRLF line endings (`\r\n`).**
  - This is required for Windows PowerShell 5.1 compatibility on legacy Windows environments.
- `.cmd` and `.md` files use standard UTF-8 (no BOM) with CRLF.

## 3. Cryptography and Credential Architecture
- **No Plaintext Passwords**: Never write passwords to disk in plaintext.
- Always use `[System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, 'LocalMachine')` to generate `pw.bin`.
- After creating `pw.bin`, immediately restrict ACLs:
  `icacls "pw.bin" /inheritance:r /grant "SYSTEM:F" /grant "Administrators:F"`
- Zero out byte arrays (`[System.Array]::Clear`) and free BSTR pointers (`Marshal.ZeroFreeBSTR`) immediately after use.

## 4. Service Architecture (No Dynamic Script Generation)
- Do NOT generate temporary or dynamic scripts (`service.ps1`, `deploy-profile.ps1`) via string templates.
- NSSM services MUST directly invoke the unified dispatcher with `service-run`:
  `powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Program Files\OpenConnect\bin\openconnectsg.ps1" service-run <service_name>`

## 5. Dependency Integrity
- External binary downloads (NSSM, openconnect) MUST include cryptographic SHA256 hash checks before execution or placement.
- If an official checksum does not match, abort immediately and purge the downloaded payload.

## 6. Single-Tunnel & Mutex Enforcement
- Every service run MUST acquire a named global mutex: `New-Object System.Threading.Mutex($false, "Global\$serviceName")`.
- When `openconnectsg connect` is invoked, any conflicting running `openconnect_*` services MUST be stopped first to guarantee a clean routing table.
