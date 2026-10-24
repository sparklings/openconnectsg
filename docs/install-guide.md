# openconnectsg Installation Guide

이 문서는 `openconnectsg`를 Windows 환경에 배포하고 시스템 전역 CLI 명령어로 등록하는 전체 설치 과정과 환경 설정 가이드입니다.

> **관련 문서**: [아키텍처](architecture.md) | [서브커맨드 매뉴얼](subcommand-manual.md) | [보안 및 자격 증명](security-credentials.md) | [트러블슈팅](troubleshooting.md) | [Changelog](../CHANGELOG.md)

---

## 1. System Requirements

설치 전 운영체제 및 실행 환경을 확인하십시오.

| 항목 | 요구 사항 | 비고 |
|---|---|---|
| **운영체제** | Windows 10 / 11 (64-bit) | Windows Server 2016 이상 지원 |
| **PowerShell** | 5.1 이상 | `Windows PowerShell` 기본 탑재 버전 |
| **권한** | 관리자 권한 (Administrator) | 시스템 PATH 등록 및 서비스 배치에 필수 |
| **도구** | Git (Git 설치 환경 권장) | Git 미설치 환경은 오프라인 설치 지원 |
| **네트워크** | 인터넷 연결 | NSSM 및 openconnect 자동 다운로드용 |

---

## 2. Prerequisites

### 2.1. Run PowerShell as Administrator
설치 스크립트는 시스템 `Program Files` 디렉터리에 접근하고 머신 환경 변수를 수정하므로 반드시 **관리자 권한** 으로 실행해야 합니다.

1. `시작` 메뉴 우클릭 $\rightarrow$ **Windows 터미널(관리자)** 또는 **PowerShell(관리자)** 선택
2. PowerShell 버전 확인:
   ```powershell
   $PSVersionTable.PSVersion
   # Major 버전이 5 이상이어야 합니다.
   ```

### 2.2. Execution Policy
PowerShell 스크립트 실행이 제한된 경우 일시적으로 우회 플래그(`-ExecutionPolicy Bypass`)를 추가하여 실행하거나, 정책을 완화합니다:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## 3. Installation Methods

### Method A. Clone Repository and Install (Git Environment)

```powershell
# 1) 저장소를 C:\Program Files\OpenConnect\repo 에 clone
git clone https://github.com/sparklings/openconnectsg.git "C:\Program Files\OpenConnect\repo"

# 2) 설치 스크립트 실행 (bin 자동 배치 및 PATH 등록)
powershell -ExecutionPolicy Bypass -File "C:\Program Files\OpenConnect\repo\install\install-openconnectsg.ps1"
```

### Method B. One-Line Web Automatic Install (Without Git)

Git이나 개발 도구가 없어도 PowerShell 기본 명령어로 원격 최신 코드를 즉시 내려받아 설치합니다:

```powershell
irm https://raw.githubusercontent.com/sparklings/openconnectsg/main/install/install-openconnectsg.ps1 | iex
```

### Method C. Offline / Manual ZIP Download Installation

1. GitHub에서 [ZIP 다운로드](https://github.com/sparklings/openconnectsg/archive/refs/heads/main.zip) 후 압축 해제
2. 압축 해제한 디렉터리 내에서 관리자 권한으로 실행:
```powershell
powershell -ExecutionPolicy Bypass -File .\install\install-openconnectsg.ps1 -SkipClone
```

---

## 4. Post-Installation

### 4.1. Welcome Banner

설치가 성공적으로 완료되면 터미널에 다음과 같은 웰컴 배너와 퀵스타트 가이드가 출력됩니다:

```text
   ____                   ______                            __   _____       
  / __ \____  ___  ____  / ____/___  ____  ____  ___  _____/ /_ / ___/____ _ 
 / / / / __ \/ _ \/ __ \/ /   / __ \/ __ \/ __ \/ _ \/ ___/ __/ \__ \/ __ `/ 
/ /_/ / /_/ /  __/ / / / /___/ /_/ / / / / / / /  __/ /__/ /_   ___/ / /_/ /  
\____/ .___/\___/_/ /_/\____/\____/_/ /_/_/ /_/\___/\___/\__/  /____/\__, /   
    /_/                                                             /____/    
 ==============================================================================
  OpenConnectSg :: Windows Background Daemon & DPAPI Automation Wrapper (v0.1.2d)
 ==============================================================================
  [DEPLOY]   Target   : C:\Program Files\OpenConnect\bin
  [SYSTEM]   PATH     : Successfully registered (Machine Scope)
  [PACKAGES] Required : OpenConnect CLI v9.21, NSSM v2.24
  [FEATURES] Windows DPAPI Encrypted Credential (pw.bin), Wintun Kernel Tunnel Adapter

 ------------------------------------------------------------------------------
  QUICK START INSTRUCTIONS
 ------------------------------------------------------------------------------
  1. Reload PATH in current session (or open a new terminal):
     $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                 [Environment]::GetEnvironmentVariable('Path','User')

  2. Run the interactive setup wizard:
     openconnectsg setup

  3. Connect and verify service status:
     openconnectsg connect
     openconnectsg status

  For all subcommands and syntax: openconnectsg help
 ==============================================================================
```

### 4.2. Command Activation (Important)

Windows는 설치 프로그램(자식 프로세스)이 시스템 PATH를 변경해도 **이미 열려 있는 기존 터미널 세션에는 새 PATH가 자동으로 갱신되지 않습니다**.

* **선택 1 (권장):** **새 PowerShell 창** 을 열면 `openconnectsg` 명령어가 즉시 인식됩니다.
* **선택 2:** 현재 열려 있는 창에서 바로 사용하려면 아래 명령어로 환경 변수를 즉시 다시 로드합니다:
  ```powershell
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
  ```

### 4.3. Verify Installation
```powershell
openconnectsg version
# 출력: openconnectsg 0.1.2d
```

### 4.4. Run Initial Profile Setup Wizard
```powershell
openconnectsg setup
```
- 실행 시 필요한 외부 도구(`NSSM 2.24`, `openconnect v9.21`)가 공식 SHA256 체크섬 검증을 거쳐 자동 다운로드 및 설치됩니다. (공식 사이트 장애 시 검증된 GitHub 미러로 자동 대체)
- 원격VPN서버의 주소, 포트, 계정, 비밀번호를 순서대로 입력하면 .NET 기반 초고속 인증서 Pin(RFC7469) 추출, Windows DPAPI 암호화 및 서비스 등록이 원스톱으로 완료됩니다.

---

## 5. Update

### Method A. Automatic CLI Upgrade (Recommended)
어느 터미널에서나 아래 명령을 실행하면 최신 릴리스 패키지를 자동 다운로드하여 배포 및 서비스를 갱신합니다 (UAC 자동 승격):
```powershell
openconnectsg upgrade
```

### Method B. Manual Repository Update
```powershell
cd "C:\Program Files\OpenConnect\repo"
git pull --ff-only

powershell -ExecutionPolicy Bypass -File .\install\install-openconnectsg.ps1
```

---

## 6. Uninstall

설치된 환경을 깔끔하게 제거할 수 있는 2가지 방법이 제공됩니다:

### Method A. Interactive CLI Removal (`openconnectsg uninstall`)
```powershell
# 관리자 권한 터미널에서 실행
openconnectsg uninstall
```
- **[1] openconnectsg only**: 터널 서비스 중지/해제, 프로필 및 바이너리 삭제, PATH 제거 (OpenConnect CLI와 NSSM은 보존)
- **[2] Full Purge**: 모든 서비스/프로필 삭제 + OpenConnect CLI 및 NSSM 완전 제거 + 시스템 PATH 정리

### Method B. Removal via Install Script
```powershell
# openconnectsg만 제거
powershell -ExecutionPolicy Bypass -File .\install\install-openconnectsg.ps1 -Uninstall -Scope app

# 모든 구성 요소 완전 영구 삭제 (Full Purge)
powershell -ExecutionPolicy Bypass -File .\install\install-openconnectsg.ps1 -Uninstall -Scope full
```

---

## 7. Troubleshooting

### Q1. Error: "The script cannot be executed..."
- **원인**: Windows의 PowerShell ExecutionPolicy가 `Restricted`로 설정되어 있습니다.
- **조치**: 실행 시 `-ExecutionPolicy Bypass` 플래그를 붙여 실행하십시오.

### Q2. Error: "openconnectsg : The term is not recognized as the name of a cmdlet..."
- **원인**: 설치 후 기존 터미널 창을 그대로 사용 중이어서 변경된 PATH가 로드되지 않았습니다.
- **조치**: 현재 터미널 창을 닫고 새 창을 여십시오.

### Q3. Error: "Permission denied" or "Too many bad login attempts"
- **원인**:
  - `Permission denied`: 계정 정보는 유효하나 방화벽 측 SSL-VPN 인가(Authorization) 정책 또는 그룹 권한에 매핑되지 않은 경우입니다.
  - `Too many bad login attempts`: 연속적인 시도로 인해 방화벽의 브루트포스 차단 타이머가 작동한 상태입니다.
- **조치**: 차단 타이머의 경우 3~5분 정도 대기 후 다시 시도하시고, 인가 문제는 네트워크 관리자에게 사용자 계정의 SSL-VPN 접근 그룹 권한을 확인하십시오.
