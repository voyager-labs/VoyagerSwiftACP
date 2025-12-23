# 빌드 스킴 및 실행 환경

## 개요

Voyager 프로젝트는 두 가지 독립적인 축으로 실행 환경을 결정합니다:
- **빌드 설정 (Configuration)**: Debug 또는 Release
- **스킴 (Scheme)**: Dev 또는 Prod

이 두 축의 조합에 따라 환경 변수와 백엔드 실행 방식이 자동으로 결정됩니다.

## 스킴 (Schemes)

### Voyager-Dev
- **빌드 설정**: Debug (기본)
- **용도**: 로컬 개발 및 디버깅
- **특징**:
  - 디버거 연결 가능
  - 최적화 비활성화 (`-Onone`)
  - DEBUG 매크로 정의
  - App Sandbox 비활성화
  - Entitlements: `VoyagerDebug.entitlements`
  - 환경변수: `BACKEND_MODE=source` (자동 주입)

### Voyager-Prod
- **빌드 설정**: Release (기본)
- **용도**: 프로덕션 배포 및 테스트
- **특징**:
  - 디버거 연결 불가
  - 최적화 활성화
  - App Sandbox 활성화
  - Entitlements: `VoyagerRelease.entitlements`
  - 환경변수: `BACKEND_MODE=bundled` (자동 주입)

### VoyagerHelper-Dev
- **빌드 설정**: Debug (기본)
- **용도**: Helper 앱 개발 및 디버깅
- **특징**: Voyager-Dev와 동일한 Debug 설정
  - 환경변수: `BACKEND_MODE=source` (자동 주입)

### VoyagerHelper-Prod
- **빌드 설정**: Release (기본)
- **용도**: Helper 앱 프로덕션 빌드
- **특징**: Voyager-Prod와 동일한 Release 설정
  - 환경변수: `BACKEND_MODE=bundled` (자동 주입)

## 실행 환경 (Environments)

### 환경 타입 (EnvironmentType)

**dev 환경:**
- **감지 조건**: Info.plist의 `APP_ENV=dev` (빌드 설정에서 자동 설정)
- **빌드 설정**: Debug → `APP_ENV=dev` 자동 설정
- **환경 파일**: `.env.dev` (프로젝트 루트 또는 번들 리소스)
- **백엔드 실행**: 로컬 `uv` 환경 사용 (`uv run dev`)

**prod 환경:**
- **감지 조건**: Info.plist의 `APP_ENV=prod` (빌드 설정에서 자동 설정)
- **빌드 설정**: Release → `APP_ENV=prod` 자동 설정
- **환경 파일**: `.env.prod` (프로젝트 루트 또는 번들 리소스)
- **백엔드 실행**: 번들된 venv 사용 (독립 실행)

### 백엔드 모드 (BackendMode)

**source 모드:**
- **설정**: `BACKEND_MODE=source` (Dev 스킴에서 자동 주입)
- **백엔드 디렉토리**: `apps/backend` (소스 디렉토리)
- **실행 방식**: 로컬 `uv` 명령어 사용
- **명령어**: `uv run dev` 또는 `uv run prod` (APP_ENV에 따라)
- **요구사항**: 시스템 PATH에 `uv` 설치 필요

**bundled 모드:**
- **설정**: `BACKEND_MODE=bundled` (Prod 스킴에서 자동 주입)
- **백엔드 디렉토리**: `VoyagerHelper.app/Contents/Resources/helper-runtime`
- **실행 방식**: 번들된 Python 인터프리터 직접 실행
- **명령어**: `helper-runtime/bin/python -m uvicorn app.main:app`
- **요구사항**: Release 빌드 시 venv가 번들에 포함되어 있어야 함

## 환경 감지 우선순위

`Environment.swift`의 `detectEnvironmentType()` 메서드는 다음 순서로 환경을 감지합니다:

1. **Info.plist** (`APP_ENV`) - 최우선
   - 빌드 설정에서 자동 설정됨 (Debug → dev, Release → prod)
   - `Voyager/Info.plist` 및 `VoyagerHelper/Info.plist`에 설정
   - 빌드 시 `$(APP_ENV)` 변수가 실제 값으로 치환됨

2. **기본값**: `dev`
   - Info.plist에서 값을 찾을 수 없으면 dev로 설정

`detectBackendMode()` 메서드는 다음 순서로 백엔드 모드를 감지합니다:

1. **런타임 환경변수** (`BACKEND_MODE`) - 최우선
   - 스킴의 LaunchAction에서 자동 주입됨
   - Dev 스킴 → `BACKEND_MODE=source`
   - Prod 스킴 → `BACKEND_MODE=bundled`

2. **번들 리소스 확인**
   - `helper-runtime` 디렉토리가 번들 리소스에 있으면 → `bundled`
   - 없으면 → `source`

## 스킴과 환경의 매핑

| 스킴 | 빌드 설정 | APP_ENV | BACKEND_MODE | 백엔드 실행 방식 | 환경 파일 |
|------|-----------|---------|--------------|------------------|-----------|
| Voyager-Dev | Debug | dev | source | 로컬 `uv run dev` | `.env.dev` |
| Voyager-Prod | Release | prod | bundled | 번들 Python 직접 실행 | `.env.prod` |
| VoyagerHelper-Dev | Debug | dev | source | 로컬 `uv run dev` | `.env.dev` |
| VoyagerHelper-Prod | Release | prod | bundled | 번들 Python 직접 실행 | `.env.prod` |

## 빌드 프로세스

### Debug 빌드 (Dev 환경)

**VoyagerHelper 빌드 단계:**

1. **Sources**: Swift 소스 파일 컴파일
2. **Prepare Backend Venv**: 스킵됨 (빌드 스크립트에서 `CONFIGURATION=Debug` 체크)
3. **Bundle Backend Venv**: 스킵됨 (빌드 스크립트에서 `CONFIGURATION=Debug` 체크)
4. **Run Lint and Format**: SwiftLint 및 SwiftFormat 실행
5. **Frameworks**: 프레임워크 링크
6. **Resources**: 리소스 파일 복사

**Voyager 빌드 단계:**

1. **Sources**: Swift 소스 파일 컴파일
2. **Run Lint and Format**: SwiftLint 및 SwiftFormat 실행
3. **Frameworks**: 프레임워크 링크
4. **Resources**: 리소스 파일 복사
5. **Copy Helper into App**: VoyagerHelper.app을 Voyager.app/Contents/Helpers/로 복사

**실행 시:**

- `APP_ENV=dev` (Info.plist에서 읽음)
- `BACKEND_MODE=source` (스킴 환경변수에서 주입)
- `.env.dev` 파일 로드 (번들 리소스 또는 프로젝트 루트)
- `apps/backend` 디렉토리에서 `uv run dev` 실행

### Release 빌드 (Prod 환경)

**VoyagerHelper 빌드 단계:**

1. **Sources**: Swift 소스 파일 컴파일
2. **Prepare Backend Venv**: 실행됨
   - `scripts/prepare-helper-runtime.sh` 실행
   - 백엔드 휠 빌드 (`uv build --wheel`)
   - 번들용 venv 생성 (`apps/backend/build/helper-runtime`)
   - uv.lock에서 런타임 의존성 추출 및 설치
   - 빌드된 백엔드 휠을 venv에 설치
3. **Bundle Backend Venv**: 실행됨
   - `apps/backend/build/helper-runtime` → `VoyagerHelper.app/Contents/Resources/helper-runtime` 복사
   - `.env.prod` 파일을 번들 리소스로 복사 (없으면 기본값 생성)
4. **Run Lint and Format**: SwiftLint 및 SwiftFormat 실행
5. **Frameworks**: 프레임워크 링크
6. **Resources**: 리소스 파일 복사

**Voyager 빌드 단계:**

1. **Sources**: Swift 소스 파일 컴파일
2. **Run Lint and Format**: SwiftLint 및 SwiftFormat 실행
3. **Frameworks**: 프레임워크 링크
4. **Resources**: 리소스 파일 복사
5. **Copy Helper into App**: VoyagerHelper.app을 Voyager.app/Contents/Helpers/로 복사

**실행 시:**

- `APP_ENV=prod` (Info.plist에서 읽음)
- `BACKEND_MODE=bundled` (스킴 환경변수에서 주입)
- `.env.prod` 파일 로드 (번들 리소스 우선, 없으면 프로젝트 루트)
- `VoyagerHelper.app/Contents/Resources/helper-runtime/bin/python` 직접 실행

## 환경 파일 로드 우선순위

`Environment.swift`의 `loadEnvFile()` 메서드는 다음 순서로 환경 파일을 로드합니다:

1. **번들 리소스** (최우선)
   - `VoyagerHelper.app/Contents/Resources/.env.dev` 또는 `.env.prod`
   - Release 빌드 시 자동으로 복사됨

2. **프로젝트 루트**
   - `.env.dev` 또는 `.env.prod` (환경 타입에 따라)
   - 프로젝트 루트는 `.env`, `.env.dev`, `.env.prod` 파일 중 하나를 찾아서 결정

3. **기본 .env 파일** (fallback)
   - 위의 파일들을 찾을 수 없으면 기본 `.env` 파일 사용

## 명확화 사항

### 스킴 이름의 의미
- **`-Dev`**: 개발용 스킴 (로컬 `uv` 환경 사용)
- **`-Prod`**: 프로덕션용 스킴 (번들 venv 사용)

### 빌드 설정의 의미
- **Debug**: 개발 및 디버깅용 (최적화 없음, 디버거 연결 가능)
- **Release**: 프로덕션 배포용 (최적화 활성화, 디버거 연결 불가)

### 환경 타입의 의미
- **`dev`**: 개발 환경 (로컬 개발 서버 실행)
- **`prod`**: 프로덕션 환경 (프로덕션 서버 실행)

### 백엔드 모드의 의미
- **`source`**: 소스 디렉토리에서 백엔드 실행 (로컬 `uv` 사용)
- **`bundled`**: 번들된 venv에서 백엔드 실행 (독립 실행)

### 혼동 방지
- 스킴 이름(`-Dev`, `-Prod`)은 **백엔드 실행 방식**을 나타냅니다
- 빌드 설정(Debug/Release)은 **빌드 최적화 및 디버깅 설정**을 나타냅니다
- 환경 타입(`dev`, `prod`)은 **백엔드 실행 모드**를 나타냅니다
- 빌드 설정이 자동으로 환경 타입을 결정하고, 스킴이 백엔드 모드를 결정합니다

## 참고

- 환경 감지 로직: [apps/macos/Voyager/VoyagerHelper/Infrastructure/Environment.swift](../../apps/macos/Voyager/VoyagerHelper/Infrastructure/Environment.swift)
- 백엔드 실행 로직: [apps/macos/Voyager/VoyagerHelper/Infrastructure/ProcessRunner.swift](../../apps/macos/Voyager/VoyagerHelper/Infrastructure/ProcessRunner.swift)
- 빌드 스크립트: [apps/macos/Voyager/Voyager.xcodeproj/project.pbxproj](../../apps/macos/Voyager/Voyager.xcodeproj/project.pbxproj)

