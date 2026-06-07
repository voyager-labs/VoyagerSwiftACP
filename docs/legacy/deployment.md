# 배포/번들링

이 문서는 Voyager macOS 배포 시 필요한 번들링 개념(Helper/XPC/리소스 중심)을 정리합니다.

관련 문서

- 개발 환경/로컬 실행: `docs/legacy/development.md`
- ENV 로딩 규칙: `docs/legacy/architecture/environment.md`
- Registry 스펙/운영: `docs/legacy/architecture/registries.md`

---

## 1. 실행 개요

Voyager는 macOS 앱 + Helper + XPC 기반으로 동작하며, 로컬 FastAPI 백엔드를 앱 번들에서 직접 실행하지 않습니다.

- `Voyager-Dev`/`Voyager-Prod` 모두 Helper/XPC 런타임을 사용
- 서버 백엔드(`apps/backend`)는 별도 배포 단위로 운영

세부 규칙은 `docs/legacy/architecture/environment.md`를 SSOT로 봅니다.

---

## 2. 번들 리소스

### 2.1 Registry JSON 포함

검색 조건/속성 정의 레지스트리(JSON)는 macOS 타깃 리소스로 포함됩니다.

- 소스 위치: `shared/*.json`
- 운영/스키마: `docs/legacy/architecture/registries.md`

### 2.2 번들 리소스 env 파일 포함

Release 빌드에서는 아래 파일을 번들 리소스에 복사합니다.

- `.env.prod`

주의

- 위 파일은 시크릿을 포함하지 않습니다.
- 시크릿이 필요하면 CI/Keychain/런타임 환경 변수로 주입합니다.

---

## 3. 코드 서명

코드 서명은 macOS 앱/Helper/XPC 산출물 기준으로 수행됩니다.

- 서명 identity는 Xcode 빌드 설정/CI 환경에서 주입됩니다.
- 리소스 복사(`.env.prod`, `shared/*.json`)는 서명 전에 완료되어야 합니다.

---

## 4. 배포 시 흔한 실패 포인트

- `.env.prod` 파일이 레포 루트에 존재하지 않아 리소스 복사가 스킵됨
- Registry JSON이 누락되어 검색 조건 변환이 실패
- 코드 서명(identity) 누락으로 앱/Helper/XPC 실행이 차단됨

문제 해결은 `docs/legacy/troubleshooting.md`와 Helper 로그(`docs/legacy/macos/voyager-helper.md`)를 같이 참고합니다.
