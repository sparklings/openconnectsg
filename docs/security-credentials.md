# Security & Credentials Specification

본 문서는 **OpenConnectSg**에서 자격 증명(비밀번호, 인증서 지문)을 안전하게 암호화·보관하고, 권한을 제어하는 보안 아키텍처 및 구현 명세를 기술합니다.

---

## 1. Overview & Threat Model

OpenConnectSg는 사용자가 매번 비밀번호를 수동 입력하거나, 일반 텍스트 배치 스크립트에 평문 암호를 노출하는 취약점을 제거하기 위해 설계되었습니다.

### Key Security Objectives
1. **평문 비밀번호 노출 차단**: 디스크, 임시 파일, 커맨드라인 파라미터, 로그 파일에 평문 암호를 남기지 않습니다.
2. **최소 권한 접근 제어 (Least Privilege)**: Windows 접근 제어 목록(ACL)을 적용하여 기밀 파일에 대한 일반 사용자 및 비권한 프로세스의 접근을 원천 차단합니다.
3. **중간자 공격(MITM) 방지**: 자체 서명 인증서나 사설 CA 환경에서도 고유 지문(`pin-sha256`) 고정 기법을 적용하여 인증서 위·변조를 방지합니다.

---

## 2. Credential Encryption: Windows DPAPI

비밀번호는 Windows Data Protection API (DPAPI)의 **`LocalMachine`** 스코프를 통해 암호화되어 바이너리 형태(`pw.bin`)로 저장됩니다.

### Encryption and Decryption Mechanism

* **기술 스택**: `.NET` `System.Security.Cryptography.ProtectedData`
* **보호 스코프**: `DataProtectionScope.LocalMachine`
* **저장 위치**: `C:\Program Files\OpenConnect\profiles\<서비스명>\pw.bin`

#### Encryption Procedure (`src/init-openconnectsg.ps1`)
```powershell
$bytes = [System.Text.Encoding]::UTF8.GetBytes($plainPassword)
$entropy = $null
$encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
    $bytes,
    $entropy,
    [System.Security.Cryptography.DataProtectionScope]::LocalMachine
)
[System.IO.File]::WriteAllBytes($pwBinPath, $encrypted)
```

#### Decryption and Process Streaming (`src/openconnectsg.ps1`)
백그라운드 데몬 서비스 실행 시(`service-run` 또는 `connect`), 암호화된 `pw.bin` 바이트를 읽어 메모리 상에서만 일시적으로 복호화한 후, .NET 전용 UTF-8 표준 입력(`stdin`) 스트림을 통해 `openconnect.exe`로 직결 전달합니다.

```powershell
$encrypted = [System.IO.File]::ReadAllBytes($pwBinPath)
$plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
    $encrypted,
    $null,
    [System.Security.Cryptography.DataProtectionScope]::LocalMachine
)
$plainPw = [System.Text.Encoding]::UTF8.GetString($plainBytes)

# 프로세스 stdin에 직접 전달 후 메모리 해제
$sw.WriteLine($plainPw)
$sw.Flush()
```

> [!NOTE]
> `LocalMachine` 스코프를 사용하는 이유:  
> 서비스가 백그라운드에서 사용자 로그인 없이 OS 부팅 시(`NT AUTHORITY\SYSTEM` 계정) 구동되어야 하므로, 특정 사용자 로그인 세션에 종속되는 `CurrentUser` 스코프 대신 컴퓨터 수준 암호화(`LocalMachine`)를 사용합니다.

---

## 3. File System Access Control (ACL Locking)

`LocalMachine` 스코프로 암호화된 파일은 동일 PC의 다른 관리자 권한 프로세스에서도 이론적으로 복호화가 가능하므로, **파일 시스템 권한을 엄격히 제한**합니다.

`init-openconnectsg.ps1`는 `pw.bin` 생성 즉시 Windows `icacls.exe`를 호출하여 상속 권한을 제거하고 허용 대상을 제한합니다:

```powershell
# 1. 상속 권한 제거
icacls "$pwBinPath" /inheritance:r

# 2. SYSTEM 및 Administrators 그룹에만 Full Access 부여
icacls "$pwBinPath" /grant:r "SYSTEM:(F)"
icacls "$pwBinPath" /grant:r "*S-1-5-32-544:(F)"  # Administrators SID
```

- 일반 사용자 계정이나 표준 권한으로 실행된 애플리케이션은 `pw.bin` 파일에 접근할 수 없습니다.

---

## 4. Certificate Public Key Pinning (RFC 7469 `pin-sha256`)

기업 사설망이나 자체 서명(Self-Signed) 인증서를 사용하는 방화벽(FortiGate 등)에 연결할 때, 인증서 신뢰 경고로 인해 자동 연결이 중단되거나 중간자 공격(MITM)에 노출될 수 있습니다.

### Operational Principle
1. **지문 추출**: `init-openconnectsg.ps1` 마법사 실행 시, 대상 서버의 SSL 인증서로부터 RFC 7469 규격의 `pin-sha256` 해시를 추출합니다.
2. **프로필 저장**: 추출된 지문은 `profiles\<서비스명>\pin.txt` 및 `openconnect.conf`에 기록됩니다:
   ```ini
   servercert = pin-sha256:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=
   ```
3. **런타임 검증**: `openconnect.exe`는 접속 시 서버의 인증서 공개키 해시가 저장된 `pin-sha256`과 정확히 일치하는 경우에만 핸드셰이크를 완료합니다.

---

## 5. Security Audit and Verification Checklist

시스템 관리자는 다음 항목을 정기적으로 점검할 수 있습니다:

| 점검 항목 | 점검 대상 | 정상 기준 |
| :--- | :--- | :--- |
| **`pw.bin` 파일 권한** | `C:\Program Files\OpenConnect\profiles\*\pw.bin` | `SYSTEM` 및 `Administrators`만 접근 허용 |
| **디스크 평문 노출** | `profiles\*\logs\*.log` | 비밀번호 문자열이 로그에 존재하지 않음 |
| **서버 지문 유효성** | `profiles\*\pin.txt` | 유효한 `pin-sha256:` 형식의 base64 해시 존재 |
| **프로세스 통신** | 메모리 및 CLI 인수 | 커맨드라인 인수에 `--passwd-on-stdin` 사용 (인수에 암호 미노출) |
