# openconnectsg — OpenConnect 원격접속 자동화 (v3.0.0)

원격VPN서버 뒤 원격 내부 네트워크 서버자원에 **NSSM + openconnect CLI**로 자동 접속하는 Windows용 경량 CLI 도구.
초기 프로필 설정부터 백그라운드 데몬 서비스 운영까지 단일 명령 `openconnectsg`로 수행합니다.

---

## 1. 개요

- 매번 비밀번호를 입력하던 원격VPN서버 접속을, 비밀번호를 **DPAPI로 봉인**해 두고 윈도OS 부팅 시 자동 접속하도록 구성합니다.
- 접속은 `openconnect.exe`가 수행하고, 서비스 등록·감시·재시작은 **NSSM 2.24**가 담당합니다.
- 초기 환경 설정(`setup`)과 일상적인 운영(`list`, `connect`, `disconnect` 등)을 **단일 CLI `openconnectsg`**로 통일했습니다.

### 요구 사항

| 항목 | 요구 |
|---|---|
| OS | Windows 10/11 (x64) 또는 Windows Server 2016+ |
| PowerShell | 5.1 이상 (`ProtectedData` 및 NSSM 서비스 제어) |
| 권한 | 관리자 권한 (설치 및 Windows Service 등록 시 필수) |
| 네트워크 | 외부 다운로드(NSSM, openconnect) 연결 |

---

## 2. 아키텍처와 동작 원리

```
[윈도OS 부팅 / 시작]
   └ NSSM 관리 서비스 openconnect_<host>_<port>_<tag8>  (자동 시작)
        └ openconnectsg.ps1 service-run <서비스명>  (통합 데몬 러너)
             ├ profiles\<서비스명>\pw.bin  ── DPAPI(LocalMachine) 복호화 ──▶ 비밀번호 (stdin)
             ├ profiles\<서비스명>\openconnect.conf (--config)
             └ openconnect.exe --config … --passwd-on-stdin  ──▶ 원격VPN서버
```

- **통합 데몬 러너**: 이전 버전의 동적 래퍼 스크립트 생성 방식을 완전히 제거하고, `openconnectsg.ps1 service-run` 내부 서브커맨드가 단일화된 진입점으로 실행됩니다.
- **서비스명**: `openconnect_<host>_<port>_<tag8>`, `tag8` = `SHA256("<host>|<port>|<user>")[0..8]`.
- **프로필 디렉터리**: `profiles\<서비스명>\` — `openconnect.conf`·`user.txt`·`pin.txt`·`pw.bin`·`label.txt`·`logs\`.
- **래퍼 흐름**: 전역 뮤텍스(`Global\<서비스명>`) $\rightarrow$ `pw.bin` DPAPI 복호화 $\rightarrow$ openconnect 프로세스 stdin 전달 $\rightarrow$ 종료코드 전파.

### 비밀번호 보호 (DPAPI LocalMachine)

- `ProtectedData.Protect(평문, LocalMachine)`으로 바이트화해 `pw.bin`에 저장합니다. 디스크나 로그에 평문이 남지 않습니다.
- 생성 즉시 `icacls`를 통해 **SYSTEM 및 로컬 Administrators만** 읽을 수 있도록 ACL을 잠급니다.

### 지문 고정 (pin-sha256)

- 서버 인증서는 RFC 7469 공개키 지문(`pin-sha256`)으로 고정합니다.
- 자체서명 인증서 환경에서 발생하는 `signer not found` 경고를 안전하게 흡수하고 변조를 방지합니다.

---

## 3. 저장소 구조

| 경로 | 설명 |
|---|---|
| `README.md` | 프로젝트 소개 및 빠른 시작 |
| `LICENSE` | MIT 라이선스 |
| `.gitignore` | 기밀 및 런타임 파일 커밋 방지 규칙 |
| `src\openconnectsg.ps1` | 통합 CLI 디스패처 및 서비스 데몬 러너 |
| `src\openconnectsg.cmd` | PATH 등록용 셔틀 |
| `src\init-openconnectsg.ps1` | 프로필 등록 마법사 및 의존성 검증기 |
| `install\install-openconnectsg.ps1` | 시스템 배포 및 PATH 등록 프로그램 |
| `docs\openconnectsg.md` | 아키텍처 및 상세 기술 문서 (본 문서) |
| `docs\commands.md` | 서브커맨드 레퍼런스 매뉴얼 |
| `docs\install-guide.md` | 배포 및 설치 가이드 |

런타임 경로(설치 후):

| 위치 | 내용 |
|---|---|
| `C:\Program Files\OpenConnect\bin` | 배포 바이너리 및 CLI 스크립트 |
| `C:\Program Files\OpenConnect\profiles\<서비스명>` | 프로필 구성, 암호화 키, 입출력 로그 |
| `C:\Program Files\nssm\nssm.exe` | NSSM 2.24 (SHA256 검증 완료) |

---

## 4. 빠른 시작

```powershell
# 1) 저장소 복제 및 설치
git clone https://github.com/sparklings/openconnectsg.git "C:\Program Files\OpenConnect\repo"
powershell -ExecutionPolicy Bypass -File "C:\Program Files\OpenConnect\repo\install\install-openconnectsg.ps1"

# 2) 새 터미널에서 프로필 등록 마법사 실행
openconnectsg setup

# 3) 연결 및 상태 확인
openconnectsg list
openconnectsg connect 1
```

---

## 5. 문제 해결

### 로그 확인
```powershell
Get-Content "C:\Program Files\OpenConnect\profiles\<서비스명>\logs\err.log" -Tail 50
Get-Content "C:\Program Files\OpenConnect\profiles\<서비스명>\logs\out.log" -Tail 50
```

- 인증 실패 반복 $\rightarrow$ `openconnectsg setup`으로 계정 및 비밀번호 재등록.
- 지문 불일치 $\rightarrow$ `profiles\<서비스명>\pin.txt` 갱신.
- 다중 연결 해제 $\rightarrow$ `openconnectsg disconnect all`.
