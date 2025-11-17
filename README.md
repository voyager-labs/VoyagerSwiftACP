# Voyager App

프로젝트 개요와 실행/문서 진입점을 간단히 제공합니다.

## Quick Start

- Backend

  - Setup: `cd apps/backend && uv sync && uv run pre-commit install`
  - Dev server: `uv run dev`
  - Tests: `uv run pytest`
- macOS App

  - Xcode에서 시작: `xed apps/macos/Voyager/Voyager.xcodeproj` (열기 후 `Cmd+R` 실행)
  - VSCode 류 IDE(Sweetpad Extension)에서 실행:
    - Xcode 프로젝트 열기: Sweetpad로 `apps/macos/Voyager/Voyager.xcodeproj` 오픈
    - 스킴 실행: `Voyager` 스킴을 선택하여 Debug 구성으로 실행
    - 참고: Sweetpad 환경에 따라 CLI/버튼 동작이 다를 수 있습니다. 스킴/구성은 Xcode 프로젝트와 동기화되어야 합니다.
  - Build (CLI): `xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager -configuration Debug`
  - Tests (CLI): `xcodebuild test -scheme Voyager -project apps/macos/Voyager/Voyager.xcodeproj`

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
