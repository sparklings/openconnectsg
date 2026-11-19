# OpenConnectSg Development Todo & Roadmap

이 문서는 OpenConnectSg의 기능 개발 로드맵 및 향후 구현 과제를 관리하는 작업 목록입니다.

---

## 📌 [Feature] Host Bookmark & Auto-VPN Dispatcher (호스트 북마크 및 자동 VPN 실행기)

### 1. 개요 및 기획 배경
- **배경**: 사내/원격 인프라의 서버(SSH), 관리 콘솔(Web), 내부 서비스에 접근하기 위해 사용자가 먼저 특정 VPN 프로필에 수동으로 연결한 후, 별도로 터미널이나 웹 브라우저를 열어 주소를 입력해야 하는 번거로움이 존재함.
- **목표**: 
  - 특정 내부 호스트(IP/도메인, 포트, 프로토콜, 로그인 계정 등) 정보를 북마크로 등록하고 관리(CRUD)함.
  - 각 호스트를 특정 VPN 프로필에 매핑함.
  - 호스트 북마크 선택(호출) 시, **매핑된 VPN 연결 상태를 자동으로 확인하여 미연결 시 자동 접속**하고, 터널이 수립되면 **SSH 클라이언트 또는 웹 브라우저를 즉시 기동**하여 원클릭 접속 환경을 제공함.

---

### 2. 상세 기능 개발 요구사항 (Functional Requirements)

#### FR-01. 북마크 데이터 모델 및 영속성 관리 (Data Layer)
- [ ] **저장 위치 (`OpenConnectSg` 기준 표준화)**:
  - **기본 저장소 (사용자별/권한 격리)**: `%LOCALAPPDATA%\OpenConnectSg\bookmarks.json`
    - UAC(관리자 권한) 없이 일반 사용자 권한으로 실행되는 CLI/트레이 GUI에서도 자유롭게 북마크 CRUD가 가능하도록 보장.
  - **머신 전역 공유 저장소 (옵션/시스템 공용)**: `C:\ProgramData\OpenConnectSg\bookmarks.json`
    - 다중 사용자가 공용 호스트 목록을 공유해야 하는 엔터프라이즈/서버 환경용.
  - **배포 및 관리자 오버라이드 경로**: `C:\Program Files\OpenConnectSg\bookmarks.json` (또는 `C:\Program Files\OpenConnect\openconnectsg\bookmarks.json`)
  - *저장소 탐색 우선순위 (Cascading Resolution)*:
    1. 환경 변수/명령행 지정 경로 (`--file <path>`)
    2. 로컬 사용자 저장소 (`%LOCALAPPDATA%\OpenConnectSg\bookmarks.json`)
    3. 시스템 공용 저장소 (`%ProgramData%\OpenConnectSg\bookmarks.json`)
- [ ] **JSON 스키마 정의**:
  ```json
  [
    {
      "id": "bm-prod-web01",
      "name": "Prod Web Server 01",
      "host": "10.20.1.15",
      "port": 22,
      "protocol": "ssh",
      "vpnProfile": "seoul-dc",
      "user": "ubuntu",
      "autoConnect": true,
      "connectTimeout": 15,
      "description": "Production Web Cluster Node 1",
      "tags": ["prod", "web", "linux"],
      "createdAt": "2026-11-20T09:00:00Z"
    },
    {
      "id": "bm-corp-wiki",
      "name": "Internal Confluence Wiki",
      "host": "wiki.internal.corp",
      "port": 443,
      "protocol": "https",
      "path": "/dashboard.action",
      "vpnProfile": "corp-vpn",
      "autoConnect": true,
      "description": "Company Knowledge Base",
      "tags": ["corp", "wiki"],
      "createdAt": "2026-11-20T09:00:00Z"
    }
  ]
  ```
- [ ] **데이터 검증 (Validation)**:
  - `name`, `host`, `protocol`, `vpnProfile` 필수 입력 검증.
  - `protocol`: `ssh`, `http`, `https`, `rdp` 지원.
  - `vpnProfile`이 실제 등록된 프로필(`Get-Profiles`)에 존재하는지 무결성 검증.
  - 포트 번호 범위 검증 (1 ~ 65535, 미입력 시 프로토콜 기본 포트 22/80/443/3389 자동 부여).

#### FR-02. CLI 서브커맨드 (`openconnectsg bookmark` / `bm`)
- [ ] **CRUD 명령어 체계 구현**:
  - `openconnectsg bookmark list` (별칭: `ls`): 등록된 북마크 목록, 매핑된 VPN, 프로토콜, 타겟 주소 테이블 뷰 출력.
  - `openconnectsg bookmark add`: 대화형 마법사 또는 인라인 플래그(`-Name`, `-Host`, `-Proto`, `-Vpn`, `-User`, `-Port`)를 통한 북마크 등록.
  - `openconnectsg bookmark edit <name|id>`: 기존 북마크의 속성 변경.
  - `openconnectsg bookmark remove <name|id>` (별칭: `rm`): 북마크 삭제.
  - `openconnectsg bookmark show <name|id>`: 단일 북마크 세부 정보 및 매핑 상태 출력.
- [ ] **실행 명령어 (`openconnectsg open` / `bookmark open`)**:
  - `openconnectsg open <name|id>`: 북마크를 즉시 실행 (VPN 자동 연결 $\rightarrow$ 클라이언트 기동).
  - 옵션: `--no-connect` (VPN 미연결 시 자동 접속하지 않고 경고 후 중단), `--dry-run` (실행 커맨드만 출력).

#### FR-03. 자동 VPN 감지 및 디스패처 엔진 (Connection & Execution Engine)
- [ ] **터널 상태 확인**:
  - 선택한 북마크의 `vpnProfile`이 현재 활성화(`Connected`) 상태인지 점검.
  - 이미 해당 VPN이 연결된 경우: 즉시 호스트 실행 단계로 진행.
  - 다른 VPN이 연결되어 있는 경우: 충돌 방지 정책 (기존 VPN 유지 여부 경고 또는 사용자 확인 후 전환).
- [ ] **자동 접속 수행 (`autoConnect: true`)**:
  - `Do-Connect -Profile $vpnProfile` 내부 루틴 호출.
  - Wintun 어댑터 생성, IP 할당, 라우트 테이블 반영 완료까지 대기 (최대 타임아웃 감시).
- [ ] **프로토콜별 클라이언트 실행 핸들러**:
  - **SSH (`protocol: ssh`)**:
    - Windows 기본 OpenSSH (`ssh.exe`) 또는 Windows Terminal(`wt.exe -p "PowerShell" ssh ...`) 연동.
    - 계정 파라미터가 있을 경우 `ssh -p <port> <user>@<host>` 실행.
    - SSH 개인키 또는 추가 파라미터 옵션 지원.
  - **Web (`protocol: http | https`)**:
    - `Start-Process "$protocol://$host:$port$path"`를 통해 기본 웹 브라우저(Chrome/Edge/기본값)로 URL 호출.
  - **RDP (`protocol: rdp`)**:
    - Windows 원격 데스크톱 연결 `mstsc.exe /v:<host>:<port>` 자동 기동 지원.

#### FR-04. 트레이 GUI (`openconnectsg-tray.ps1`) 연동
- [ ] **트레이 컨텍스트 메뉴 (우클릭)**:
  - "Bookmarks" 서브메뉴 추가.
  - 프로필별 서브메뉴 그룹화: `Bookmarks -> [Seoul DC] -> Prod Web 01 (SSH)` 형태.
  - 클릭 1회로 백그라운드 VPN 확인/연결 후 터미널/브라우저 론칭.
- [ ] **메인 트레이 대시보드 UI**:
  - 'Bookmarks' 탭 또는 전용 리스트뷰 추가.
  - 북마크 추가/수정/삭제 다이얼로그(WinForms) 제공.
  - 호스트별 'Quick Connect' 실행 버튼 및 핑(Ping) 헬스체크 상태 표시.

#### FR-05. 예외 처리 및 안전장치
- [ ] **네트워크 도달 가능성 검증**:
  - VPN 연결 직후 호스트 TCP 포트 오픈 확인(`Test-NetConnection -ComputerName $host -Port $port -WarningAction SilentlyContinue`)을 옵션으로 제공하여 연결 실패 시 친절한 오류 안내.
- [ ] **자격 증명 보안**:
  - 북마크에 평문 패스워드를 저장하지 않고, SSH Key 또는 브라우저/시스템 자격 증명 관리자에 위임.

---

### 3. 단계별 개발 계획 (Development Phases)

- [ ] **Phase 1: 데이터 모델 및 기본 스토리지 엔진 구현**
  - `OpenConnectSg` 네임스페이스 기반의 `bookmarks.json` I/O 헬퍼 함수 (`Get-Bookmarks`, `Save-Bookmarks`).
  - 사용자별/시스템 공용 경로 해석 및 자동 디렉터리 생성 로직.
  - 북마크 유효성 검사기 및 프로필 매핑 검증 로직.
- [ ] **Phase 2: CLI 서브커맨드 구현 (`openconnectsg bookmark`, `openconnectsg open`)**
  - `openconnectsg.ps1` 내 `Do-Bookmark` 및 `Do-Open` 디스패처 작성.
  - `list`, `add`, `edit`, `remove`, `open` 서브커맨드 구현.
- [ ] **Phase 3: 프로토콜별 실행 핸들러 및 VPN 터널 연계 검증**
  - SSH (OpenSSH / wt.exe / cmd), Browser (HTTP/HTTPS), RDP 론처 구현.
  - 터널 수립 완료 대기 폴링 및 타임아웃 제어 로직.
- [ ] **Phase 4: 트레이 GUI 연동 (`openconnectsg-tray.ps1`)**
  - 시스템 트레이 컨텍스트 메뉴에 Bookmarks 서브메뉴 반영.
  - 메인 윈도우 북마크 관리 뷰 및 원클릭 버튼 배치.
- [ ] **Phase 5: 문서화 및 통합 테스트**
  - `docs/subcommand-manual.md`에 `bookmark` 및 `open` 매뉴얼 추가.
  - `docs/architecture.md`에 북마크 디스패치 파이프라인 다이어그램 추가.
  - 다양한 네트워크 시나리오(기존 연결 상태, 미연결 상태, 타임아웃 등) 검증.
