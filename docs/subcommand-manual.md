# openconnectsg 서브커맨드 메뉴얼 (Subcommand Manual)

`openconnectsg` CLI 도구에서 지원하는 모든 서브커맨드의 구문, 파라미터, 동작 정책 및 실행 예시를 정리한 사용자 메뉴얼입니다.

---

## 1. 개요 및 구문 규칙

### 기본 문법

```
openconnectsg <서브커맨드> [인자1] [인자2] ...
```

- 서브커맨드를 지정하지 않고 `openconnectsg`만 실행할 경우, 기본적으로 `openconnectsg list`가 실행되어 등록된 프로필 목록이 표시됩니다.
- 대소문자 구분 없이 입력할 수 있습니다(예: `LIST`, `list` 동일 취급).
- 종료 코드(Exit Code):
  - `0`: 성공
  - `1`: 실행 오류(프로필 미존재, 서비스 시작 실패 등)
  - `2`: 사용법 오류(알 수 없는 서브커맨드 입력)

---

## 2. 프로필 식별자(`profile`) 지정 규칙

서브커맨드에서 대상 프로필을 지정할 때 다음 4가지 식별자 중 하나를 유연하게 사용할 수 있습니다.

| 식별자 유형 | 설명 | 예시 |
|---|---|---|
| **번호 (Index)** | `list` 명령어로 출력되는 목록의 순번(1부터 시작하는 정수) | `1`, `2` |
| **별칭 (Alias)** | `alias` 명령어로 등록된 별칭(`label.txt`) | `office`, `dev` |
| **계정명 (User)** | VPN 로그인 시 사용되는 계정명(`user.txt`) | `user01`, `admin` |
| **서비스명 부분 일치** | NSSM 서비스 이름의 일부 문자열 | `443`, `203.0.113` |

### 식별자 해석 우선순위
1. 입력값이 숫자인 경우 $\rightarrow$ **번호(Index)** 일치 우선
2. **별칭(Alias)** 정확 일치
3. **계정명(User)** 정확 일치
4. **부분 일치(Substring Match)**: 별칭, 계정, 서버 주소, 서비스명 중 포함 여부 검색
> [!NOTE]
> 만약 별칭이나 계정명, 부분 일치 검색 결과가 2개 이상 중복되어 모호한 경우, 오류를 반환하고 고유 번호(Index)로 지정할 것을 안내합니다.

---

## 3. 서브커맨드 상세 레퍼런스

### 3.1. `list` / `ls` (프로필 목록 조회)

등록되어 있는 모든 VPN 프로필과 현재 연결 상태를 표 형태로 출력합니다.

- **문법**:
  ```powershell
  openconnectsg list
  openconnectsg ls
  openconnectsg        # 인자 생략 시 자동 실행
  ```
- **출력 항목**:
  - `*`: 기본 서비스(`default`)로 지정된 프로필 앞에 표시
  - `#`: 프로필 번호(Index)
  - `User`: 등록된 사용자 계정명
  - `Server`: VPN 서버 주소 및 포트
  - `Alias`: 사용자가 지정한 별칭
  - `Status`: 윈도우 서비스 실행 상태 (`Running`, `Stopped`, `N/A`)
- **실행 예시**:
  ```powershell
  > openconnectsg list
    #   User               Server                   Alias        Status
  * 1   user01             203.0.113.10:443         office       Running
    2   dev_user           198.51.100.50:443        lab          Stopped
  ```

---

### 3.2. `status` (프로필 상태 상세 확인)

지정한 프로필의 서비스명, 계정, 별칭 및 현재 서비스 상태를 단일 라인으로 확인합니다.

- **문법**:
  ```powershell
  openconnectsg status [<profile>]
  ```
- **인자**:
  - `<profile>` *(선택)*: 프로필 번호, 별칭, 계정 또는 서비스명 일부. 생략 시 전체 목록(`list`)을 출력합니다.
- **실행 예시**:
  ```powershell
  > openconnectsg status 1
  openconnect_203.0.113.10_443_a1b2c3d4  user01  office  Running

  > openconnectsg status office
  openconnect_203.0.113.10_443_a1b2c3d4  user01  office  Running
  ```

---

### 3.3. `connect` / `up` / `start` (VPN 연결)

선택한 프로필로 VPN 터널 연결을 시작합니다.

- **문법**:
  ```powershell
  openconnectsg connect [<profile>]
  openconnectsg up [<profile>]         # connect의 단축 별칭
  openconnectsg start [<profile>]      # connect의 호환 별칭
  ```
- **인자**:
  - `<profile>` *(선택)*: 연결할 프로필의 번호, 별칭, 계정명 등. 생략 시 기본 프로필(`default`)로 연결합니다.
- **주요 동작 및 정책**:
  - **단일 접속 정책(Single Connection Policy)**: 다중 터널 충돌을 방지하기 위해 대상 외에 현재 실행 중인 다른 모든 `openconnect_*` 서비스를 **자동으로 정지(`disconnect`)**한 뒤 연결합니다.
  - 연결 성공 시 해당 프로필을 **기본 프로필(`default`)로 자동 갱신**합니다.
  - 서비스 시작 후 최대 15초간 상태를 폴링하여 `Running` 여부를 확인합니다.
- **실행 예시**:
  ```powershell
  > openconnectsg connect 1
  connect openconnect_203.0.113.10_443_a1b2c3d4
  Status: Running

  > openconnectsg connect 2
  disconnect  openconnect_203.0.113.10_443_a1b2c3d4
  connect openconnect_198.51.100.50_443_e5f6g7h8
  Status: Running
  ```

---

### 3.4. `disconnect` / `down` / `stop` (VPN 연결 해제)

지정한 프로필 또는 실행 중인 모든 VPN 연결을 안전하게 해제합니다.

- **문법**:
  ```powershell
  openconnectsg disconnect [<profile|all>]
  openconnectsg down [<profile|all>]       # disconnect의 단축 별칭
  openconnectsg stop [<profile|all>]       # disconnect의 호환 별칭
  ```
- **인자**:
  - `<profile>`: 해제할 특정 프로필 번호, 별칭, 계정명.
  - `all` *(또는 인자 생략)*: 현재 실행 중인 모든 openconnect VPN 서비스를 일괄 정지.
- **실행 예시**:
  ```powershell
  # 특정 프로필만 연결 해제
  > openconnectsg disconnect 1
  disconnect  openconnect_203.0.113.10_443_a1b2c3d4
  Status: Stopped

  # 전체 연결 일괄 해제
  > openconnectsg disconnect all
  disconnect  openconnect_203.0.113.10_443_a1b2c3d4
  ```

---

### 3.5. `setup` / `add` (새 프로필 등록 마법사)

새로운 VPN 접속 정보를 대화형으로 입력받아 서비스 및 자격증명을 안전하게 등록합니다.

- **문법**:
  ```powershell
  openconnectsg setup
  openconnectsg add         # setup의 별칭
  openconnectsg install     # 이전 버전과의 호환 별칭
  ```
- **대화형 입력 항목**:
  1. **원격VPN서버 주소(IP 또는 도메인)**: 예: `vpn.example.com` 또는 `203.0.113.10`
  2. **원격VPN서버 포트 [443]**: 엔터 입력 시 기본 443 포트 적용
  3. **사용자 계정**: VPN 계정 아이디
  4. **비밀번호 (숨김 입력)**: 마스킹 처리되어 화면에 노출되지 않음
- **자동 수행 작업 (7단계)**:
  1. 프로필 디렉터리 생성 (`profiles/<service_name>/`)
  2. NSSM 2.24 바이너리 확인 및 **공식 SHA256 체크섬 무결성 검증**
  3. openconnect v9.21 다운로드 및 설치
  4. 프로필 설정 파일(`openconnect.conf`, `user.txt`) 생성 및 가상 어댑터 명칭(`interface=OpenConnectSg`) 구성
  5. Windows DPAPI(LocalMachine)를 이용한 비밀번호 암호화 저장(`pw.bin`) 및 SYSTEM/Admin NTFS ACL 적용
  6. 서버 인증서 지문(`pin-sha256`, RFC7469) 자동 프로빙 및 저장
  7. 통합 데몬 러너(`service-run`) 기반 NSSM Windows Service 등록 및 기동

---

### 3.6. `alias` / `label` (별칭 부여)

프로필을 번호나 복잡한 서비스명 대신 짧은 단어로 호출할 수 있도록 별칭(Alias)을 부여합니다.

- **문법**:
  ```powershell
  openconnectsg alias <profile> <alias>
  openconnectsg label <profile> <alias>    # 호환 별칭
  ```
- **인자**:
  - `<profile>` *(필수)*: 대상 프로필 번호, 계정명.
  - `<alias>` *(필수)*: 새로 부여할 별칭 문자열 (공백 없음).
- **실행 예시**:
  ```powershell
  > openconnectsg alias 1 office
  alias 'office' -> openconnect_203.0.113.10_443_a1b2c3d4

  # 이후 별칭으로 바로 접속 가능
  > openconnectsg connect office
  ```

---

### 3.7. `default` (기본 프로필 설정)

기본 프로필 포인터(`profiles/default.txt`)를 수동으로 지정합니다.

- **문법**:
  ```powershell
  openconnectsg default <profile>
  ```
- **인자**:
  - `<profile>` *(필수)*: 기본으로 설정할 프로필 번호, 별칭 등.
- **실행 예시**:
  ```powershell
  > openconnectsg default 2
  default = openconnect_198.51.100.50_443_e5f6g7h8
  ```

---

### 3.8. `remove` / `rm` / `delete` (프로필 및 서비스 삭제)

등록된 프로필 구성 및 윈도우 서비스를 완전히 삭제합니다.

- **문법**:
  ```powershell
  openconnectsg remove <profile>
  openconnectsg rm <profile>       # 단축 별칭
  openconnectsg delete <profile>   # 별칭
  ```
- **인자**:
  - `<profile>` *(필수)*: 삭제할 대상 프로필.
- **주요 동작**:
  1. 서비스가 현재 실행 중인 경우 자동으로 먼저 정지합니다.
  2. 안전을 위해 사용자에게 확인 프롬프트를 요청합니다 (`yes` 입력 시 진행).
  3. NSSM 서비스 등록을 완전히 제거(`nssm remove confirm`)합니다.
  4. 프로필 폴더(`profiles/<svc>`)를 디스크에서 영구 삭제합니다.
- **실행 예시**:
  ```powershell
  > openconnectsg rm 2
  Target: openconnect_198.51.100.50_443_e5f6g7h8 (User: dev_user)
  This will stop the service, unregister it, and purge the profile directory. Type 'yes' to proceed: yes
  Removed profile and service: openconnect_198.51.100.50_443_e5f6g7h8
  ```

---

### 3.9. `uninstall` / `un` / `purge` (도구 및 의존성 삭제)

등록된 모든 VPN 터널과 서비스를 중지 및 해제하고, 사용자가 선택한 범위에 따라 `openconnectsg` 또는 OpenConnect CLI/NSSM을 삭제합니다.

- **문법**:
  ```powershell
  openconnectsg uninstall [<scope>]
  openconnectsg un [<scope>]        # 단축 별칭
  openconnectsg purge [<scope>]     # 별칭
  ```
- **인자**:
  - `<scope>` *(선택)*: 삭제 범위 (`app`: openconnectsg만 삭제 / `full`: CLI 및 NSSM 포함 전체 삭제). 생략 시 대화형 프롬프트가 표시됩니다.
- **삭제 범위 (Scope)**:
  1. **openconnectsg only (`app`)**:
     - 모든 등록된 윈도우 서비스 중지 및 등록 해제
     - `profiles` 및 `bin` 디렉터리 삭제
     - 시스템 PATH에서 `bin` 제거
     - OpenConnect CLI(`openconnect.exe`) 및 NSSM 유지
  2. **Full Purge (`full`)**:
     - `openconnectsg` 전체 삭제
     - OpenConnect CLI 무인 제거 및 디렉터리 정리
     - NSSM(`C:\Program Files\nssm`) 디렉터리 완전 삭제
     - 모든 시스템 환경변수 정리
- **실행 예시**:
  ```powershell
  > openconnectsg uninstall
  ========================================
      openconnectsg Uninstaller
  ========================================

  Select uninstallation scope:
    [1] openconnectsg only (Recommended)
    [2] Full Purge
    [q] Cancel / Abort

  Enter your choice [1/2/q]: 1
  Are you sure you want to proceed with uninstallation? (Type 'yes' to proceed): yes
  ```

---

### 3.10. `upgrade` / `update` (시스템 업그레이드)

설치된 `openconnectsg` 바이너리를 최신 버전으로 갱신하고, 실행 중인 터널 서비스를 자동으로 재시작합니다.

- **문법**:
  ```powershell
  openconnectsg upgrade [<source_path>]
  openconnectsg update [<source_path>]      # upgrade의 단축 별칭
  ```
- **인자**:
  - `<source_path>` *(선택)*: 업데이트할 Git 저장소 또는 소스 디렉터리 경로. 생략 시 기존 설치 시 기록된 소스 위치를 자동으로 참조합니다.
- **주요 동작**:
  1. 관리자 권한을 확인하고, 일반 터미널인 경우 UAC 승격 팝업을 호출하여 안전하게 수행합니다.
  2. Git이 설치된 경우 원격 저장소(`https://github.com/sparklings/openconnectsg`)를 최신으로 클론(`git clone --depth 1`)하여 소스를 확보합니다 (`git pull`에 의존하지 않음).
  3. Git 또는 개발 도구가 없는 일반 PC인 경우, GitHub HTTPS 아카이브(ZIP)를 자동 다운로드 및 압축 해제하여 순수 PowerShell 환경에서도 완벽히 업그레이드합니다.
  4. 바이너리(`openconnectsg.ps1`, `openconnectsg.cmd` 등)를 `C:\Program Files\OpenConnect\bin`으로 재배포합니다.
  5. 비대해진 레거시 하트비트 로그가 남아있을 경우 `err.log`를 자동 정리합니다.
  6. 활성 서비스가 실행 중이면 새 스크립트가 적용되도록 서비스를 안전하게 재시작합니다.
- **실행 예시**:
  ```powershell
  > openconnectsg upgrade

     ____                   ______                            __   _____       
    / __ \____  ___  ____  / ____/___  ____  ____  ___  _____/ /_ / ___/____ _ 
   / / / / __ \/ _ \/ __ \/ /   / __ \/ __ \/ __ \/ _ \/ ___/ __/ \__ \/ __ `/ 
  / /_/ / /_/ /  __/ / / / /___/ /_/ / / / / / / /  __/ /__/ /_   ___/ / /_/ /  
  \____/ .___/\___/_/ /_/\____/\____/_/ /_/_/ /_/\___/\___/\__/  /____/\__, /   
      /_/                                                             /____/    
   ==============================================================================
    OpenConnectSg :: System Upgrade & Maintenance (v0.1.2b)
   ==============================================================================

   [Step 1/3] Fetching latest release package...

     Source Type       : Remote Git Repository
     Repository URL    : https://github.com/sparklings/openconnectsg.git
     Cloning repository (depth 1)...
     Status            : Repository cloned successfully.

   [Step 2/3] Deploying updated binaries...

     Target Directory  : C:\Program Files\OpenConnect\bin
     Target Version    : openconnectsg 0.1.2b (Current: 0.1.2b)
     Deploying scripts...
     Core scripts updated successfully.
     Status            : Binaries deployed and profile configurations sanitized.

   [Step 3/3] Synchronizing background services...

     Restarting active service : openconnect_203.231.7.150_10443_103995b4...
     Service state             : Running (active)

   ==============================================================================
    Upgrade completed successfully! (openconnectsg 0.1.2b)
   ==============================================================================
  ```

---

### 3.11. `version` (버전 및 시스템 정보 확인)

현재 설치된 `openconnectsg`의 버전 및 저장소, 설치 경로 정보를 확인합니다.

- **문법**:
  ```powershell
  openconnectsg version      # 배너 및 상세 시스템 정보 표시
  openconnectsg -v           # 단일 라인 버전 문자열 출력 (스크립트 파싱용)
  openconnectsg --version
  ```
- **실행 결과 (`openconnectsg version`)**:
  ```powershell
     ____                   ______                            __   _____       
    / __ \____  ___  ____  / ____/___  ____  ____  ___  _____/ /_ / ___/____ _ 
   / / / / __ \/ _ \/ __ \/ /   / __ \/ __ \/ __ \/ _ \/ ___/ __/ \__ \/ __ `/ 
  / /_/ / /_/ /  __/ / / / /___/ /_/ / / / / / / /  __/ /__/ /_   ___/ / /_/ /  
  \____/ .___/\___/_/ /_/\____/\____/_/ /_/_/ /_/\___/\___/\__/  /____/\__, /   
      /_/                                                             /____/    
   ==============================================================================
    OpenConnectSg :: System & Version Information (v0.1.2b)
   ==============================================================================

    Version       : openconnectsg 0.1.2b
    Binary Path   : C:\Program Files\OpenConnect\bin
    Profiles Path : C:\Program Files\OpenConnect\profiles
    Repository    : https://github.com/sparklings/openconnectsg
    Documentation : https://github.com/sparklings/openconnectsg#readme
  ```

---

### 3.12. `banner` (웰컴 아스키 배너 표시)

`openconnectsg` 공식 Slant ASCII Figlet 웰컴 배너를 출력합니다.

- **문법**:
  ```powershell
  openconnectsg banner
  ```

---

### 3.13. `help` (도움말 표시)

전체 서브커맨드 요약 안내문과 아스키 배너를 출력합니다.

- **문법**:
  ```powershell
  openconnectsg help
  openconnectsg -h
  openconnectsg --help
  ```
