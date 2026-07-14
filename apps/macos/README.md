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

Terminal, Zed, VSCode/Sweetpad task는 같은 build flag와 DerivedData 경로를 쓰도록 `scripts/dev/macos-launch.sh`를 표준 진입점으로 사용합니다.

```bash
# 기본 개발 앱 빌드 후 실행
mise run macos-launch

# 저장된 진행 상태를 유지한 채 온보딩 강제 표시(Debug 전용, 일회성)
mise run macos-launch -- --scheme Voyager-Dev --configuration Debug --env VOYAGER_SCHEME_FORCE_ONBOARDING=1

# 특정 scheme/configuration 빌드 후 실행
mise run macos-launch -- --scheme SettingsHost-Dev --configuration Debug

# 빌드만 확인
mise run macos-launch -- --scheme Voyager-Dev --configuration Debug --no-launch
```

`Voyager-Dev`가 유일한 개발 실행 scheme입니다. Debug 실행의 `VOYAGER_SCHEME_FORCE_ONBOARDING` launch 환경변수가 `0`이거나 없으면 저장된 진행 상태에 따라 동작하고, 정확히 `1`이면 저장된 진행 상태를 지우지 않은 채 온보딩을 강제로 표시합니다. 이 값은 `.env` 설정이 아니며 Release/Prod에서는 지원하지 않습니다.

기본 build flag는 다음 경로로 고정됩니다.

- `-derivedDataPath build/dev/DerivedData`
- `-clonedSourcePackagesDirPath build/dev/SourcePackages`
- `-skipPackagePluginValidation`
- `-skipMacroValidation`
- `COMPILER_INDEX_STORE_ENABLE=NO`

### IDE별 실행 경로와 온보딩 표시 토글

- Xcode: `apps/macos/Voyager/Voyager.xcworkspace`를 열고 `Voyager-Dev` scheme을 선택합니다. Debug Run 환경변수 `VOYAGER_SCHEME_FORCE_ONBOARDING`을 `0` 또는 제거하면 저장된 진행 상태를 사용하고, 정확히 `1`로 설정하면 진행 상태를 유지한 채 온보딩을 강제로 표시합니다.
- Zed: `.zed/tasks.json`의 `Voyager Dev: Launch (Debug)` task를 실행합니다. task의 `VOYAGER_SCHEME_FORCE_ONBOARDING` 값을 `0` 또는 제거하면 저장된 진행 상태를 사용하고, 정확히 `1`로 바꾸면 온보딩을 강제로 표시합니다.
- VSCode/Sweetpad: `.vscode/tasks.json`의 `Voyager Dev: Launch (Debug)` task를 실행합니다. task의 `VOYAGER_SCHEME_FORCE_ONBOARDING` 값을 Zed와 같이 설정합니다. Sweetpad build는 `.vscode/settings.json`의 shared xcodebuild wrapper를 사용합니다.

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

### 테스트 실행 (xcodebuild 직접)

```bash
# 모든 테스트 실행(개발)
xcodebuild test -project Voyager.xcodeproj -scheme Voyager-Dev

# 단위 테스트 실행
xcodebuild test -project Voyager.xcodeproj -scheme Voyager-Dev -only-testing:VoyagerTests

# 특정 suite 실행
xcodebuild test -project Voyager.xcodeproj -scheme Voyager-Dev -only-testing:VoyagerTests/AccessUnlockFlowTests
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
- **InjectionNext** : 고급 코드 인젝션
- **swift-identified-collections** : 식별 가능한 컬렉션
- **swift-dependencies** : 의존성 주입 프레임워크

### InjectionNext 사용법

#### 필요한 설정 - 완료

- **Other Linker Flags**: `-Xlinker -interposable` (Debug 빌드에만 적용)
- **Swift Package**: InjectionNext 의존성
- **Scheme Environment Variables**: `INJECTION_PROJECT_ROOT = $(SRCROOT)`

#### 사용 방법

1. **InjectionNext 앱 다운로드 및 설치**:

    ```bash
    # https://github.com/johnno1962/InjectionNext/releases 에서 다운로드
    # Applications 폴더로 이동
    ```

2. **InjectionNext 앱에서 "Launch Xcode" 실행**

3. **코드 변경 후 저장하면 자동으로 함수 레벨 인젝션 적용**

#### 제한사항

- 함수 본문만 변경 가능
- 프로퍼티 추가/삭제 불가
- 메서드 시그니처 변경 불가
