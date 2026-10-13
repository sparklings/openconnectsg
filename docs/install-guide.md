# openconnectsg 설치 가이드 (Installation Guide)

이 문서는 `openconnectsg`를 Windows 환경에 배포하고 시스템 전역 CLI 명령어로 등록하는 전체 설치 과정과 환경 설정 가이드입니다.

---

## 1. 시스템 요구 사항 (System Requirements)

설치 전 운영체제 및 실행 환경을 확인하십시오.

| 항목 | 요구 사항 | 비고 |
|---|---|---|
| **운영체제** | Windows 10 / 11 (64-bit) | Windows Server 2016 이상 지원 |
| **PowerShell** | 5.1 이상 | `Windows PowerShell` 기본 탑재 버전 |
| **권한** | 관리자 권한 (Administrator) | 시스템 PATH 등록 및 서비스 배치에 필수 |
| **도구** | Git (Git 설치 환경 권장) | Git 미설치 환경은 오프라인 설치 지원 |
| **네트워크** | 인터넷 연결 | NSSM 및 openconnect 자동 다운로드용 |

---

## 2. 사전 준비 (Prerequisites)

### 2.1. 관리자 권한 PowerShell 실행
설치 스크립트는 시스템 `Program Files` 디렉터리에 접근하고 머신 환경 변수를 수정하므로 반드시 **관리자 권한**으로 실행해야 합니다.

1. `시작` 메뉴 우클릭 $\rightarrow$ **Windows 터미널(관리자)** 또는 **PowerShell(관리자)** 선택
2. PowerShell 버전 확인:
   ```powershell
   $PSVersionTable.PSVersion
   # Major 버전이 5 이상이어야 합니다.
   ```

### 2.2. 실행 정책 (Execution Policy)
PowerShell 스크립트 실행이 제한된 경우 일시적으로 우회 플래그(`-ExecutionPolicy Bypass`)를 추가하여 실행하거나, 정책을 완화합니다:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## 3. 설치 방법 (Installation Methods)

### 방법 A. 저장소 Clone 후 로컬 설치 (가장 권장)

```powershell
# 1) 저장소를 C:\Program Files\OpenConnect\repo 에 clone
git clone https://github.com/sparklings/openconnectsg.git "C:\Program Files\OpenConnect\repo"

# 2) 설치 스크립트 실행 (로컬 소스를 자동으로 감지하여 bin 배치 및 PATH 등록)
powershell -ExecutionPolicy Bypass -File "C:\Program Files\OpenConnect\repo\install\install-openconnectsg.ps1"
```

### 방법 B. 단일 인스톨러 파일로 원격 자동 설치

```powershell
powershell -ExecutionPolicy Bypass -File .\install-openconnectsg.ps1 `
  -RepoUrl "https://github.com/sparklings/openconnectsg.git" `
  -Dest    "C:\Program Files\OpenConnect\repo"
```

### 방법 C. 오프라인 / 폐쇄망 설치 (ZIP 다운로드 환경)

```powershell
# 압축을 해제한 프로젝트 루트 디렉터리로 이동 후 실행
powershell -ExecutionPolicy Bypass -File .\install\install-openconnectsg.ps1 -SkipClone
```

---

## 4. 설치 후 확인 및 초기 설정 (Post-Installation)

### 4.1. 새 터미널 열기
시스템 환경 변수(PATH) 갱신을 적용받기 위해 **현재 터미널 창을 닫고 새로운 PowerShell 창을 엽니다**.

### 4.2. 설치 확인
```powershell
openconnectsg version
# 출력: openconnectsg 0.1.1b
```

### 4.3. 초기 프로필 등록 마법사 실행
```powershell
openconnectsg setup
```
- 실행 시 필요한 외부 도구(`NSSM 2.24`, `openconnect v9.21`)가 공식 SHA256 체크섬 검증을 거쳐 자동 다운로드 및 설치됩니다. (공식 사이트 장애 시 검증된 GitHub 미러로 자동 대체)
- 원격VPN서버의 주소, 포트, 계정, 비밀번호를 순서대로 입력하면 .NET 기반 초고속 인증서 Pin(RFC7469) 추출, Windows DPAPI 암호화 및 서비스 등록이 원스톱으로 완료됩니다.

---

## 5. 업데이트 및 재설치 (Update)

```powershell
cd "C:\Program Files\OpenConnect\repo"
git pull --ff-only

powershell -ExecutionPolicy Bypass -File .\install\install-openconnectsg.ps1
```

---

## 6. 제거 및 완전 삭제 (Uninstall)

설치된 환경을 깔끔하게 제거할 수 있는 2가지 방법이 제공됩니다:

### 방법 A. CLI 대화형 제거 (`openconnectsg uninstall`)
```powershell
# 관리자 권한 터미널에서 실행
openconnectsg uninstall
```
- **[1] openconnectsg only**: 터널 서비스 중지/해제, 프로필 및 바이너리 삭제, PATH 제거 (OpenConnect CLI와 NSSM은 보존)
- **[2] Full Purge**: 모든 서비스/프로필 삭제 + OpenConnect CLI 및 NSSM 완전 제거 + 시스템 PATH 정리

### 방법 B. 설치 스크립트 기반 제거
```powershell
# openconnectsg만 제거
powershell -ExecutionPolicy Bypass -File .\install\install-openconnectsg.ps1 -Uninstall -Scope app

# 모든 구성 요소 완전 영구 삭제 (Full Purge)
powershell -ExecutionPolicy Bypass -File .\install\install-openconnectsg.ps1 -Uninstall -Scope full
```

---

## 7. 문제 해결 (Troubleshooting)

### Q1. `...스크립트를 실행할 수 없습니다` 오류가 발생합니다.
- **원인**: Windows의 PowerShell ExecutionPolicy가 `Restricted`로 설정되어 있습니다.
- **조치**: 실행 시 `-ExecutionPolicy Bypass` 플래그를 붙여 실행하십시오.

### Q2. `openconnectsg : 용어가 cmdlet, 함수...로 인식되지 않습니다.`
- **원인**: 설치 후 기존 터미널 창을 그대로 사용 중이어서 변경된 PATH가 로드되지 않았습니다.
- **조치**: 현재 터미널 창을 닫고 새 창을 여십시오.

### Q3. `Permission denied` 또는 `Too many bad login attempts` 오류가 발생합니다.
- **원인**:
  - `Permission denied`: 계정 정보는 유효하나 방화벽 측 SSL-VPN 인가(Authorization) 정책 또는 그룹 권한에 매핑되지 않은 경우입니다.
  - `Too many bad login attempts`: 연속적인 시도로 인해 방화벽의 브루트포스 차단 타이머가 작동한 상태입니다.
- **조치**: 차단 타이머의 경우 3~5분 정도 대기 후 다시 시도하시고, 인가 문제는 네트워크 관리자에게 사용자 계정의 SSL-VPN 접근 그룹 권한을 확인하십시오.
