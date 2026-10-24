# 시스템 아키텍처 및 코어 설계 (System Architecture)

본 문서는 **OpenConnectSg**의 시스템 아키텍처, 프로세스 생명주기(Lifecycle), Windows 서비스 데몬 오케스트레이션, 그리고 커널 수준의 네트워크 터널 형성 원리를 상세히 기술합니다.

---

## 1. 시스템 개요 및 설계 철학

OpenConnectSg는 독립적인 VPN 클라이언트가 아니며, Windows 환경에서 공식 **`openconnect.exe` (MinGW64-GnuTLS)** CLI를 백그라운드 Windows 서비스로 오케스트레이션하는 **PowerShell 래퍼 및 관리 프레임워크**입니다.

### 핵심 설계 원칙
* **Zero Console Window**: 콘솔 창을 상시 띄워두지 않고 Windows 백그라운드 서비스(NSSM)로 안전하게 격리 구동.
* **Single Tunnel Enforcement**: 전역 뮤텍스(`Global\openconnectsg_mutex`)를 활용하여 다중 프로필 간의 라우팅 충돌 및 게이트웨이 경합 방지.
* **Kernel-Level Networking**: 고성능 가상 네트워크 어댑터인 **Wintun** 드라이버를 통해 초고속 터널링 구현.
* **Unified Dispatcher**: 과거의 동적 스크립트 생성 방식을 폐기하고, 단일 진입점인 `src/openconnectsg.ps1` 내부의 `service-run` 디스패처로 모든 데몬 실행 통일.

---

## 2. 전체 아키텍처 다이어그램

```
+-------------------------------------------------------------------------+
|                              Windows OS                                 |
+-------------------------------------------------------------------------+
                                     │
                    (OS 부팅 또는 사용자의 connect 명령)
                                     ▼
+─────────────────────────────────────────────────────────────────────────+
|                 NSSM 2.24 (Windows Service Daemon)                      |
|                   Service: openconnect_<host>_<port>_<tag8>             |
+─────────────────────────────────────────────────────────────────────────+
                                     │
           (Process execution: powershell -File openconnectsg.ps1 service-run ...)
                                     ▼
+─────────────────────────────────────────────────────────────────────────+
|                  OpenConnectSg Unified Runner                           |
|  - Mutex 획득 (Global\openconnect_<host>_<port>_<tag8>)                 |
|  - DPAPI(LocalMachine) pw.bin 복호화 (메모리 로드)                       |
|  - openconnect.conf 설정 검증 및 Wintun 충돌 방지 살균(Sanitize)         |
+─────────────────────────────────────────────────────────────────────────+
             │                                              │
      (stdin Stream Pipe)                           (--config openconnect.conf)
             ▼                                              ▼
+─────────────────────────────────────────────────────────────────────────+
|                    openconnect.exe (GnuTLS v9.21)                       |
|  - SSL-VPN Handshake (RFC 7469 pin-sha256 인증서 검증)                  |
|  - Wintun Driver 로드 및 Wintun 가상 어댑터 인스턴스화                  |
+─────────────────────────────────────────────────────────────────────────+
                                     │
                             (vpnc-script-win.js)
                                     ▼
+─────────────────────────────────────────────────────────────────────────+
|               Windows Kernel Network Stack & Routing Table              |
|  - Tunnel IP 할당 및 사내망 대역 Split Routing 경로 주입                |
+─────────────────────────────────────────────────────────────────────────+
```

---

## 3. 핵심 컴포넌트 분석

### 3.1 서비스 네이밍 규칙 및 식별자 (`tag8`)
각 프로필은 호스트, 포트, 사용자 계정을 기반으로 충돌 없는 고유 서비스명을 부여받습니다:
* **포맷**: `openconnect_<host>_<port>_<tag8>`
* **해시 생성 알고리즘**:
  $$\text{tag8} = \text{SHA256}(\text{"<host>|<port>|<user>"})[0..7]$$
* **프로필 디렉터리 경로**: `C:\Program Files\OpenConnect\profiles\<서비스명>\`

### 3.2 통합 데몬 러너 (`service-run`)
기존 버전에서 각 서비스마다 별도의 `.ps1` 배치 스크립트를 생성하던 레거시 구조를 완전히 제거했습니다.  
NSSM 서비스 등록 시 다음과 같이 표준 진입점을 등록합니다:

```powershell
nssm install $serviceName "powershell.exe" `
    "-ExecutionPolicy Bypass -NoProfile -File `"$binDir\openconnectsg.ps1`" service-run `"$serviceName`""
```

`service-run` 실행 시:
1. 전역 뮤텍스를 생성하여 동일 서비스의 중복 인스턴스 실행 방지.
2. `pw.bin`을 DPAPI로 복호화.
3. `.NET` `System.Diagnostics.Process`를 생성하여 UTF-8 `StreamWriter`로 암호를 프로세스 stdin에 주입.
4. 프로세스 종료 시 종료 코드(Exit Code)를 NSSM으로 정확히 전파하여 자동 재시작 수명주기 관리.

### 3.3 Wintun 가상 네트워크 인터페이스
* **Wintun**: WireGuard 프로젝트에서 개발한 Windows 커널 전용 고성능 TUN 드라이버.
* **어댑터 생성 및 정리**:
  * 구버전에서 `interface=OpenConnectSg`로 인터페이스명을 고정했을 때 이전 어댑터 잠김으로 인해 `0x102` 타임아웃이 발생하던 문제를 해결.
  * 최신 버전(v0.1.2a+)에서는 `openconnect.conf` 내의 `interface` 지시어를 자동으로 제거(sanitize)하여 Wintun이 시스템 레벨에서 충돌 없이 동적으로 어댑터를 생성하도록 보장.

### 3.4 분할 라우팅 (Split Routing)
* `vpnc-script-win.js`가 VPN 연결 수립 후 방화벽 게이트웨이가 전달한 라우팅 대역만 시스템 라우팅 테이블에 주입합니다.
* 사용자의 일반 인터넷 트래픽(웹 브라우징, 유튜브, 외부 API)은 로컬 게이트웨이로 전송되고, 사내망 IP 대역만 Wintun 가상 터널로 통과합니다.

---

## 4. 디렉터리 및 산출물 배치 구조 (Deployment Layout)

```
C:\Program Files\OpenConnect\
├── bin\                                  # 바이너리 및 실행 스크립트
│   ├── openconnectsg.ps1                # 메인 CLI 디스패처 및 데몬 러너 (v0.1.2d)
│   ├── openconnectsg.cmd                # PATH 연동용 셔틀
│   ├── init-openconnectsg.ps1           # 프로필 생성 및 검증 마법사
│   └── .installed                       # 설치 메타데이터 마커
├── profiles\                             # 등록된 VPN 프로필 저장소
│   └── openconnect_<host>_<port>_<tag8>\
│       ├── openconnect.conf             # openconnect CLI 설정 파일
│       ├── user.txt                     # 사용자 계정명
│       ├── pin.txt                      # RFC 7469 서버 인증서 SHA-256 핀
│       ├── label.txt                    # 프로필 단축 별칭(alias)
│       ├── pw.bin                       # DPAPI 암호화된 비밀번호 바이너리
│       └── logs\                        # 입출력 런타임 로그
│           ├── out.log
│           └── err.log
├── openconnect.exe                       # 공식 OpenConnect 바이너리 (v9.21)
├── wintun.dll                            # Wintun 가상 TUN 드라이버
├── vpnc-script-win.js                    # Windows 라우팅 구성 스크립트
└── ... (의존성 DLLs)
```
