# 개발 환경

이 문서는 Voyager 모노레포에서 로컬 개발을 시작하기 위한 최소 가이드입니다.

관련 문서

- 실행/ENV 로딩 규칙: `docs/architecture/environment.md`
- 아키텍처 개요: `docs/architecture/overview.md`
- macOS 앱 구조: `docs/architecture/macos-app.md`
- 트러블슈팅: `docs/troubleshooting.md`

---

## 1. 필수 도구

### 1.1 macOS

- macOS (앱 개발은 macOS에서만 가능)
- Xcode (레포에서 고정한 버전 사용)

Xcode 버전 고정

- 고정 파일: `.xcode-version`
- 설치/선택 스크립트: `scripts/xcodes.sh`

권장 설정 방법

```bash
chmod +x scripts/xcodes.sh
./scripts/xcodes.sh
```

### 1.2 Backend (Python)

- Python 버전 고정: `apps/backend/.python-version`
- 패키지/실행 도구: `uv`

---

## 2. 환경 파일(.env) 준비

Voyager는 macOS 앱/Helper/Backend가 같은 키 체계를 공유하도록 설계되어 있습니다.

환경 파일 역할(요약)

- `.env.source`: source 모드에서 사용하는 PUBLIC 설정 (시크릿 금지)
- `.env.bundled`: bundled 모드에서 사용하는 PUBLIC 설정 (시크릿 금지)
- `.env.dev` (Git ignored): 로컬 개발 환경 (시크릿 포함 가능)
- `.env.prod` (Git tracked): 프로덕션 템플릿 (시크릿 금지; CI/런타임에서 주입)

가장 먼저 할 일

```bash
cp .env.example .env.dev
```

세부 로딩 규칙/우선순위는 `docs/architecture/environment.md`를 참고합니다.

---

## 3. macOS 앱 개발

### 3.1 실행(권장)

- Xcode에서 `apps/macos/Voyager/Voyager.xcworkspace`를 열고 `Voyager-Dev` 스킴을 실행합니다.
- Helper가 백엔드 실행/인덱싱을 담당하므로, 일반적인 개발은 “앱 실행”만으로 통합 동작을 확인할 수 있습니다.

CLI 빌드(필요 시)

```bash
xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug
```

참고

- GUI는 `apps/macos/Voyager/Voyager.xcworkspace`로 여는 것을 권장합니다.
- CLI(`xcodebuild`)는 현재 `-workspace`에서 scheme 노출이 안 되는 케이스가 있어 `-project`가 더 안정적입니다.

### 3.2 주의사항

- source 모드에서 `.env.*`를 찾기 위해 `VOYAGER_PROJECT_ROOT`가 필요할 수 있습니다.
- Debug/Release에 따라 `APP_ENV`가 자동으로 결정됩니다.

---

## 4. Backend 개발

### 4.1 설치

```bash
cd apps/backend
uv sync
uv run pre-commit install
```

### 4.2 개발 서버

```bash
cd apps/backend
uv run dev
```

### 4.3 테스트

```bash
cd apps/backend
uv run pytest
```

---

## 5. 통합 개발(앱 + Helper + Backend)

통합 동작은 아래 흐름으로 구성됩니다.

1) Voyager 앱 실행
2) Helper 실행 및 환경 로딩
3) Helper가 백엔드 프로세스를 source/bundled 모드로 기동
4) Helper가 포트를 예약하고 준비 상태를 검증
5) 앱이 Helper 상태를 수신 후 API 호출

통합/부트스트랩 상세는 `docs/macos/voyager-helper.md`, `docs/integration/backend-bootstrap.md`를 참고합니다.

---

## 6. 흔한 문제

- 백엔드가 뜨지 않음 / 포트 연결 실패 / 인덱싱이 진행되지 않음 등의 문제는 `docs/troubleshooting.md`를 우선 확인합니다.
