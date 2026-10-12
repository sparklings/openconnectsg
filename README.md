# OpenConnectSg

> 프로젝트명은 **OpenConnectSg**로 정의하며, 실행 명령·스크립트 소스코드·문서 및 내부 식별자는 모두 소문자 `openconnectsg`로 표기합니다.

Windows 환경에서 `openconnect.exe` CLI 도구를 사용할 때, 반복되는 수작업(매번 비밀번호 입력, 콘솔 창 유지, 다중 접속 관리)을 줄이기 위해 작성된 PowerShell 기반 자동화 도구입니다.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11%2FServer-blue.svg)]()
[![Shell: PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)]()

---

## 📌 프로젝트 소개 및 역할

`openconnectsg`는 독립적인 VPN 클라이언트가 아닙니다. Windows 환경에서 공식 [OpenConnect](https://www.infradead.org/openconnect/)(`openconnect.exe`) CLI 도구를 백그라운드 Windows 서비스로 구동하고 프로필 관리를 보조하기 위해 작성된 **PowerShell 래퍼(Wrapper) 스크립트**입니다.

실제 VPN 터널링 및 모든 네트워크 패킷 처리는 시스템에 설치된 `openconnect.exe`가 전담하며, `openconnectsg`는 다음과 같은 로컬 편의 기능만을 수행합니다:

- **백그라운드 서비스 구동 보조**: NSSM 2.24와 연계하여 터미널 창을 띄워두지 않고 백그라운드 Windows 서비스로 `openconnect.exe`를 실행합니다.
- **DPAPI 비밀번호 암호화 보관**: 매 접속 시 비밀번호를 수동 입력하거나 평문 배치 파일에 적어두지 않도록, Windows DPAPI(`LocalMachine` 스코프)로 암호화하여 로컬 디스크에 보관한 뒤 서비스 기동 시 안전하게 전달합니다.
- **프로필 기반 CLI 관리**: 서버 주소, 포트, 사용자 계정을 프로필별 디렉터리로 관리하며, `connect`, `disconnect`, `alias`, `status` 명령어로 간편하게 제어합니다.
- **자체서명 인증서 지문 고정**: 자체서명 인증서 환경에서 최초 셋업 시 RFC 7469 `pin-sha256` 지문을 확인하여 설정 파일에 저장합니다.
- **클린 삭제 및 초기화(`uninstall`)**: 도구만 삭제(`app`)하거나 외부 의존성(NSSM, OpenConnect CLI)까지 시스템 전체에서 말끔히 정리(`full`)하는 언인스톨러를 내장했습니다.

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
│   ├── subcommand-manual.md  # 서브커맨드 및 별칭 전체 레퍼런스 메뉴얼
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
| `openconnectsg uninstall [<s\>]` | `un`, `purge` | 도구 제거 (범위: `app` 앱 전용 삭제, `full` 전체 완전 삭제) |
| `openconnectsg version` | `-v` | 현재 버전 출력 (`0.1.1a`) |
| `openconnectsg help` | `-h` | CLI 도움말 화면 출력 |

자세한 사용법은 [서브커맨드 메뉴얼](docs/subcommand-manual.md)을 참조하십시오.

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
- **NSSM (Non-Sucking Service Manager) 2.24**: Windows 서비스 수명주기 감시 및 데몬화 관리 (공식 사이트 및 GitHub 백업 미러 이중화 지원, SHA256 체크섬 검증)
- **openconnect CLI v9.21 (MinGW64-GnuTLS)**: SSL-VPN 터널링 연결 수립

---

## 🙏 감사의 글 (Acknowledgments & Credits)

본 프로젝트는 훌륭한 오픈소스 및 플랫폼 생태계가 있었기에 만들어질 수 있었습니다. 핵심 통신 엔진, 윈도우 서비스 관리 및 스크립팅 런타임을 제공해 주신 프로젝트와 엔지니어분들께 깊은 감사를 전합니다:

- **[OpenConnect](https://www.infradead.org/openconnect/)**: 강력하고 신뢰성 높은 다중 프로토콜 VPN 클라이언트를 만들어 주신 OpenConnect 개발진과 기여자 여러분께 진심으로 감사드립니다. 본 도구의 모든 네트워크 터널링과 보안 접속은 전적으로 `openconnect.exe`에 의존하고 있습니다.
- **[NSSM (Non-Sucking Service Manager)](https://nssm.cc/)**: Windows 환경에서 프로세스를 견고한 백그라운드 서비스로 구동할 수 있도록 뛰어난 도구를 제공해 주신 Iain Patterson 님과 NSSM 기여자분들께 감사드립니다.
- **[Microsoft PowerShell](https://github.com/PowerShell/PowerShell)**: Windows 환경에서 시스템 제어, DPAPI 암호화 연동 및 프로세스 오케스트레이션을 유연하고 안정적으로 구현할 수 있는 객체 지향 스크립팅 플랫폼을 제공해 준 Microsoft 및 PowerShell 팀에 감사드립니다.

---

## 📄 라이선스 (License)

본 프로젝트는 [MIT License](LICENSE)에 따라 자유롭게 사용, 수정 및 배포할 수 있습니다.

---

## 🏷️ 검색 키워드 및 메타데이터 (Keywords & SEO Index)

`OpenConnect Windows CLI`, `Fortinet SSL-VPN Automation`, `Windows Background VPN Service`, `NSSM OpenConnect Daemon`, `DPAPI Credential Encryption`, `OpenConnect Auto-Reconnect on Boot`, `Single-Tunnel VPN Orchestrator`, `PowerShell VPN CLI`, `Headless Windows VPN`, `Self-Signed Certificate Pin-SHA256`

---

## 🤖 LLM & AI 에이전트 인덱싱 (AI Ingestion)

이 저장소는 LLM 웹 크롤러 및 AI 코딩 에이전트(Claude, ChatGPT, Cursor, Copilot)를 위해 표준화된 머신 리더블 문서를 제공합니다:
- **간략 요약 명세**: [`llms.txt`](llms.txt)
- **심층 아키텍처 및 내부 구현 명세**: [`llms-full.txt`](llms-full.txt)
- **AI 에이전트 코딩 제약 규칙**: [`.github/copilot-instructions.md`](.github/copilot-instructions.md)
- **보안 및 위협 모델 명세**: [`SECURITY.md`](SECURITY.md)
- **시맨틱 소프트웨어 메타데이터**: [`CITATION.cff`](CITATION.cff)