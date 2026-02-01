# macOS 앱 빌드/실행

이 문서는 Voyager macOS 앱(`Voyager`/`VoyagerHelper`)을 로컬에서 빌드/실행/테스트하기 위한 실전 가이드입니다.

관련 문서

- ENV 로딩/키 목록: `docs/architecture/environment.md`
- macOS 구조(TCA/FSD): `docs/architecture/macos-app.md`
- Helper 상세(백엔드 실행/인덱싱): `docs/macos/voyager-helper.md`
- 트러블슈팅: `docs/troubleshooting.md`

---

## 1. Xcode 버전 고정

이 레포는 루트의 `.xcode-version` 파일로 공식 Xcode 버전을 고정해 사용합니다.

권장 설치/선택 방법

```bash
chmod +x scripts/xcodes.sh
./scripts/xcodes.sh
```

---

## 2. 프로젝트 열기

프로젝트는 `apps/macos/Voyager/` 아래에 있습니다.

- Xcode Workspace (권장): `apps/macos/Voyager/Voyager.xcworkspace`
- Xcode Project (권장 for CLI): `apps/macos/Voyager/Voyager.xcodeproj`

현재는 `xcodebuild -workspace ...`에서 scheme이 노출되지 않는 케이스가 있어, CLI/CI에서는 `-project` 사용을 권장합니다.

---

## 3. 스킴/모드 개념

Voyager는 두 축으로 실행 환경이 결정됩니다.

- `APP_ENV` (dev/prod): Debug -> dev, Release -> prod (빌드 설정 기반)
- `BACKEND_MODE` (source/bundled): Dev 스킴 -> source, Prod 스킴 -> bundled (스킴 기반)

세부 규칙은 `docs/architecture/environment.md`를 SSOT로 봅니다.

---

## 4. 빌드/실행 (CLI)

### 4.1 개발 빌드 (Voyager)

프로젝트 기준

```bash
xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug
```

워크스페이스 기준(참고)

주의: 이 레포에서는 Workspace에서 scheme이 노출되지 않는 케이스가 있어, `-workspace` 기반 빌드는 실패할 수 있습니다.

```bash
xcodebuild -list -workspace apps/macos/Voyager/Voyager.xcworkspace
```

`Schemes:` 목록에 `Voyager-Dev`/`Voyager-Prod` 등이 보이지 않으면, CLI/CI에서는 위의 프로젝트 기준(`-project`) 커맨드를 사용합니다.

### 4.2 배포용 빌드 (Voyager)

프로젝트 기준(권장)

```bash
xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Prod -configuration Release
```

---

## 5. 테스트 실행

프로젝트 기준(권장)

```bash
xcodebuild test -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev
```

단위 테스트만

```bash
xcodebuild test -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -only-testing:VoyagerTests
```

UI 테스트만

```bash
xcodebuild test -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -only-testing:VoyagerUITests
```

---

## 6. 로그 확인

```bash
log stream --predicate 'subsystem == "com.voyager.app"'
```

추가적으로 Helper/Backend 통합 흐름, 포트 예약, 인덱싱 문제 등은 `docs/macos/voyager-helper.md`와 `docs/troubleshooting.md`를 함께 참고합니다.
