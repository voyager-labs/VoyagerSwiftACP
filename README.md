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

macOS 앱 검색 경로는 Helper/XPC + Gateway를 사용하며, 로컬 FastAPI 프로세스를 앱 번들에서 직접 실행하지 않습니다.

- **Dev/Prod 공통**: Helper 및 XPC 서비스가 검색/인덱싱 런타임을 담당
- 백엔드(`apps/backend`)는 별도 서버 런타임으로 독립 운영

### 보안

- 비밀키는 커밋 금지
- 로컬 개발: `.env.dev` 파일 사용 (Git ignored)
- CI/CD: `.env.prod`는 secrets 없이 복사 (앱 번들 노출 방지)

## Quick Start

- Backend
    - Setup: `cd apps/backend && uv sync && uv run pre-commit install`
    - Dev server: `uv run dev`
    - Tests: `uv run pytest`

- macOS App
    - Xcode에서 시작(권장): `xed apps/macos/Voyager/Voyager.xcworkspace` (열기 후 `Cmd+R` 실행)
        - Workspace에 Voyager.xcodeproj, OnboardingHost.xcodeproj, SettingsHost.xcodeproj가 포함되어 있습니다
    - (대안) Xcode 프로젝트: `xed apps/macos/Voyager/Voyager.xcodeproj`
    - Terminal/Agent에서 실행:
        - 기본 개발 앱 실행: `mise run macos-launch`
        - 온보딩 표시 토글(Debug 전용): `Voyager-Dev`가 유일한 개발 scheme입니다. `VOYAGER_SCHEME_FORCE_ONBOARDING` launch 환경변수가 `0`이거나 없으면 저장된 진행 상태에 따라 동작하고, 정확히 `1`이면 저장된 진행 상태를 지우지 않은 채 온보딩을 강제로 표시합니다. 이 값은 `.env` 설정이 아니며 Release/Prod에서는 지원하지 않습니다.
        - 일회성 강제 표시: `mise run macos-launch -- --scheme Voyager-Dev --configuration Debug --env VOYAGER_SCHEME_FORCE_ONBOARDING=1`
        - 다른 scheme 실행: `mise run macos-launch -- --scheme SettingsHost-Dev --configuration Debug`
        - 빌드만 확인: `mise run macos-launch -- --scheme Voyager-Dev --configuration Debug --no-launch`
    - Xcode에서 실행:
        - `Voyager-Dev` scheme의 Debug Run 환경변수 `VOYAGER_SCHEME_FORCE_ONBOARDING`을 `0` 또는 제거하면 저장된 진행 상태를 사용합니다.
        - 같은 환경변수를 정확히 `1`로 설정하면 진행 상태를 유지한 채 온보딩을 강제로 표시합니다.
    - VSCode 류 IDE(Sweetpad Extension)에서 실행:
        - Xcode 프로젝트 열기: Sweetpad로 `apps/macos/Voyager/Voyager.xcodeproj` 오픈
        - 태스크로 실행 (권장):
            - `Cmd+Shift+P` (또는 `Ctrl+Shift+P`)로 Command Palette 열기
            - "Tasks: Run Task" 입력 후 다음 태스크 중 선택:
                - `Voyager Dev: Launch (Debug)` - 개발 환경 Debug 모드로 빌드 및 실행
                - `Voyager Dev: Launch (Release)` - 개발 환경 Release 모드로 빌드 및 실행
                - `Voyager Prod: Launch (Debug)` - 프로덕션 환경 Debug 모드로 빌드 및 실행
                - `Voyager Prod: Launch (Release)` - 프로덕션 환경 Release 모드로 빌드 및 실행
                - `OnboardingHost Dev: Launch (Debug)` - 온보딩 호스트 Debug 모드로 빌드 및 실행
                - `OnboardingHost Dev: Launch (Release)` - 온보딩 호스트 Release 모드로 빌드 및 실행
                - `SettingsHost Dev: Launch (Debug)` - 설정 호스트 Debug 모드로 빌드 및 실행
                - `SettingsHost Dev: Launch (Release)` - 설정 호스트 Release 모드로 빌드 및 실행
            - `Voyager Dev: Launch (Debug)` task의 `VOYAGER_SCHEME_FORCE_ONBOARDING` 값을 `0` 또는 제거하면 저장된 진행 상태를 사용하고, 정확히 `1`로 바꾸면 진행 상태를 유지한 채 온보딩을 강제로 표시합니다. 이 값은 launch 환경이며 `.env` 설정이 아니고 Release/Prod에서는 지원하지 않습니다.
            - 참고: Sweetpad는 `.vscode/settings.json`의 shared xcodebuild wrapper를 사용합니다. 버튼을 통한 직접 실행은 xcscheme의 환경변수가 제대로 주입되지 않을 수 있어 태스크 실행을 권장합니다.
    - Zed 에디터에서 실행 (`.zed/tasks.json`):
        - 태스크 실행: `task: spawn` (단축키 `opt-shift-t`)으로 태스크 선택 모달 열기
        - 재실행: `task: rerun` (단축키 `opt-t`)
        - 사용 가능한 태스크 (VSCode Sweetpad와 동일):
            - `Voyager Dev: Launch (Debug)` / `Voyager Dev: Launch (Release)`
            - `Voyager Prod: Launch (Debug)` / `Voyager Prod: Launch (Release)`
            - `VoyagerHelper Dev: Launch (Debug)` / `VoyagerHelper Dev: Launch (Release)`
            - `OnboardingHost Dev: Launch (Debug)` / `OnboardingHost Dev: Launch (Release)`
            - `SettingsHost Dev: Launch (Debug)` / `SettingsHost Dev: Launch (Release)`
            - `FileManagerHost Dev: Launch (Debug)` / `FileManagerHost Dev: Launch (Release)`
            - `Voyager Dev: Build Only (Debug)` - 빌드만 (런치 없음)
            - `Voyager Dev: Test` - Voyager-Dev 스킴 테스트
        - `Voyager Dev: Launch (Debug)` task의 `VOYAGER_SCHEME_FORCE_ONBOARDING` 값을 `0` 또는 제거하면 저장된 진행 상태를 사용하고, 정확히 `1`로 바꾸면 진행 상태를 유지한 채 온보딩을 강제로 표시합니다. 이 값은 launch 환경이며 `.env` 설정이 아니고 Release/Prod에서는 지원하지 않습니다.
        - 내부 동작: `scripts/dev/macos-launch.sh`가 xcodebuild 빌드 → `.app` 산출물 해석 → 태스크별 launch 환경변수 주입 후 실행파일 직접 실행
        - Zed 태스크의 환경변수는 `.zed/tasks.json`에서 명시적으로 전달합니다. 런타임 `.env` 표준화는 별도 이슈(VOY-432)에서 다룹니다.
    - Build (CLI): `mise run macos-build`
    - Prod build/archive (CLI): `mise run macos-launch -- --scheme Voyager-Prod --configuration Release --no-launch`
    - Tests (CLI): `mise run macos-test`
    - OnboardingHost Build (CLI): `mise run macos-launch -- --scheme OnboardingHost-Dev --configuration Debug --no-launch`
    - SettingsHost Build (CLI): `mise run macos-launch -- --scheme SettingsHost-Dev --configuration Debug --no-launch`

### Xcode 버전 관리

이 레포에서는 루트 디렉터리의 `.xcode-version` 파일로 **공식 Xcode 버전**을 고정해서 사용합니다.
현재 기준 버전은 Xcode 26.1이며, 이 Xcode가 제공하는 Swift 6.2.1을 사용합니다.
Swift 기대 버전은 루트 `.swift-toolchain-version`에 별도로 명시합니다.
모든 로컬 개발 환경과 CI는 이 버전에 맞추는 것을 원칙으로 합니다.

`swiftly`를 사용하는 환경을 위해 루트 `.swift-version`은 `xcode`로 고정합니다.
`.swift-version`은 swiftly가 읽는 toolchain 선택 파일이고, `.swift-toolchain-version`은 이 레포가 기대하는 Swift 버전을 검증하기 위한 파일입니다.
따라서 `swiftly`가 PATH에서 먼저 잡히더라도 레포 안에서는 현재 선택된 Xcode toolchain을 사용하고, 그 결과가 Swift 6.2.1인지 `mise run swift-version`으로 확인합니다.

#### 사전 준비

- macOS
- Xcode 설치 및 업데이트 권한

#### 이 프로젝트용 Xcode 설정 방법

처음 클론했거나, Xcode 버전을 다시 맞추고 싶을 때 **레포 루트에서** 다음을 실행합니다.

```bash
chmod +x scripts/xcodes.sh   # 최초 1회만 필요 (이미 실행 권한이 있으면 생략 가능)
./scripts/xcodes.sh
```

이 스크립트는 다음 작업을 수행합니다.

1. 레포 루트의 `.xcode-version` 파일을 읽어, 필요한 Xcode 버전을 확인합니다.
2. `xcodes` CLI가 설치되어 있지 않으면 설치합니다.
3. `xcodes install <버전>`으로 해당 Xcode 버전을 설치합니다. (이미 설치되어 있다면 건너뜁니다)
4. `xcodes select <버전>`으로 해당 버전을 현재 macOS의 활성 Xcode로 설정합니다.

`swiftly`를 별도로 쓰는 경우에는 아래 명령으로 레포 기준 Swift toolchain도 확인할 수 있습니다.

```bash
swiftly use
mise run swift-version
```

정상이라면 `swiftly use`는 `xcode`, `mise run swift-version`은 `.swift-toolchain-version`과 일치하는 Swift 6.2.1을 출력합니다.

설정이 제대로 되었는지 확인하려면:

```bash
xcodebuild -version
```

을 실행했을 때 출력되는 Xcode 버전이 `.xcode-version`에 적힌 값과 일치해야 합니다.

#### 스크립트를 실행해야 하는 시점

- 이 레포를 **처음 클론한 직후**

## Development Bootstrap (Git hooks)

커밋 시점에 Swift/Python 포맷/린트를 자동으로 실행해서 실패하면 커밋을 막습니다.

처음 클론한 후(그리고 새로운 머신에서) **레포 루트에서 한 번만** 실행하세요:

```bash
bash scripts/setup.sh
```

이 설정은 repo-local git config(`core.hooksPath`)에 저장되며, 동일 레포에서 생성한 worktree에도 그대로 적용되는 것을 목표로 합니다.

- 다른 프로젝트 때문에 Xcode 버전을 변경했다가, **다시 Voyager 앱을 개발하려고 할 때**
- `.xcode-version`이 변경된 PR이 머지되어, **새로운 공식 Xcode 버전에 맞추어야 할 때**

> 이 레포에서 작업할 때는 항상 `.xcode-version`에 적힌 Xcode 버전으로 빌드하는 것을 원칙으로 합니다.
> 다른 프로젝트와 혼용해서 Xcode 버전을 바꾼 경우, Voyager 작업 전에 `./scripts/xcodes.sh`를 한 번 실행해 Xcode 버전을 다시 맞춰 주세요.

## Cupertino Apple Docs MCP

이 레포의 `opencode.json`에는 Apple 플랫폼 문서 검색용 `cupertino` MCP가 함께 선언되어 있습니다.
`mise`로 버전 고정 관리되며, `mise install cupertino`로 설치할 수 있습니다.

- 지원 플랫폼: macOS 15+
- 설치:

```bash
mise install cupertino
```

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

- 진입점: `docs/index.md`
- Active engineering 문서: `docs/canonical/ENGINEERING/index.md`
- Canonical product/docs SSOT: `docs/canonical/README.md`
- Engineering quick refs:
    - `docs/canonical/ENGINEERING/common/coding-standards.md`
    - `docs/canonical/ENGINEERING/common/tech-stack.md`
    - `docs/canonical/ENGINEERING/app/topology/source-tree.md`

## Back to Docs

- 전체 문서 인덱스: `docs/index.md`
