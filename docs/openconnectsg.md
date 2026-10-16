# openconnectsg — OpenConnect 원격접속 자동화 (v0.1.2d)

원격VPN서버 뒤 원격 내부 네트워크 서버자원에 **NSSM + openconnect CLI**로 자동 접속하는 Windows용 경량 CLI 도구.
초기 프로필 설정부터 백그라운드 데몬 서비스 운영, 클린 삭제(`uninstall`)까지 단일 명령 `openconnectsg`로 수행합니다.

---

## 1. 개요

- 반복적인 비밀번호 입력 과정을 줄이기 위해 Windows DPAPI(LocalMachine)로 비밀번호를 암호화하여 로컬에 보관하고, 서비스 기동 시 자동으로 전달합니다.
- 접속은 `openconnect.exe`가 수행하고, Windows 백그라운드 서비스 등록 및 관리는 **NSSM 2.24**가 담당합니다.
- 프로필 설정(`setup`)과 일상적인 연결·해제(`list`, `connect`, `disconnect`)를 **단일 CLI `openconnectsg`**로 조작합니다.

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
- **래퍼 흐름**: 전역 뮤텍스(`Global\<서비스명>`) $\rightarrow$ `pw.bin` DPAPI 복호화 $\rightarrow$ .NET `ProcessStartInfo` 및 `StreamWriter`를 통한 openconnect 프로세스 stdin 직결 전달 $\rightarrow$ 종료코드 전파.
- **Wintun 가상 어댑터**: Wintun 드라이버를 통해 Windows 커널 수준의 가상 인터페이스를 안정적으로 생성하여 IP 및 분할 라우팅(Split Routing)을 구성합니다.

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
| `docs\subcommand-manual.md` | 서브커맨드 레퍼런스 메뉴얼 |
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

- `Permission denied` 에러 $\rightarrow$ 사용자 계정이 방화벽 측 SSL-VPN 터널 인가 그룹에 포함되어 있는지 확인.
- `Too many bad login attempts` 에러 $\rightarrow$ 방화벽 측 브루트포스 락아웃 정책 발동 상태. 3~5분 대기 후 재시도.
- 인증 실패 반복 $\rightarrow$ `openconnectsg setup`으로 계정 및 비밀번호 재등록.
- 지문 불일치 $\rightarrow$ `profiles\<서비스명>\pin.txt` 갱신.
- 다중 연결 해제 $\rightarrow$ `openconnectsg disconnect all`.
- 완전 삭제 및 초기화 $\rightarrow$ `openconnectsg uninstall` (또는 `-Scope full`).

---

## 6. 버전 및 변경 이력 (Version History)

| 버전 | 일자 | 주요 변경 내용 |
|---|---|---|
| **v0.1.2d** | 2026-10-16 | **업그레이드 버전 검증 및 무중단 보호**: 최신 버전 시 업그레이드 생략 및 실행 중인 서비스 유지, `--force` 강제 배포 옵션 추가, `Compare-VersionString` 시맨틱 버전 비교 탑재, 공식 명칭(`OpenConnectSg`) 준수 확인 |
| **v0.1.2c** | 2026-10-15 | **TUI 인터페이스 일원화**: 전체 서브커맨드에 80컬럼 박스 규격(`====`, `----`) 및 단계별 줄바꿈 적용, 영문 상태 메시지 표준화, 연결 실패 시 원인 분석 진단 블록 추가 |
| **v0.1.2b** | 2026-10-14 | **초기 설치 화면 고도화**: Slant ASCII 아트 기반의 Welcome 메시지 배너 추가, 필수 패키지(`OpenConnect CLI`, `NSSM`) 및 핵심 기능(`DPAPI`, `Wintun`) 안내, 직관적인 Quick Start 가이드 터미널 출력 지원 |
| **v0.1.2a** | 2026-10-13 | 다중 프로필 인덱스/별칭 라우팅 최적화, 전역 뮤텍스 기반 단일 터널 보장, 언인스톨러 스코프(`app`/`full`) 분리, LLM 명세 파일(`llms.txt`, `llms-full.txt`) 탑재 |
| **v0.1.1b** | 2026-10-11 | DPAPI LocalMachine 비밀번호 암호화 보관, NSSM 기반 Windows 서비스 등록 마법사(`init-openconnectsg.ps1`), RFC 7469 인증서 지문 고정 |

