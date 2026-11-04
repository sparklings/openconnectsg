# OpenConnectSg

> PowerShell automation wrapper for OpenConnect on Windows: DPAPI-secured, NSSM background service daemon with Wintun support and multi-profile management.

프로젝트 공식 명칭은 **OpenConnectSg** 로 정의하며, 실행 명령·스크립트 소스코드·문서 및 내부 식별자는 모두 소문자 `openconnectsg`로 표기합니다.

`openconnectsg`은 Windows 환경에서 `openconnect.exe` CLI 도구를 사용할 때 발생하는 반복적인 수작업(매번 비밀번호 입력, 콘솔 창 유지, 다중 접속 관리, 재부팅 시 수동 재연결)을 제거하기 위한 PowerShell 기반 백그라운드 서비스 자동화 도구입니다.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11%2FServer-blue.svg)]()
[![Shell: PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)]()
[![Version: v0.1.3a](https://img.shields.io/badge/Version-v0.1.3a-green.svg)](CHANGELOG.md)

---

## Key Features

* **멀티 벤더 자동 감지 및 지원**: Cisco AnyConnect (Firepower/ASA) 및 Fortinet FortiGate SSL-VPN 게이트웨이 시그니처를 패킷 및 인증서 레벨에서 자동 판별
* **Cisco 터널 그룹(AuthGroup) 자동 수집**: WebVPN 포털에서 운영 중인 터널 그룹을 실시간으로 질의하여 마법사에서 선택 제공
* **백그라운드 무중단 데몬**: NSSM 2.24와 결합하여 터미널 창을 띄우지 않고 Windows 서비스로 구동하며, OS 부팅 시 자동 연결
* **DPAPI 비밀번호 암호화 보관**: Windows DPAPI(`LocalMachine`)를 통해 암호를 `pw.bin`에 암호화 저장하고 `icacls`로 접근을 통제
* **Wintun 커널 터널링**: WireGuard Wintun 고속 가상 인터페이스와 `vpnc-script-win.js`를 통한 안정적인 Split Routing 구성
* **단일 터널 보장**: 전역 뮤텍스로 세션 충돌을 원천 방지

---

## Documentation Hub

본 프로젝트는 산출물 및 기능별로 세분화된 전용 문서를 제공합니다. 상세 내용은 아래 개별 문서를 참조하십시오:

| 기능 / 도메인 | 대상 산출물 파일 | 주요 내용 및 링크 |
| :--- | :--- | :--- |
| **시스템 아키텍처** | `src/openconnectsg.ps1` | [시스템 구조 및 코어 설계](docs/architecture.md)<br>통합 데몬 러너, Wintun 터널 메커니즘, 프로세스 수명주기 |
| **설치 및 배포** | `install/install-openconnectsg.ps1` | [배포 및 설치 가이드](docs/install-guide.md)<br>온라인/오프라인 환경별 배포 절차, 환경변수(PATH) 및 시스템 요구사항 |
| **CLI 커맨드 레퍼런스** | `src/openconnectsg.cmd` | [서브커맨드 전체 매뉴얼](docs/subcommand-manual.md)<br>13개 서브커맨드 명세, 단축 별칭, 파라미터 및 TUI 출력 규격 |
| **보안 및 자격 증명** | `src/init-openconnectsg.ps1`<br>`pw.bin`, `pin.txt` | [보안 및 자격 증명 관리](docs/security-credentials.md)<br>DPAPI LocalMachine 암호화, icacls 권한 잠금, pin-sha256 지문 고정 |
| **DPAPI 심층 기술 가이드** | `.NET ProtectedData`<br>`pw.bin` | [DPAPI 심층 기술 가이드](docs/dpapi-technical-guide.md)<br>DPAPI 키 도출 구조, LocalMachine 스코프, 무인 데몬 주입 설계 |
| **icacls 접근 제어 가이드** | `icacls.exe`<br>`NTFS DACL` | [icacls 접근 제어 가이드](docs/icacls-technical-guide.md)<br>NTFS 보안 모델, 상속 완전 차단(/inheritance:r), Well-Known SID 하드닝 |
| **장애 진단 및 트러블슈팅** | `profiles/<service>/logs/*` | [장애 진단 및 문제 해결 가이드](docs/troubleshooting.md)<br>로그 분석법, Wintun 어댑터 0x102 타임아웃 해결, 계정 잠금 대응 |
| **버전 및 변경 이력** | 전체 프로젝트 리포지토리 | [변경 이력 (CHANGELOG.md)](CHANGELOG.md)<br>버전별(v0.1.0 ~ v0.1.3a) 추가/수정/보안 패치 및 산출물 추적 |

---

## Quick Start

### 1) Clone Repository and System Installation
관리자 권한으로 PowerShell 다음의 명령을 실행합니다:

```powershell
# 1. 저장소 clone
git clone https://github.com/sparklings/openconnectsg.git "C:\Program Files\OpenConnect\repo"

# 2. 시스템 배포 (C:\Program Files\OpenConnect\bin 자동 배치 및 PATH 등록)
powershell -ExecutionPolicy Bypass -File "C:\Program Files\OpenConnect\repo\install\install-openconnectsg.ps1"
```

### 2) Profile Setup in New Terminal (Interactive Wizard)
새 PowerShell 창을 열고 설정 마법사를 실행합니다:
```powershell
openconnectsg setup
```
> 서버 주소, 포트, 계정, 비밀번호를 입력하면 NSSM·openconnect 의존성 검증, 비밀번호 DPAPI 암호화 및 서비스 등록이 원스톱으로 진행됩니다.

### 3) Routine VPN Operations
```powershell
openconnectsg list                 # 등록된 프로필 목록 및 연결 상태 확인
openconnectsg connect 1            # 1번 프로필로 연결 (기존 활성 터널 자동 해제)
openconnectsg alias 1 office       # 1번 프로필에 'office' 별칭 부여
openconnectsg connect office       # 별칭으로 간편 연결
openconnectsg disconnect all       # 모든 활성 VPN 연결 해제
```

---

## Quick Command Reference

| 명령어 | 단축 별칭 | 설명 |
|---|---|---|
| `openconnectsg list` | `ls` | 등록된 프로필 및 런타임 연결 상태 표 출력 |
| `openconnectsg status [<p>]` | - | 특정 프로필의 런타임 상태 단일 라인 조회 |
| `openconnectsg connect [<p>]` | `up`, `start` | 지정 프로필로 VPN 터널 연결 (단일 연결 강제) |
| `openconnectsg disconnect [<p\|all>]` | `down`, `stop` | 지정 프로필 또는 전체 활성 터널 안전 해제 |
| `openconnectsg setup` | `add` | 새 VPN 프로필 추가 대화형 설정 마법사 |
| `openconnectsg alias <p> <별칭>` | `label` | 프로필에 호출용 별칭 부여 |
| `openconnectsg default <p>` | - | 기본 접속 대상 프로필 포인터 지정 |
| `openconnectsg remove <p>` | `rm`, `delete` | 프로필 구성 삭제 및 Windows 서비스 영구 등록 해제 |
| `openconnectsg upgrade [<p>]` | `update` | 최신 소스로 바이너리 업그레이드 및 버전 검증 (`--force` 지원) |
| `openconnectsg uninstall [<s\>]` | `un`, `purge` | 도구 제거 (범위: `app` 앱 전용 삭제, `full` 전체 완전 삭제) |
| `openconnectsg version` | `-v` | 현재 버전 및 시스템 정보 출력 (`0.1.3a`) |
| `openconnectsg banner` | - | 웰컴 Slant ASCII Figlet 배너 출력 |
| `openconnectsg help` | `-h` | CLI 도움말 및 배너 출력 |

> 각 명령어의 상세 옵션 및 TUI 출력 화면은 [서브커맨드 전체 매뉴얼](docs/subcommand-manual.md)을 참조하십시오.

---

## Latest Release Information (v0.1.3a)

* **멀티 벤더 자동 감지 (Cisco AnyConnect & Fortinet SSL-VPN)**: `openconnectsg setup` 실행 시 게이트웨이 주소만 입력하면 TLS 인증서, HTTP 헤더/쿠키, 리다이렉트 응답을 분석하여 Cisco 및 Fortinet 게이트웨이를 자동 감지하고 최적 프로필을 구성합니다.
* **Cisco 터널 그룹(AuthGroup) 자동 탐색**: Cisco WebVPN 로그온 포털에서 운영 중인 터널 그룹 목록을 탐색하여 손쉽게 선택할 수 있도록 지원합니다.
* **프로토콜 및 그룹 가시성 강화**: `openconnectsg list` 명령에 `PROTO` 컬럼을 신설하고, `openconnectsg status`에서 프로토콜 및 그룹 상세 정보를 표기합니다.

전체 버전별 세부 변경 사항은 [CHANGELOG.md](CHANGELOG.md)에서 확인하실 수 있습니다.

---

## Dependencies and Prerequisites

`openconnectsg setup` 실행 시 공식 체크섬을 검증하여 자동으로 다운로드 및 배치됩니다:
* **[OpenConnect CLI v9.21 (MinGW64-GnuTLS)](https://www.infradead.org/openconnect/)**: SSL-VPN 터널링 연결 수립
* **[NSSM 2.24](https://nssm.cc/)**: Windows 서비스 수명주기 감시 및 데몬화 관리 (SHA256 체크섬 검증)
* **PowerShell 5.1+**: 관리자 권한 필수

---

## LLM & AI Agent Indexing (AI Ingestion)

* **간략 요약 명세**: [`llms.txt`](llms.txt)
* **심층 아키텍처 및 구현 명세**: [`llms-full.txt`](llms-full.txt)
* **AI 코딩 에이전트 제약 규칙**: [`.github/copilot-instructions.md`](.github/copilot-instructions.md)
* **소프트웨어 메타데이터**: [`CITATION.cff`](CITATION.cff)

---

## License

본 프로젝트는 [MIT License](LICENSE)에 따라 자유롭게 사용, 수정 및 배포할 수 있습니다.

---

## Trademark Disclaimer

> **Disclaimer**: All product names, logos, and brands are property of their respective owners. Fortinet® and FortiGate® are registered trademarks of Fortinet, Inc. Use of these names in this project is strictly for interoperability demonstration and does not imply any affiliation, sponsorship, or endorsement.
