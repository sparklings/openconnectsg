# openconnectsg 종합 개요 및 문서 가이드

> [!NOTE]
> 본 문서는 기존 참조 호환성을 유지하기 위한 종합 개요 문서입니다.  
> 세부 도메인별 최신 기술 문서는 아래 링크를 참조하십시오:
> - **[시스템 아키텍처 및 내부 원리](architecture.md)**
> - **[CLI 서브커맨드 전체 레퍼런스](subcommand-manual.md)**
> - **[배포 및 설치 가이드](install-guide.md)**
> - **[보안 및 자격 증명(DPAPI) 명세](security-credentials.md)**
> - **[장애 진단 및 트러블슈팅](troubleshooting.md)**
> - **[버전별 변경 이력 (Changelog)](../CHANGELOG.md)**

---

## 1. 개요 및 설계 목적

`openconnectsg`는 Windows 환경에서 공식 [OpenConnect](https://www.infradead.org/openconnect/)(`openconnect.exe`) CLI 도구를 백그라운드 Windows 서비스(NSSM)로 구동하고 프로필 관리를 보조하기 위해 작성된 **PowerShell 래퍼(Wrapper) 프레임워크**입니다.

### 핵심 기능
- **DPAPI 비밀번호 암호화**: `LocalMachine` 스코프로 안전하게 보호된 암호 바이트(`pw.bin`) 저장.
- **NSSM 서비스 통합**: 터미널 창 없이 백그라운드에서 상시 터널 유지 및 OS 부팅 시 자동 연결.
- **단일 터널 보장**: 전역 뮤텍스를 기반으로 다중 연결 간의 라우팅 충돌 방지.
- **Wintun 가상 어댑터**: 커널 수준의 고속 가상 인터페이스 자동 구성.

자세한 내부 구현과 컴포넌트 간 상호작용은 [시스템 아키텍처 명세서](architecture.md)에서 확인하실 수 있습니다.
