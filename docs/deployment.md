# 배포/번들링

이 문서는 Voyager 배포 시 필요한 번들링 개념(특히 Python 백엔드 바이너리 포함)을 정리합니다.

관련 문서

- 개발 환경/로컬 실행: `docs/development.md`
- ENV 로딩 규칙: `docs/architecture/environment.md`
- Registry 스펙/운영: `docs/architecture/registries.md`

---

## 1. 실행 모드

Voyager는 스킴/빌드 설정 조합으로 실행 모드가 결정됩니다.

- `Voyager-Dev` 스킴: source 모드 (로컬 `uv` 기반 실행)
- `Voyager-Prod` 스킴: bundled 모드 (Nuitka 바이너리 실행)

세부 규칙은 `docs/architecture/environment.md`를 SSOT로 봅니다.

---

## 2. Backend 바이너리(Nuitka) 빌드/번들링

### 2.1 개요

bundled 모드에서는 Python 백엔드를 “독립 실행 바이너리”로 빌드한 뒤, VoyagerHelper 앱 번들 리소스에 포함합니다.

핵심 스크립트

- 전체 오케스트레이션: `scripts/build/build-backend-binary.sh`
- Nuitka 컴파일: `scripts/build/compile-nuitka-binary.sh`
- Release 리소스에 env 복사: `scripts/build/copy-bundled-env-files.sh`

### 2.2 산출물 위치

Nuitka 결과(레포 내)

- `apps/backend/build/nuitka/server.dist/`

앱 번들 리소스 내 복사 대상

- `{TARGET_BUILD_DIR}/{UNLOCALIZED_RESOURCES_FOLDER_PATH}/server/`

바이너리 이름

- 원본: `server.bin`
- 번들링 시 rename: `Voyager Backend`

### 2.3 Registry JSON 포함

검색 조건/속성 정의 레지스트리(JSON)는 bundled 모드에서 바이너리에 함께 포함됩니다.

- 소스 위치: `shared/*.json`
- 운영/스키마: `docs/architecture/registries.md`

### 2.4 번들 리소스 env 파일 포함

Release + bundled 모드에서는 아래 파일을 번들 리소스에 복사합니다.

- `.env.bundled`
- `.env.prod`

주의

- 위 파일은 시크릿을 포함하지 않습니다.
- 시크릿이 필요하면 CI/Keychain/런타임 환경 변수로 주입합니다.

---

## 3. 코드 서명

`scripts/build/build-backend-binary.sh`는 번들링 이후 `server/` 디렉터리 안의 Mach-O 파일을 찾아 코드 서명을 시도합니다.

- 서명 identity: `EXPANDED_CODE_SIGN_IDENTITY` (Xcode가 주입)

CI/배포 환경에서 서명 실패가 발생하면, 로그에서 "EXPANDED_CODE_SIGN_IDENTITY"가 설정됐는지부터 확인합니다.

---

## 4. 배포 시 흔한 실패 포인트

- Release인데도 `BACKEND_MODE=bundled`가 아니어서 바이너리/리소스가 복사되지 않음
- `.env.bundled` 또는 `.env.prod` 파일이 레포 루트에 존재하지 않아 리소스 복사가 스킵됨
- Registry JSON이 누락되어 검색 조건 변환이 실패
- 코드 서명(identity) 누락으로 번들 내 바이너리 실행이 차단

문제 해결은 `docs/troubleshooting.md`와 Helper 로그(`docs/macos/voyager-helper.md`)를 같이 참고합니다.
