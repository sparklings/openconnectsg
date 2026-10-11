# OpenConnectSg

> 프로젝트명은 **OpenConnectSg**로 정의하며, 실행 명령·스크립트 소스코드·문서 및 내부 식별자는 모두 소문자 `openconnectsg`로 표기합니다.

원격VPN서버 뒤 서버자원에 NSSM + openconnect CLI로 자동 접속하는 Windows용 경량 CLI 도구.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-blue.svg)]()

---

## 주요 기능

- **데몬 자동화**: NSSM 2.24 기반 Windows Service 등록으로 OS 부팅 시 자동 연결 및 백그라운드 구동.
- **안전한 자격증명 보관**: Windows DPAPI(LocalMachine)를 통해 비밀번호를 암호화하여 로컬 디스크에 평문 잔류 방지.
- **인증서 지문 자동 고정**: 자체서명 인증서 환경에서도 RFC 7469 `pin-sha256` 핀을 자동 확보하여 안전하게 고정.
- **단일 터널 정책 (Single-Tunnel Enforcement)**: 다중 터널 충돌을 방지하기 위해 신규 접속 시 기존 활성 터널 자동 해제.
- **다운로드 무결성 검증**: 의존성 다운로드 시 SHA256 암호화 해시 검증을 통해 공급망 변조 방지.

---

## 요구 사항

- Windows 10 / 11 (x64) 또는 Windows Server 2016 이상
- PowerShell 5.1 이상 (관리자 권한 필수)
- Git (선택: Git clone 설치 시)

---

## 저장소 구조

```
src/
  openconnectsg.ps1       # CLI 디스패처 및 서비스 데몬 러너
  openconnectsg.cmd       # PATH 등록용 래퍼 셔틀
  init-openconnectsg.ps1  # 프로필 등록 마법사 및 의존성 검증기
install/
  install-openconnectsg.ps1 # 자동 배포 및 시스템 PATH 등록 인스톨러
docs/
  commands.md             # 서브커맨드 레퍼런스 매뉴얼
  install-guide.md        # 배포 및 설치 가이드
  openconnectsg.md        # 아키텍처 및 상세 기술 문서
LICENSE                   # MIT License
.gitignore                # 버전 관리 제외 규칙
```

---

## 빠른 시작

### 1) 저장소 다운로드 및 설치
```powershell
# 관리자 권한 PowerShell 실행
git clone https://github.com/sparklings/openconnectsg.git "C:\Program Files\OpenConnect\repo"

# 설치 실행 (자동으로 C:\Program Files\OpenConnect\bin 에 배포 및 PATH 등록)
powershell -ExecutionPolicy Bypass -File "C:\Program Files\OpenConnect\repo\install\install-openconnectsg.ps1"
```

### 2) 새 터미널에서 프로필 등록
새 PowerShell 창을 열고 대화형 설정 마법사를 실행합니다:
```powershell
openconnectsg setup
```
> 서버 주소, 포트, 계정, 비밀번호를 입력하면 NSSM과 openconnect 다운로드(해시 검증 포함), DPAPI 암호화 및 서비스 등록이 자동 완료됩니다.

### 3) 접속 및 관리
```powershell
openconnectsg list                 # 프로필 목록 및 상태 확인
openconnectsg connect 1            # 1번 프로필로 VPN 접속
openconnectsg alias 1 office       # 1번 프로필에 별칭 부여
openconnectsg connect office       # 별칭으로 접속
openconnectsg disconnect all       # VPN 접속 안전 해제
```

---

## 서브커맨드 요약

| 명령어 | 별칭 | 설명 |
|---|---|---|
| `openconnectsg list` | `ls` | 등록된 프로필 및 런타임 연결 상태 확인 |
| `openconnectsg status [<p>]` | - | 특정 프로필의 상세 상태 확인 |
| `openconnectsg connect [<p>]` | `up`, `start` | 프로필 연결 (기존 연결 자동 해제) |
| `openconnectsg disconnect [<p\|all>]` | `down`, `stop` | 프로필 연결 해제 (all = 전체 해제) |
| `openconnectsg setup` | `add` | 새 프로필 대화형 등록 마법사 |
| `openconnectsg alias <p> <별칭>` | `label` | 프로필에 단축 별칭 지정 |
| `openconnectsg default <p>` | - | 기본 프로필 포인터 지정 |
| `openconnectsg remove <p>` | `rm`, `delete` | 프로필 및 Windows 서비스 등록 영구 제거 |
| `openconnectsg version` | `-v` | CLI 버전 정보 확인 |
| `openconnectsg help` | `-h` | 도움말 출력 |

자세한 내용은 [서브커맨드 매뉴얼](docs/commands.md), [설치 가이드](docs/install-guide.md), [아키텍처 문서](docs/openconnectsg.md)를 참조하십시오.

---

## 필요 소프트웨어 패키지

이 프로젝트는 다음 두 가지 외부 패키지를 사용하며, `openconnectsg setup` 실행 시 SHA256 체크섬 무결성 검증을 거쳐 자동으로 설치됩니다.

- **NSSM (Non-Sucking Service Manager)**
  - **버전**: 2.24 (x64)
  - **경로**: `C:\Program Files\nssm\nssm.exe`
  - **역할**: 백그라운드 윈도우 서비스 등록, 프로세스 생명주기 감시, 비정상 종료 시 자동 재시작 및 로그 관리.

- **openconnect CLI**
  - **버전**: v9.21 (MinGW64-GnuTLS)
  - **경로**: `C:\Program Files\OpenConnect\openconnect.exe`
  - **역할**: 원격VPN서버 터널링 통신 수립, DPAPI 복호화 비밀번호 전달 수신, 인증서 핀(`pin-sha256`) 검증.

---

## 라이선스

본 프로젝트는 [MIT License](LICENSE)에 따라 자유롭게 사용, 수정 및 배포할 수 있습니다.