# Voyager App

프로젝트 개요와 실행/문서 진입점을 간단히 제공합니다.

## Monorepo Layout

- `apps/backend`: FastAPI 백엔드 (uv)
- `apps/macos/Voyager`: macOS SwiftUI + TCA 앱과 Helper
- `docs/`: AI 에이전트용 PRD/아키텍처 문서 인덱스

## Environment Setup

### 환경 파일

프로젝트 루트에 환경별 `.env` 파일을 생성합니다:

- **`.env.dev`** (Git ignored): 로컬 개발 환경
  - 모든 설정 포함 (비밀키 포함)
  - Debug 빌드에서 사용
  - 생성: `cp .env.example .env.dev`
- **`.env.prod`** (Git tracked): 프로덕션 환경 템플릿
  - 비밀키 제외한 기본 설정만 포함
  - Release 빌드에서 사용
  - Secrets는 파일에 포함하지 않음 (앱 번들 노출 방지)

### 환경 자동 감지

앱은 빌드 설정에 따라 환경을 자동으로 감지합니다:

- **Debug 빌드** → `dev` 환경 (로컬 `uv` 사용)
- **Release 빌드** → `prod` 환경 (번들 venv 사용)

`APP_ENV`는 빌드 설정에서 자동으로 설정되므로 `.env` 파일에 명시할 필요가 없습니다.

### 백엔드 실행 방식

스킴에 따라 백엔드 실행 방식이 결정됩니다:

- **`*-Dev` 스킴** (`BACKEND_MODE=source`): 로컬 `uv` 환경 사용
  - `apps/backend` 디렉토리에서 `uv run dev` 실행
  - 로컬 개발 시 빠른 반복 가능
- **`*-Prod` 스킴** (`BACKEND_MODE=bundled`): 번들된 서버 바이너리 사용
  - `VoyagerHelper.app/Contents/Resources/server/server.bin` 실행
  - 독립형 앱 번들 (배포용)

### 필수 환경 변수

백엔드 기동에 필요한 기본 키:

- `PUBLIC_BACKEND_HOST=127.0.0.1`
- `PUBLIC_BACKEND_PORT=0` (0이면 동적 할당)

### 보안

- 비밀키는 커밋 금지
- 로컬 개발: `.env.dev` 파일 사용 (Git ignored)
- CI/CD: `.env.prod`는 secrets 없이 복사 (앱 번들 노출 방지)

## Quick Start

* Backend

  * Setup: `cd apps/backend && uv sync && uv run pre-commit install`
  * Dev server: `uv run dev`
  * Tests: `uv run pytest`
* macOS App

  * Xcode에서 시작(권장): `xed apps/macos/Voyager/Voyager.xcworkspace` (열기 후 `Cmd+R` 실행)
  * (대안) Xcode 프로젝트: `xed apps/macos/Voyager/Voyager.xcodeproj`
  * VSCode 류 IDE(Sweetpad Extension)에서 실행:
    * Xcode 프로젝트 열기: Sweetpad로 `apps/macos/Voyager/Voyager.xcodeproj` 오픈
    * 태스크로 실행 (권장):
      * `Cmd+Shift+P` (또는 `Ctrl+Shift+P`)로 Command Palette 열기
      * "Tasks: Run Task" 입력 후 다음 태스크 중 선택:
        - `Voyager Dev: Launch (Debug)` - 개발 환경 Debug 모드로 빌드 및 실행
        - `Voyager Dev: Launch (Release)` - 개발 환경 Release 모드로 빌드 및 실행
        - `Voyager Prod: Launch (Debug)` - 프로덕션 환경 Debug 모드로 빌드 및 실행
        - `Voyager Prod: Launch (Release)` - 프로덕션 환경 Release 모드로 빌드 및 실행
      * 참고: 버튼을 통한 직접 실행은 비권장합니다. xcscheme의 환경변수가 제대로 주입되지 않을 수 있습니다. 태스크를 통한 실행을 사용하세요.
  * Build (CLI): `xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug`
  * Prod build/archive (CLI): `xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Prod -configuration Release`
  * Tests (CLI): `xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj`

### Xcode 버전 관리

이 레포에서는 루트 디렉터리의 `.xcode-version` 파일로 **공식 Xcode 버전**을 고정해서 사용합니다.
모든 로컬 개발 환경과 CI는 이 버전에 맞추는 것을 원칙으로 합니다.

#### 사전 준비

* macOS
* [Homebrew](https://brew.sh) 설치
* Xcode 설치 및 업데이트 권한

#### 이 프로젝트용 Xcode 설정 방법

처음 클론했거나, Xcode 버전을 다시 맞추고 싶을 때 **레포 루트에서** 다음을 실행합니다.

```bash
chmod +x scripts/xcodes.sh   # 최초 1회만 필요 (이미 실행 권한이 있으면 생략 가능)
./scripts/xcodes.sh
```

이 스크립트는 다음 작업을 수행합니다.

1. 레포 루트의 `.xcode-version` 파일을 읽어, 필요한 Xcode 버전을 확인합니다.
2. `xcodes` CLI가 설치되어 있지 않으면 Homebrew로 설치합니다.
3. `xcodes install <버전>`으로 해당 Xcode 버전을 설치합니다. (이미 설치되어 있다면 건너뜁니다)
4. `xcodes select <버전>`으로 해당 버전을 현재 macOS의 활성 Xcode로 설정합니다.

설정이 제대로 되었는지 확인하려면:

```bash
xcodebuild -version
```

을 실행했을 때 출력되는 Xcode 버전이 `.xcode-version`에 적힌 값과 일치해야 합니다.

#### 스크립트를 실행해야 하는 시점

* 이 레포를 **처음 클론한 직후**

## Development Bootstrap (Git hooks)

커밋 시점에 Swift/Python 포맷/린트를 자동으로 실행해서 실패하면 커밋을 막습니다.

처음 클론한 후(그리고 새로운 머신에서) **레포 루트에서 한 번만** 실행하세요:

```bash
make bootstrap
```

이 설정은 repo-local git config(`core.hooksPath`)에 저장되며, 동일 레포에서 생성한 worktree에도 그대로 적용되는 것을 목표로 합니다.
* 다른 프로젝트 때문에 Xcode 버전을 변경했다가, **다시 Voyager 앱을 개발하려고 할 때**
* `.xcode-version`이 변경된 PR이 머지되어, **새로운 공식 Xcode 버전에 맞추어야 할 때**

> 이 레포에서 작업할 때는 항상 `.xcode-version`에 적힌 Xcode 버전으로 빌드하는 것을 원칙으로 합니다.
> 다른 프로젝트와 혼용해서 Xcode 버전을 바꾼 경우, Voyager 작업 전에 `./scripts/xcodes.sh`를 한 번 실행해 Xcode 버전을 다시 맞춰 주세요.

## Conventions

- Git Flow

  - **브랜치 구조**
    - `main`: 운영/배포 브랜치 (태그: `vX.Y.Z`)
    - `develop`: 개발 통합 브랜치
    - `release/v<X.Y.Z>`: 릴리즈 준비/안정화 브랜치
    - `<type>/<linear-issue>`: 이슈별 개발 브랜치
      - `type`: `feature`, `fix`, `chore`, `refactor`, `docs`, `test`, `ci`
      - 예: `feature/voy-123`, `fix/voy-456`
    - `hotfix/<linear-issue>`: 운영 긴급 수정 브랜치

  - **일반 개발 워크플로우**
    1. `develop`에서 `<type>/<linear-issue>` 브랜치 생성
    2. 개발 완료 후 `develop`으로 PR 생성 및 머지
    3. 머지 후 작업 브랜치 삭제

  - **릴리즈 워크플로우**
    1. `develop`에서 `release/v<X.Y.Z>` 브랜치 생성
    2. 릴리즈 브랜치에서 버그 수정이 필요한 경우 `fix/<linear-issue>` 분기 후 `release/v<X.Y.Z>`로 PR 머지
    3. 릴리즈 준비 완료 후 `release/v<X.Y.Z> -> main` PR 머지 및 `vX.Y.Z` 태그 생성
    4. `main -> develop` (또는 `release/v<X.Y.Z> -> develop`)로 back-merge

  - **Hotfix 워크플로우**
    1. `main`에서 `hotfix/<linear-issue>` 브랜치 생성
    2. 수정 후 `main`으로 PR 머지
    3. 동일 변경사항을 `develop` 및 진행 중인 `release/*` 브랜치에도 반영

- Conventional Commits

  - Subject: `<type>(<scope>): <short description>` (명령형, ≲ 50자)
  - Scope: 모노레포 명확성을 위해 `(backend)` 또는 `(macos)` 권장
  - Types: `feat`, `fix`, `ui`, `refactor`, `style`, `docs`, `chore`, `test`, `ci`, `build`
  - Body: `- ` 불릿으로 WHAT/WHY, 현재형, 영향 범위/파일 필요 시 명시
  - 예시:
    - `feat(backend): add asset ingestion endpoint`
    - `fix(macos): resolve crash on QuickLook preview`
    - `ui(macos): improve sidebar navigation layout`
    - `docs: consolidate API contract guidelines`
- Pull Requests

  - PR 설명에 의도/범위/리스크/검증 증거/롤백 포함, 관련 이슈 링크 및 UI 변경 시 스크린샷 첨부
  - 문서/코드 변경이 함께 있을 때는 범위를 분리하고 작은 PR을 선호

## Documentation for Agents

- Entry point: `docs/index.md` (PRD / Architecture / Frontend Spec 샤드 인덱스)
- Architecture quick refs loaded by tools:
  - `docs/architecture/coding-standards.md`
  - `docs/architecture/tech-stack.md`
  - `docs/architecture/source-tree.md`

## Back to Docs

- 전체 문서 인덱스: `docs/index.md`
