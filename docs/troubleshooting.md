# Troubleshooting & Diagnostic Guide

본 문서는 **OpenConnectSg** 사용 중 발생할 수 있는 주요 네트워크 장애, 프로세스 예외, 인증 실패 및 어댑터 충돌에 대한 원인 분석과 단계별 해결 절차를 안내합니다.

---

## 1. Log File Locations & Real-Time Diagnostics

연결 문제 발생 시 가장 먼저 확인해야 할 산출물은 대상 프로필의 로그 파일입니다.

### Log Storage Directory
```
C:\Program Files\OpenConnect\profiles\<서비스명>\logs\
├── out.log   # openconnect.exe 표준 출력 (연결 성공, IP 할당, 라우팅 테이블)
└── err.log   # openconnect.exe 표준 에러 및 인증 오류, 핸드셰이크 경고
```

### Real-Time Log Monitoring Commands
```powershell
# 특정 프로필의 에러 로그 실시간 추적 (PowerShell)
Get-Content "C:\Program Files\OpenConnect\profiles\<서비스명>\logs\err.log" -Wait -Tail 30

# 최근 50줄 출력
Get-Content "C:\Program Files\OpenConnect\profiles\<service_name>\logs\out.log" -Tail 50
```

---

## 2. Common Errors, Causes & Remediation

### ① Wintun Adapter Creation Timeout (`0x102` / `CreateTun: Wait failed`)
* **현상**: `err.log`에 `Failed to create Wintun adapter: 0x102` 또는 타임아웃 에러가 발생하며 터널이 형성되지 않음.
* **원인**: 이전 세션에서 생성된 가상 어댑터가 비정상 종료되어 잠겨 있거나, 설정 파일에 특정 인터페이스명이 고정(`interface=...`)되어 충돌한 경우.
* **해결책**:
  1. OpenConnectSg v0.1.2a 이상에서는 자체 소독(sanitize) 및 정리 로직이 내장되어 있습니다. 최신 버전으로 업그레이드합니다:
     ```powershell
     openconnectsg upgrade --force
     ```
  2. 잔존 어댑터 수동 정리:
     ```powershell
     openconnectsg disconnect all
     # 네트워크 어댑터 새로고침
     Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*Wintun*" } | Restart-NetAdapter
     ```

### ② `Permission denied` or Authentication Rejection
* **현상**: 로그인 단계에서 인증 거부 발생.
* **원인**: 
  - 비밀번호 오입력 또는 사내 포털 비밀번호 만료.
  - 방화벽(FortiGate 등)에서 해당 계정의 SSL-VPN 접근 그룹 권한이 부여되지 않음.
* **해결책**:
  ```powershell
  # 마법사를 통해 계정/비밀번호 갱신
  openconnectsg setup
  ```

### ③ `Too many bad login attempts` (Account Lockout)
* **현상**: 단시간에 여러 번 재연결을 시도하다가 방화벽 차단 정책에 걸림.
* **원인**: 방화벽(Fortinet 등)의 Brute-force 방어 정책에 의해 3~5분간 임시 블랙리스트에 등록됨.
* **해결책**:
  - 즉각적인 재시도를 멈추고 3~5분 대기 후 시도.
  - 비밀번호가 확실하지 않은 경우 마법사 재등록 전 사내 웹 포털에서 먼저 로그인 가능 여부를 확인.

### ④ Server Certificate Pin Mismatch (`signer not found` / `Certificate pin mismatch`)
* **현상**: 방화벽 장비의 인증서가 갱신되거나 재발급되어 연결이 차단됨.
* **해결책**:
  - `profiles\<서비스명>\pin.txt` 파일을 열어 최신 서버 인증서의 RFC 7469 SHA-256 핀으로 수정하거나,
  - `openconnectsg setup`을 재실행하여 신규 인증서 지문을 자동으로 감지하고 재저장.

### ⑤ Conflict with Existing Running VPN Tunnel
* **현상**: 새 프로필로 연결 시도 시 기존 연결과 라우팅 충돌 발생.
* **해결책**:
  - OpenConnectSg는 단일 터널 원칙(Single-Tunnel Policy)을 강제합니다.
  ```powershell
  # 모든 터널 강제 종료
  openconnectsg disconnect all
  # 원하는 프로필로 재연결
  openconnectsg connect 1
  ```

### ⑥ Fortinet SSL-VPN DTLS Failure & Session Cookie Rejection (`Cookie is no longer valid, ending session` / `Cookie was rejected by server; exiting`)
* **현상**: `err.log`에 `svrhello status was "fail" rather than "ok"`, `Failed to connect DTLS tunnel; using HTTPS instead`, `Cookie is no longer valid, ending session`, `Cookie was rejected by server; exiting.`이 반복되며 VPN 연결이 해제됨.
* **원인**: FortiGate 방화벽의 DTLS 핸드셰이크가 실패하고 OpenConnect가 기존 HTTPS(TLS) 터널로 fallback을 시도하지만, FortiGate의 세션 쿠키 단발성 정책(`reconnect-after-drop is not allowed`)으로 인해 이전 쿠키가 거부되어 세션이 파기됨.
* **해결책**:
  - `openconnect.conf`에 `no-dtls` 옵션을 명시하여 불안정한 DTLS 대신 검증된 표준 TLS 터널로만 연결하도록 강제.
  - OpenConnectSg에서는 `openconnectsg connect` 또는 백그라운드 서비스 기동 시 `protocol=fortinet` 설정에 대해 자동으로 `no-dtls`를 살균·보정하여 영구적인 안정 연결을 보장합니다.

---

## 3. Full Reset & Clean Reinstallation (Purge)

복구가 불가능할 정도로 설정이 꼬인 경우 내장 언인스톨러를 통해 시스템을 정리할 수 있습니다.

```powershell
# 1) 도구 스크립트만 삭제 (프로필 및 의존성은 유지)
openconnectsg uninstall -Scope app

# 2) 프로필, 로그, NSSM 서비스 등록을 포함한 전체 완전 삭제
openconnectsg uninstall -Scope full
```
