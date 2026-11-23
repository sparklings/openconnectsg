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

## 🎨 [Feature] System Tray GUI UI/UX & Reliability Modernization (트레이 GUI 개선)

### 1. 개요 및 개선 배경
- **현행 문제점 분석**:
  - **화면 겹침(Overlap) 및 레이아웃 깨짐**: 창 크기 변경 및 고해상도(DPI 125%/150%) 환경에서 경로 확인 바(`lookBar`)의 긴 텍스트와 하단 푸터(`foot`)의 체크박스/상태 라벨이 겹치거나 화면 밖으로 밀려남.
  - **고정된 화면 분할**: 프로필 목록 영역이 150px(`Absolute`)로 고정되어 프로필/북마크가 많아지면 스크롤이 답답하며, 네트워크 리포트 영역 간 크기 조절이 불가능함.
  - **렌더링 깜빡임(Flicker)**: 3초 주기의 타이머 폴링마다 리스트뷰 항목 전체를 삭제(`Items.Clear()`) 후 재추가하여 화면 깜빡임이 심하고 선택 포커스가 튐.
  - **아이콘 품질 한계**: GDI+ 기본 드로잉(32x32 단일 비트맵)으로 생성되어 고해상도 모니터 및 작업 표시줄 알림 영역에서 경계선이 뭉개지고 시인성이 낮음.
  - **UI 프리징 및 예외 처리 취약성**: 메인 스레드에서의 네트워크 상태 조회 지연, CLI 비동기 프로세스 파일 I/O 잠금 예외, WinForms 모달리스 다이얼로그 처리 미비.

---

### 2. 상세 개선 요구사항 (Functional Requirements)

#### FR-06. 윈도우 폼 레이아웃 및 화면 겹침(Overlap) 완전 해소
- [ ] **반응형 2분할 스플리터 구조 도입 (`SplitContainer`)**:
  - 상단(프로필/북마크 목록)과 하단(네트워크 리포트/경로 분석)을 `SplitContainer`로 분리하여 사용자가 자유롭게 경계선 드래그로 비율 조절 가능하도록 개선.
- [ ] **경로 확인 바(`lookBar`) 겹침 방지 레이아웃 개편**:
  - `WrapContents = $false`로 인한 가로 밀림 현상 해결: 경로 확인 결과를 고정 라벨 대신 자동 줄바꿈 또는 가변 너비 읽기 전용 텍스트박스로 변경하여 텍스트 길이에 따라 하단 컨트롤과 겹치지 않도록 분리.
- [ ] **표준 `StatusStrip` 도입으로 푸터 정리**:
  - 기존 `FlowLayoutPanel` 기반의 `$foot`을 Windows 표준 `StatusStrip` 및 `ToolStripStatusLabel`로 대체.
  - 좌측: 실시간 작업 상태 및 갱신 시간, 우측: 자동 실행 체크박스 및 DPI 배율 정보로 완벽한 좌우 분리 정렬.
- [ ] **DPI 스케일링(Per-Monitor DPI) 최적화**:
  - `AutoScaleMode = Dpi` 환경에서 폰트, 버튼 패딩, 컨트롤 최소/최대 크기(`MinimumSize`, `MaximumSize`)가 96 DPI ~ 192 DPI(100% ~ 200%) 전 구간에서 일그러짐 없이 비례 유지되도록 보정.

#### FR-07. 아이콘 품질 및 비주얼 아이덴티티(Visual Identity) 고도화
- [ ] **멀티 해상도 공식 `.ico` 에셋 도입**:
  - 런타임 32x32 GDI+ 원시 드로잉 방식에서 벗어나 16x16, 24x24, 32x32, 48x48, 64x64, 256x256 멀티 사이즈가 포함된 고화질 전문 아이콘 파일 구축.
  - 100%, 125%, 150%, 200% 디스플레이 스케일별 트레이 영역에서 안티앨리어싱이 완벽 적용된 선명한 아이콘 렌더링.
- [ ] **상태별 비주얼 시인성 강화**:
  - **Connected (연결됨)**: 세련된 에메랄드 그린 + 보안 쉴드/자물쇠 모티프.
  - **Connecting (연결 중)**: 비비드 앰버(Amber) + 애니메이션 느낌의 회전/진행 심볼.
  - **Disconnected (연결 끊김)**: 모던 뉴트럴 슬레이트 그레이.
  - **Warning / Error**: 레드 뱃지 인디케이터.
- [ ] **윈도우 폼 타이틀바 및 작업 표시줄 개별 최적화**:
  - 폼 타이틀바(`Form.Icon`)와 시스템 트레이(`NotifyIcon.Icon`) 간 해상도 불일치 제거.

#### FR-08. 렌더링 깜빡임(Flicker) 제거 및 런타임 안정성 보강
- [ ] **이중 버퍼링(DoubleBuffering) 전면 적용**:
  - `Form`, `ListView`, `TableLayoutPanel`, `SplitContainer`에 리플렉션을 통해 `DoubleBuffered = true` 강제 적용하여 화면 갱신 시의 백색 플래시/깜빡임 완전 제거.
- [ ] **리스트뷰 스마트 갱신 (Diff-Update / In-place Update)**:
  - 매 주기마다 `Items.Clear()`를 호출하지 않고, 기존 아이템 목록과 상태(`State`, `Display`, `Host`)를 비교하여 변경된 행의 `SubItems`와 색상/폰트만 즉시 갱신.
  - 사용자가 선택한 행(`SelectedItems`)의 포커스와 스크롤 위치 영구 유지.
- [ ] **텍스트 리포트 스크롤 점프 방지**:
  - 네트워크 분석 리포트 업데이트 시 Win32 API(`EM_GETSCROLLPOS`, `EM_SETSCROLLPOS`)를 활용하여 수직/수평 스크롤 위치를 기억하고 복원.
- [ ] **비동기 프로세스 파일 잠금 예외 방어**:
  - CLI 출력 파일(`openconnectsg-tray.out`) 읽기 시 `[System.IO.FileShare]::ReadWrite` 옵션을 적용하여 읽기-쓰기 충돌에 따른 `IOException` 예외 원천 차단.

#### FR-09. Windows 11 모던 UI 스타일 및 사용자 편의성(UX) 향상
- [ ] **모던 다크/라이트 테마 자동 감지 지원**:
  - Windows 개인 설정 레지스트리(`HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme`)를 감지하여 다크 모드 / 라이트 모드 색상 팔레트 자동 전환.
- [ ] **상태 컬럼 비주얼 뱃지(Badge) 도입**:
  - 단순 텍스트("연결됨", "끊김") 대신 `ImageList` 기반의 컬러 인디케이터 닷(Dot) 뱃지 렌더링.
- [ ] **키보드 단축키 및 접근성 개선**:
  - `F5` (즉시 강제 새로고침), `Enter` (선택 프로필 즉시 연결), `Delete` (선택 프로필 연결 해제), `Ctrl+N` (새 프로필 마법사), `Ctrl+B` (북마크 관리).
- [ ] **모달리스 설정/마법사 창 개선**:
  - 새 프로필 추가 버튼(`$btnAdd`) 클릭 시 검은 콘솔창이 팝업되는 대신, 깔끔한 전용 WinForms 다이얼로그나 임베디드 설정 화면 제공.

---

### 3. 단계별 개발 계획 (Development Phases)

- [ ] **Phase 1: 데이터 모델 및 기본 스토리지 엔진 구현** ([Issue #6](https://github.com/sparklings/openconnectsg/issues/6))
  - `OpenConnectSg` 네임스페이스 기반의 `bookmarks.json` I/O 헬퍼 함수 (`Get-Bookmarks`, `Save-Bookmarks`).
  - 사용자별/시스템 공용 경로 해석 및 자동 디렉터리 생성 로직.
  - 북마크 유효성 검사기 및 프로필 매핑 검증 로직.
- [ ] **Phase 2: CLI 서브커맨드 구현 (`openconnectsg bookmark`, `openconnectsg open`)** ([Issue #7](https://github.com/sparklings/openconnectsg/issues/7))
  - `openconnectsg.ps1` 내 `Do-Bookmark` 및 `Do-Open` 디스패처 작성.
  - `list`, `add`, `edit`, `remove`, `open` 서브커맨드 구현.
- [ ] **Phase 3: 프로토콜별 실행 핸들러 및 VPN 터널 연계 검증** ([Issue #8](https://github.com/sparklings/openconnectsg/issues/8))
  - SSH (OpenSSH / wt.exe / cmd), Browser (HTTP/HTTPS), RDP 론처 구현.
  - 터널 수립 완료 대기 폴링 및 타임아웃 제어 로직.
- [ ] **Phase 4: 트레이 GUI 연동 및 북마크 뷰 구현 (`openconnectsg-tray.ps1`)** ([Issue #9](https://github.com/sparklings/openconnectsg/issues/9))
  - 시스템 트레이 컨텍스트 메뉴에 Bookmarks 서브메뉴 반영.
  - 메인 윈도우에 북마크 탭 또는 전용 리스트뷰 추가 및 원클릭 'Quick Connect' 버튼 배치.
- [ ] **Phase 5: 트레이 GUI 폼 레이아웃 및 렌더링/아이콘 전면 개선 (Modernization)** ([Issue #10](https://github.com/sparklings/openconnectsg/issues/10))
  - `SplitContainer` 도입으로 프로필/리스트 영역과 상세 뷰 간 드래그 리사이즈 구현.
  - 경로 확인 바(`lookBar`) 텍스트 초과 시 화면 겹침 해결 및 푸터(`StatusStrip`) 전면 개편.
  - `DoubleBuffered` 리플렉션 및 리스트뷰 Diff-Update(스마트 갱신)로 렌더링 깜빡임 완전 제거.
  - 고품질 멀티 해상도 공식 `.ico` 파일 적용 및 상태별 시각 디자인(에메랄드/앰버/슬레이트) 정밀화.
  - 스크롤 위치 보존 및 비동기 파일 I/O 예외 방어 로직 강화.
- [ ] **Phase 6: 문서화 및 통합 테스트** ([Issue #11](https://github.com/sparklings/openconnectsg/issues/11))
  - `docs/subcommand-manual.md`에 `bookmark` 및 `open` 매뉴얼 추가.
  - `docs/architecture.md`에 북마크 디스패치 파이프라인 및 트레이 GUI 레이아웃 아키텍처 다이어그램 추가.
  - 다양한 화면 해상도(100%~200% DPI), 네트워크 시나리오, 장시간 상주 테스트 검증.

---

## 📋 [Feature] Windows Event Log (EVTX) Native Integration & Structured Logging Architecture ([Issue #12](https://github.com/sparklings/openconnectsg/issues/12))

### 1. 개요 및 기획 배경
- **현행 문제점**:
  - `out.log` 및 `err.log`에 타임스탬프와 프로세스 ID(PID)가 없어 정확한 장애 시점 및 프로세스 단위 추적이 불가능함.
  - 윈도우 OS 표준 이벤트 시스템인 EVTX와 연동되지 않아 이벤트 뷰어(`eventvwr.msc`), `Get-WinEvent`, SIEM(Splunk, Sentinel 등) 연동 불가.
  - 서비스 재시작 시 파일 초기화로 인한 과거 장애 로그 유실 위험.
- **개발 목표**:
  - `04. 윈도우 이벤트 로그 EVTX.md` 기술보고서 표준을 준수하여 `<System>` 메타데이터(TimeCreated, ProcessID, ThreadID, Level)와 `<EventData>` 페이로드를 갖춘 네이티브 EVTX 로깅 구현.
  - 기존 텍스트 로그 파일(`out.log`, `err.log`)에도 `[yyyy-MM-dd HH:mm:ss.fff] [PID:xxxx]` 실시간 프리픽스 주입.

### 2. 상세 요구사항 (FR-EVTX)
- [ ] **FR-EVTX-01. 이벤트 소스 등록 및 수명주기 관리**:
  - 설치 스크립트 실행 시 `Application` 채널에 `OpenConnectSg` 이벤트 소스 자동 등록.
  - 제거(`uninstall`) 시 이벤트 소스 정리(`DeleteEventSource`).
- [ ] **FR-EVTX-02. 이벤트 ID 체계 정의 (Taxonomy)**:
  - `1000~1002`: 데몬 서비스 수명주기 (Start, Stop, Abnormal Exit)
  - `2000~2002`: VPN 터널 수명주기 (Attempt, Established, Disconnected)
  - `3000~3002`: 경고/네트워크 이벤트 (DTLS 실패/TLS 폴백, Wintun 자가 소독, Keepalive 지연)
  - `4000~4003`: 에러/인증 실패 (Permission denied, Wintun 0x102 타임아웃, 계정 잠금, DPAPI 복호화 실패)
  - `5000~5001`: 관리자 CLI 및 마법사 설정 변경, 바이너리 업그레이드
- [ ] **FR-EVTX-03. 구조화된 이벤트 로거 모듈 (`Write-OpenConnectSgEvent`)**:
  - `.NET` `[System.Diagnostics.EventLog]` 기반의 헬퍼 함수 구현.
  - 시스템 메타데이터 및 `<EventData>` Key/Value 페이로드 기록.
- [ ] **FR-EVTX-04. 텍스트 로그 파일 포맷 정규화**:
  - `Do-ServiceRun` 데몬 스트림 핸들러에 타임스탬프(`yyyy-MM-dd HH:mm:ss.fff`) 및 `[PID:xxxx]` 실시간 프리픽스 결합.
  - 주요 연결/장애 시점에 EVTX 이중 기록(Dual-Write) 파이프라인 수립.
- [ ] **FR-EVTX-05. CLI 진단 커맨드 및 트레이 GUI 연동**:
  - `openconnectsg logs` (`Get-WinEvent` 기반 컬러 TUI 표 뷰어) 구현.
  - 트레이 GUI 우클릭 메뉴에 "View Event Log" 항목 추가.

### 3. 단계별 개발 계획
- [ ] **Phase 1: Event Log Provider 등록 및 인프라 구축**
- [ ] **Phase 2: `Write-OpenConnectSgEvent` 코어 모듈 작성**
- [ ] **Phase 3: 데몬 스트림 인터셉터 및 텍스트 로그 포맷 표준화**
- [ ] **Phase 4: CLI 진단 커맨드 (`openconnectsg logs`) 및 트레이 GUI 연동**
- [ ] **Phase 5: 문서화 및 검증** (`docs/troubleshooting.md`, `docs/architecture.md`)
