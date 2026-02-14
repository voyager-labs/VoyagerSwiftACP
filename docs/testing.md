# 테스트

이 문서는 Voyager의 테스트 실행 방법(Backend + macOS)을 정리합니다.

관련 문서

- 개발 환경: `docs/development.md`
- macOS 빌드/실행: `docs/macos/build-and-run.md`

---

## 1. Backend (FastAPI)

### 1.1 범위

현재 백엔드 테스트는 주로 다음을 검증합니다.

- 레지스트리 로딩/검증
- LLM 변환 결과 기반 convert-only 응답 계약

테스트 위치

- `apps/backend/tests/`

### 1.2 실행

실행

```bash
cd apps/backend
uv run pytest
```

자주 쓰는 옵션

```bash
cd apps/backend

# 특정 테스트 파일만
uv run pytest tests/test_search_service_convert_only.py

# 이름으로 필터링
uv run pytest -k "condition_builder"

# 실패 즉시 중단
uv run pytest -x
```

### 1.3 권장: 타입/린트도 함께

```bash
cd apps/backend
uv run pyright
uv run ruff check
```

참고

- Pyright는 `apps/backend/pyproject.toml`에서 `strict` 모드로 설정되어 있습니다.
- 개발 중 생성되는 캐시/노트북 파일은 타입체크 대상에서 제외됩니다.

---

## 2. macOS (Voyager)

### 2.0 전제

- Xcode 버전은 레포 루트의 `.xcode-version`과 일치해야 합니다.
- Helper/Backend 통합이 포함된 테스트는 환경변수/포트 상태에 영향을 받을 수 있습니다.
  - 관련 문서: `docs/architecture/environment.md`, `docs/troubleshooting.md`

### 2.1 전체 테스트

```bash
xcodebuild test -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev
```

### 2.2 단위 테스트만

```bash
xcodebuild test -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -only-testing:VoyagerTests
```

### 2.3 UI 테스트만

```bash
xcodebuild test -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -only-testing:VoyagerUITests
```

### 2.4 Helper 테스트

Helper 테스트는 별도 스킴으로 실행할 수 있습니다.

```bash
xcodebuild test -project apps/macos/Voyager/Voyager.xcodeproj -scheme VoyagerHelper-Dev
```

### 2.5 특정 테스트만 실행

Xcode의 test target 이름을 알면 `-only-testing`으로 좁힐 수 있습니다.

```bash
xcodebuild test -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -only-testing:VoyagerTests/<TestClassName>
```

---

## 3. 실패했을 때 체크리스트

- Xcode 버전이 `.xcode-version`과 일치하는지
- Helper/Backend 통합이 포함된 테스트라면 포트/ENV 충돌이 없는지

추가 확인

- scheme 목록 확인: `xcodebuild -list -project apps/macos/Voyager/Voyager.xcodeproj`
- Helper 로그 확인: `log stream --predicate 'subsystem == "com.voyager.app"'`

추가 힌트는 `docs/troubleshooting.md`를 참고합니다.
