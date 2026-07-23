# Voyager macOS

## 개발 환경 설정

### 필수 요구사항

- **macOS**: 13.5 (Ventura) 이상
- **Xcode**: 26.1 (`.xcode-version` 고정)
- **Swift**: 6.2.1 (Xcode 26.1 toolchain)
- **SwiftLint**: 코드 스타일 검사 도구 (`mise.toml` 고정)
- **SwiftFormat**: 코드 포맷팅 도구 (`mise.toml` 고정)

### 1. 프로젝트 클론 및 설정

```bash
# 저장소 클론
git clone https://github.com/voyager-labs/voyager-app.git
cd voyager-app

# 개발 환경 한 번에 설정 (mise, Xcode, hooks, submodules, xcode-build-server)
bash scripts/setup.sh

# Xcode 프로젝트 열기
open apps/macos/Voyager/Voyager.xcworkspace
```

> SwiftLint, SwiftFormat 등 도구는 `mise.toml`에 버전이 고정되어 있으며
> `bash scripts/setup.sh`로 자동 설치됩니다.

## 개발 도구 설정

### Xcode 설정

1. **Build Settings**에서 다음을 확인:
    - Deployment Target: macOS 13.5
    - Swift Language Version: 프로젝트 기본값 사용 (Xcode 26.1 toolchain 기준)

2. **Scheme 설정**:
    - Run schemes:
        - Voyager-Dev (유일한 개발 실행 scheme)
        - Voyager-Prod (배포/Archive)
    - Helper schemes:
        - VoyagerHelper-Dev (개발용 헬퍼)
        - VoyagerHelper-Prod (배포/Archive 헬퍼)
    - Host schemes (별도 프로젝트):
        - OnboardingHost-Dev (온보딩 호스트 개발)
        - SettingsHost-Dev (설정 호스트 개발)
        - FileManagerHost-Dev (File Manager mock-only fixture/smoke 개발)
    - Test schemes: VoyagerTests, VoyagerUITests

## 빌드 및 실행

### 표준 launch 엔트리포인트

Terminal, Zed, VSCode/Sweetpad task는 `scripts/dev/xcodebuild-branch-product.sh`를 공유 injection seam으로 사용합니다. launch는 `scripts/dev/macos-launch.sh`를 통해 이 wrapper로 간접 연결됩니다.

```bash
# 기본 개발 앱 빌드 후 실행
mise run macos-launch

# 저장된 진행 상태를 유지한 채 온보딩 강제 표시(Debug 전용, 일회성)
mise run macos-launch -- --scheme Voyager-Dev --configuration Dev-Debug --env VOYAGER_SCHEME_FORCE_ONBOARDING=1

# 특정 scheme/configuration 빌드 후 실행
mise run macos-launch -- --scheme SettingsHost-Dev --configuration Dev-Debug

# 빌드만 확인
mise run macos-launch -- --scheme Voyager-Dev --configuration Dev-Debug --no-launch
```

`Voyager-Dev`가 유일한 개발 실행 scheme입니다. Debug 실행의 `VOYAGER_SCHEME_FORCE_ONBOARDING` launch 환경변수가 `0`이거나 없으면 저장된 진행 상태에 따라 동작하고, 정확히 `1`이면 저장된 진행 상태를 지우지 않은 채 온보딩을 강제로 표시합니다. 이 값은 `.env` 설정이 아니며 Release/Prod에서는 지원하지 않습니다.

### Xcode build cache

wrapper는 선택한 workspace/project의 `Package.resolved`, 전체 Xcode build version, Swift toolchain version으로 dependency/toolchain key를 계산합니다. 기본 root는 `~/Library/Caches/Voyager/XcodeBuild`이며 테스트나 로컬 환경에서는 `VOYAGER_XCODE_CACHE_ROOT`로 override할 수 있습니다.

- 공유 SwiftPM package support cache: `package-cache/<dependency-toolchain-key>` (`-packageCachePath`)
- worktree-local DerivedData: `<worktree>/build/dev/DerivedData` (`-derivedDataPath`)
- worktree-local writable checkouts: `<worktree>/build/dev/SourcePackages` (`-clonedSourcePackagesDirPath`)
- 공유 registry와 lock: `worktrees/<worktree-key>/metadata.json`, `locks/worktrees/`, `locks/package-cache/`

따라서 같은 dependency/toolchain을 쓰는 worktree는 다운로드 캐시만 공유하고, `SourcePackages/checkouts`와 DerivedData는 공유하지 않습니다. 기본 payload 경로는 절대 경로로 주입됩니다. 호출자가 이 세 flag를 명시하면 wrapper는 해당 값을 중복 없이 보존하며 resolver는 그 외부 경로를 registry에 관리 대상이라고 기록하지 않습니다. build log와 report는 계속 worktree의 `build/dev/`에 남습니다.

```bash
# 현재 cache 사용량과 worktree/host/entrypoint별 accounting 확인
mise run macos-cache-report

# 30일 이상 된 orphan entry 후보를 출력만 함 (기본, 안전)
mise run macos-cache-prune

# 실제 삭제: active Git worktree와 running-build lock은 항상 보호됨
mise run macos-cache-prune -- --apply --older-than-days 30
```

report는 active Git worktree의 local payload를 한 번만 계산하고 공유 package cache를 별도로 합산합니다. 예전 중앙 payload가 남아 있으면 `stale_central_entries`로 관찰만 하며 새 중앙 DerivedData는 만들지 않습니다. prune은 cache root 밖을 삭제하지 않으며, metadata가 없거나 stale한 entry, 삭제된 worktree, symlink/containment 검증 실패, 또는 lock을 즉시 얻지 못한 entry도 삭제하지 않습니다. `--apply`도 검증된 `<worktree>/build/dev/{DerivedData,SourcePackages}`만 삭제하며 logs, reports, 다른 build 하위 디렉터리는 보존합니다.

### IDE별 실행 경로와 온보딩 표시 토글

- Xcode: `apps/macos/Voyager/Voyager.xcworkspace`를 열고 `Voyager-Dev` scheme을 선택합니다. Debug Run 환경변수 `VOYAGER_SCHEME_FORCE_ONBOARDING`을 `0` 또는 제거하면 저장된 진행 상태를 사용하고, 정확히 `1`로 설정하면 진행 상태를 유지한 채 온보딩을 강제로 표시합니다.
- Zed: `.zed/tasks.json`의 `Voyager Dev: Launch (Dev-Debug)` task를 실행합니다. task의 `VOYAGER_SCHEME_FORCE_ONBOARDING` 값을 `0` 또는 제거하면 저장된 진행 상태를 사용하고, 정확히 `1`로 바꾸면 온보딩을 강제로 표시합니다.
- VSCode/Sweetpad: `.vscode/tasks.json`의 `Voyager Dev: Launch (Dev-Debug)` task를 실행합니다. task의 `VOYAGER_SCHEME_FORCE_ONBOARDING` 값을 Zed와 같이 설정합니다. Sweetpad build는 `.vscode/settings.json`의 shared xcodebuild wrapper를 사용합니다.

이 토글은 launch 환경이며 `.env` 파일에 설정하지 않습니다. Debug 전용 동작이므로 Release/Prod에서는 지원하지 않습니다.

## 테스트

### 테스트 실행 (mise 권장)

```bash
# 전체 Voyager-Dev 테스트 (광범위, human/CI용)
mise run macos-test

# 특정 PRODUCT flow 테스트 (focused)
mise run macos-test-flow -- --flow onb.access_unlock

# 카테고리별 flow 테스트
mise run macos-test-flow -- --category onb

# 매핑된 flow suite 목록 확인
mise run macos-test-flow -- --list

# 구조 무결성 검사
mise run macos-test-flow -- --check
```

`mise run macos-test`는 광범위한 전체 테스트를 실행하고, `mise run macos-test-flow`는 canonical PRODUCT flow 문서에 매핑된 flow suite만 focused로 실행합니다.

### selector로 테스트 좁히기

```bash
# 모든 개발 테스트 실행
mise run macos-test

# 단위 테스트 실행
mise run macos-test -- -only-testing:VoyagerTests

# 특정 suite 실행
mise run macos-test -- -only-testing:VoyagerTests/AccessUnlockFlowTests
```

### 로그 확인

```bash
log stream --predicate 'subsystem == "com.voyager.app"'
```

## 프로젝트 구성

### 타겟 설명

**Voyager.xcodeproj**

- **Voyager**: 메인 macOS 파일 관리자 앱
- **VoyagerHelper**: 인덱싱/검색 런타임(XPC, DB)을 관리하는 헬퍼 앱

**OnboardingHost.xcodeproj** (별도 프로젝트)

- **OnboardingHost**: 온보딩 전용 호스트 앱 (`apps/macos/Hosts/OnboardingHost/OnboardingHost.xcodeproj`)
    - 독립적인 Xcode 프로젝트로, Voyager.xcworkspace에 통합되어 있습니다
    - 배포용 타겟이 아닌 개발/테스트용 호스트입니다

**FileManagerHost.xcodeproj** (별도 프로젝트)

- **FileManagerHost**: File Manager Window mock-only fixture/smoke 호스트 앱 (`apps/macos/Hosts/FileManagerHost/FileManagerHost.xcodeproj`)
    - 전체 Voyager 앱 bootstrap 없이 실제 File Manager UI 조합을 deterministic mock state로 확인합니다
    - Host 앱은 별도 catalog 없이 기본 mock state를 사용해 실제 File Manager window view controller를 띄웁니다
    - smoke 검증은 `FILE_MANAGER_HOST_SMOKE=1`로 view controller mount 가능 여부를 빠르게 확인합니다

## 의존성 관리

### Swift Package Manager

프로젝트에서 사용하는 외부 라이브러리:

- **swift-composable-architecture** : TCA 프레임워크 (상태 관리)
- **swiftui-introspect** : SwiftUI에서 AppKit 접근
- **swift-dotenv** : 환경변수 관리 (.env 파일 지원)
- **Inject** : SwiftUI 핫 리로딩
- **swift-identified-collections** : 식별 가능한 컬렉션
- **swift-dependencies** : 의존성 주입 프레임워크

### InjectionNext 사용법

InjectionNext는 `FileManagerHost` 전용 Debug 개발 도구입니다. `Voyager`와 `VoyagerHelper`는 이를 링크하거나 런타임에 로드하지 않으며, 일반 `Voyager-Dev` Debug와 모든 Release 빌드는 interposable linker flag를 사용하지 않습니다.

1. [InjectionNext releases](https://github.com/johnno1962/InjectionNext/releases)에서 앱을 설치합니다.
2. InjectionNext 앱에서 **Launch Xcode**를 선택합니다.
3. Xcode에서 `apps/macos/Hosts/FileManagerHost/FileManagerHost.xcodeproj`를 열고 `FileManagerHost-Dev` scheme을 Debug로 실행합니다.

터미널이나 IDE task에서는 아래 전용 task가 InjectionNext.app 실행, Debug 전용 linker 환경, `apps/macos` 감시 경로, FileManagerHost 실행을 함께 처리합니다.

```bash
mise run macos-filemanager-injection
```

Zed와 VSCode에서는 `FileManagerHost Dev: Launch with Injection (Dev-Debug)` task를 선택합니다. 기존 FileManagerHost Dev-Debug/Dev-Release task는 Injection 없는 일반 실행으로 유지됩니다.

`INJECTION_PROJECT_ROOT`는 `apps/macos`를 가리키므로 Host와 `Packages` 소스를 함께 감시합니다. Content Tab sidebar row는 HotSwiftUI를 통해 재그리기되며, InjectionNext 전용 Xcode/task 환경에서만 FileManager 패키지가 `-Xlinker -interposable`을 추가합니다.

함수 본문 변경은 저장 후 주입할 수 있지만, 프로퍼티·타입·메서드 시그니처·패키지/프로젝트 설정 같은 구조 변경은 주입 대상이 아닙니다. 이런 변경 뒤에는 FileManagerHost를 일반적으로 다시 빌드하고 실행해야 합니다.
