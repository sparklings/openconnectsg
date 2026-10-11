# Security Policy for openconnectsg

## Supported Versions

| Version | Supported | Security Updates |
|---|---|---|
| 3.0.x | :white_check_mark: | Active support |
| < 3.0 | :x: | End of life (deprecated) |

---

## Security Architecture & Threat Model

`openconnectsg` is engineered to solve credential leakage risks common in automated VPN environments.

### 1. Data Protection at Rest (DPAPI)
- Password payloads are encrypted using **Windows Data Protection API (DPAPI)** with `LocalMachine` scope.
- The encrypted artifact (`pw.bin`) cannot be decrypted on another machine.
- File access permissions are strictly hardened immediately after creation:
  - **SYSTEM**: Full Control (`F`)
  - **Administrators**: Full Control (`F`)
  - **Inheritance**: Stripped (`/inheritance:r`)
- Unprivileged users on the system cannot read or decrypt the credential payload.

### 2. In-Memory Protection
- Passwords entered interactively are captured as `System.Security.SecureString`.
- Byte buffers used during encryption and handshake probes are explicitly cleared using `[System.Array]::Clear()` and native BSTR pointers are zero-freed.

### 3. Supply Chain & Binary Integrity
- External helper binaries (NSSM 2.24) are validated against official cryptographic SHA256 checksums before installation.
- Corrupted or modified binaries trigger an immediate fatal error and are purged from disk.

### 4. Public Key Pinning (RFC 7469)
- Server certificates are pinned using RFC 7469 SHA256 hashes (`pin-sha256`).
- This eliminates the need for unsafe flags such as `--no-cert-check`, protecting against TLS interception and MITM attacks on untrusted networks.

---

## Reporting a Vulnerability

If you discover a security vulnerability in `openconnectsg`, please **do NOT report it through public GitHub issues**.

Instead, report it via:
1. **GitHub Security Advisories**: Navigate to the **Security** tab of this repository and select **Report a vulnerability**.
2. Or contact the maintainers directly via repository security contacts.

Please include:
- A clear description of the vulnerability.
- Steps to reproduce the issue.
- Potential impact and suggested mitigations.

We will acknowledge receipt within 48 hours and provide an estimated remediation timeline.
