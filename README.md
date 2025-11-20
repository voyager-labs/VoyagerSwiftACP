# Voyager App

프로젝트 개요와 실행/문서 진입점을 간단히 제공합니다.

## Monorepo Layout

- `apps/backend`: FastAPI 백엔드 (uv)
- `apps/macos/Voyager`: macOS SwiftUI + TCA 앱과 Helper
- `docs/`: AI 에이전트용 PRD/아키텍처 문서 인덱스

## Environment Setup

- 루트에서 `.env.example` → `.env` 복사 후 필요한 값 채우기
- `APP_ENV`는 지원하는 값 `dev` 또는 `prod`만 사용합니다.
- 백엔드 기동에 필요한 기본 키: `UV_CMD`, `BACKEND_DIR`, `VOYAGER_HOST`, `VOYAGER_PORT`, `BACKEND_URL`, `VOYAGER_LOG_FILE`
- 비밀키(`OPENAI_API_KEY` 등)는 커밋 금지, 로컬 `.env`나 CI 시크릿으로만 관리

## Quick Start

* Backend

  * Setup: `cd apps/backend && uv sync && uv run pre-commit install`
  * Dev server: `uv run dev`
  * Tests: `uv run pytest`
* macOS App

  * Xcode에서 시작: `xed apps/macos/Voyager/Voyager.xcodeproj` (열기 후 `Cmd+R` 실행)
  * VSCode 류 IDE(Sweetpad Extension)에서 실행:
    * Xcode 프로젝트 열기: Sweetpad로 `apps/macos/Voyager/Voyager.xcodeproj` 오픈
    * 스킴 실행: `Voyager-Dev` 스킴을 선택하여 Debug 구성으로 실행
    * 참고: Sweetpad 환경에 따라 CLI/버튼 동작이 다를 수 있습니다. 스킴/구성은 Xcode 프로젝트와 동기화되어야 합니다.
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
* 다른 프로젝트 때문에 Xcode 버전을 변경했다가, **다시 Voyager 앱을 개발하려고 할 때**
* `.xcode-version`이 변경된 PR이 머지되어, **새로운 공식 Xcode 버전에 맞추어야 할 때**

> 이 레포에서 작업할 때는 항상 `.xcode-version`에 적힌 Xcode 버전으로 빌드하는 것을 원칙으로 합니다.
> 다른 프로젝트와 혼용해서 Xcode 버전을 바꾼 경우, Voyager 작업 전에 `./scripts/xcodes.sh`를 한 번 실행해 Xcode 버전을 다시 맞춰 주세요.

## Conventions

- Git Flow

  - 기본: `main` (현재 개발 브랜치). 추후 `dev`/`staging` 분기 도입 가능.
  - Linear Project 브랜치: `proj/{project_slug}`

    - `main`에서 분기해 프로젝트 단위 작업 집약
    - 예) proj/files
  - Linear Issue 브랜치: `{project_slug}/{linear_issue_id}`

    - 해당 `proj/{project_slug}`에서 분기
    - 예) files/voy-1
  - PR 흐름:

    - 이슈 처리 시: `{project_slug}/{linear_issue_id}` → `proj/{project_slug}` 로 PR
    - 프로젝트 마감: `proj/{project_slug}` → `main` 으로 PR
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
