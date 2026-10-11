# OpenConnectSg

> 프로젝트명은 **OpenConnectSg**로 정의하며, 실행 명령·스크립트 소스코드·문서 및 내부 식별자는 모두 소문자 `openconnectsg`로 표기합니다.

**Automated, DPAPI-Secured OpenConnect Windows Service Manager for Remote VPN Access.**  
원격VPN서버(Fortinet SSL-VPN 호환) 환경에서 무거운 GUI 클라이언트 없이, NSSM 백그라운드 서비스 및 Windows DPAPI 암호화로 원클릭·자동 접속을 수행하는 Windows 전용 오픈소스 CLI 도구입니다.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11%2FServer-blue.svg)]()
[![Shell: PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)]()
[![Security: DPAPI](https://img.shields.io/badge/Security-Windows%20DPAPI-green.svg)]()
[![Daemon: NSSM 2.24](https://img.shields.io/badge/Daemon-NSSM%202.24-orange.svg)]()

---

## 📌 왜 openconnectsg 인가? (Comparison)

| 비교 항목 | 기존 공식 GUI 클라이언트 | openconnectsg (본 도구) |
|---|---|---|
| **실행 형태** | 무거운 트레이 아이콘 GUI 프로그램 상주 | **Windows Service (NSSM) 백그라운드 데몬** |
| **부팅 시 자동 연결** | 윈도우 로그인 후 수동 접속/인증 필요 | **OS 부팅 즉시 백그라운드 자동 터널링** |
| **비밀번호 관리** | 브라우저/레지스트리 평문 노출 위험 | **Windows DPAPI (LocalMachine) 바이트 암호화 봉인** |
| **자체서명 인증서** | 매번 '신뢰할 수 없는 인증서' 팝업 발생 | **RFC 7469 `pin-sha256` 자동 프로빙 및 지문 고정** |
| **다중 계정/프로필** | 계정 전환 시 로그아웃/재입력 번거로움 | **프로필별 독립 관리 및 `openconnectsg connect <별칭>` 전환** |
| **터널 충돌 방지** | 수동으로 이전 연결 종료 필요 | **단일 터널 정책(Single-Tunnel Policy)으로 자동 상호 배제** |

---

## 🚀 주요 기능 (Key Features)

- **백그라운드 서비스 자동화**: NSSM 2.24를 기반으로 Windows 서비스로 자동 등록되어 부팅 시 자동 재연결, 장애 시 자동 재기동, 입출력 로그 로테이션을 지원합니다.
- **철저한 자격증명 보안 (Zero-Plaintext)**: Windows DPAPI(`ProtectedData`)를 사용하여 비밀번호를 암호화해 저장하며, SYSTEM 및 Administrators 권한으로 ACL을 잠급니다.
- **인증서 지문 자동 고정**: 자체서명 인증서 환경에서도 `signer not found` 경고를 우회하기 위해 RFC 7469 SHA256 핀을 자동 획득하여 무결성을 검증합니다.
- **공급망 보안 (Supply Chain Integrity)**: 설치 시 외부 바이너리(NSSM 등)에 대해 내장된 공식 SHA256 체크섬을 검증하여 파일 변조를 차단합니다.
- **간결한 CLI UX**: `openconnectsg list`, `connect`, `disconnect`, `setup`, `alias`, `rm` 등 현대적인 직관적 명령어를 제공합니다.

---

## 📋 시스템 요구 사항 (Prerequisites)

- **OS**: Windows 10, Windows 11 (x64) 또는 Windows Server 2016 이상
- **셸 환경**: Windows PowerShell 5.1 이상 (관리자 권한 필수)
- **네트워크**: 초기 설치 시 의존성 바이너리 다운로드를 위한 인터넷 연결

---

## 📂 저장소 구조 (Repository Structure)

```
openconnectsg/
├── .github/                  # GitHub 워크플로 및 이슈 템플릿
├── docs/
│   ├── commands.md           # 서브커맨드 및 별칭 전체 레퍼런스 매뉴얼
│   ├── install-guide.md      # 온라인/오프라인 환경별 배포 가이드
│   └── openconnectsg.md      # 시스템 아키텍처 및 내부 원리 상세 문서
├── install/
│   └── install-openconnectsg.ps1 # 자동 배포 및 시스템 PATH 등록 프로그램
├── src/
│   ├── openconnectsg.ps1     # 메인 CLI 디스패처 및 통합 서비스 데몬 러너
│   ├── openconnectsg.cmd     # 시스템 PATH 등록용 실행 셔틀
│   └── init-openconnectsg.ps1 # 프로필 설정 마법사 및 무결성 검증기
├── .gitattributes            # CRLF 라인 엔딩 규칙
├── .gitignore                # 기밀(pw.bin) 및 로그 커밋 차단
├── LICENSE                   # MIT License
├── llms.txt                  # LLM 및 AI 에이전트 전용 아키텍처 명세
└── README.md                 # 프로젝트 개요 및 빠른 시작 가이드
```

---

## ⚡ 빠른 시작 (Quick Start)

### 1) 저장소 다운로드 및 시스템 설치
관리자 권한 PowerShell에서 1회 실행합니다:

```powershell
# 1. 저장소 clone
git clone https://github.com/sparklings/openconnectsg.git "C:\Program Files\OpenConnect\repo"

# 2. 시스템 배포 (C:\Program Files\OpenConnect\bin 자동 배치 및 PATH 등록)
powershell -ExecutionPolicy Bypass -File "C:\Program Files\OpenConnect\repo\install\install-openconnectsg.ps1"
```

### 2) 새 터미널에서 프로필 등록 (대화형 마법사)
새 PowerShell 창을 열고 설정 마법사를 실행합니다:
```powershell
openconnectsg setup
```
> 서버 주소, 포트, 계정, 비밀번호를 입력하면 NSSM·openconnect 의존성 검증, 비밀번호 DPAPI 암호화 및 서비스 등록이 원스톱으로 진행됩니다.

### 3) 일상적인 VPN 운영
```powershell
openconnectsg list                 # 등록된 프로필 목록 및 연결 상태 확인
openconnectsg connect 1            # 1번 프로필로 연결 (기존 활성 터널 자동 해제)
openconnectsg alias 1 office       # 1번 프로필에 'office' 별칭 부여
openconnectsg connect office       # 별칭으로 간편 연결
openconnectsg disconnect all       # 모든 활성 VPN 연결 해제
```

---

## 📖 CLI 명령어 요약 (Subcommand Reference)

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
| `openconnectsg version` | `-v` | 현재 버전 출력 (`3.0.0`) |
| `openconnectsg help` | `-h` | CLI 도움말 화면 출력 |

자세한 사용법은 [서브커맨드 매뉴얼](docs/commands.md)을 참조하십시오.

---

## ❓ 자주 묻는 질문 (FAQ)

### Q1. 시스템 재부팅 후에도 자동으로 VPN이 연결되나요?
네. Windows 서비스 등록 시 `SERVICE_AUTO_START`로 구성되어 있으므로, 사용자가 윈도우에 로그인하지 않은 상태에서도 OS 부팅과 동시에 백그라운드 터널이 형성됩니다.

### Q2. 비밀번호를 변경하려면 어떻게 해야 하나요?
`openconnectsg setup`을 다시 실행하여 동일한 서버 주소와 계정으로 새 비밀번호를 입력하면, 기존 서비스와 `pw.bin`이 최신 암호로 자동 갱신됩니다.

### Q3. 다중 모니터링 환경에서 특정 서버만 터널링할 수 있나요?
네. 프로필별로 다중 등록이 가능하며, `openconnectsg connect <alias>`로 원하는 터널로 단일 전환할 수 있습니다.

---

## 🔒 필요 의존성 패키지 (Dependencies)

`openconnectsg setup` 실행 시 공식 체크섬을 검증하여 자동으로 다운로드 및 배치됩니다:
- **NSSM (Non-Sucking Service Manager) 2.24**: Windows 서비스 수명주기 감시 및 데몬화 관리
- **openconnect CLI v9.21 (MinGW64-GnuTLS)**: SSL-VPN 터널링 연결 수립

---

## 📄 라이선스 (License)

본 프로젝트는 [MIT License](LICENSE)에 따라 자유롭게 사용, 수정 및 배포할 수 있습니다.