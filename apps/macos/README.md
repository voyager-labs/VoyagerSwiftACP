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
        - Voyager-Dev (개발 실행)
        - Voyager-Prod (배포/Archive)
    - Helper schemes:
        - VoyagerHelper-Dev (개발용 헬퍼)
        - VoyagerHelper-Prod (배포/Archive 헬퍼)
    - Host schemes (별도 프로젝트 — OnboardingHost.xcodeproj):
        - OnboardingHost-Dev (온보딩 호스트 개발)
    - Test schemes: VoyagerTests, VoyagerUITests

## 빌드 및 실행

### CLI 빌드

**Voyager.xcodeproj**

```bash
# 프로젝트 빌드 (개발)
xcodebuild -project Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug build

# 프로젝트 빌드/Archive (배포)
xcodebuild -project Voyager.xcodeproj -scheme Voyager-Prod -configuration Release build

# 테스트 실행 (개발)
xcodebuild -project Voyager.xcodeproj -scheme Voyager-Dev test
```

**OnboardingHost.xcodeproj** (별도 프로젝트)

```bash
# 온보딩 호스트 빌드 (개발)
xcodebuild -project apps/macos/Hosts/OnboardingHost/OnboardingHost.xcodeproj -scheme OnboardingHost-Dev -configuration Debug build
```

> 참고: OnboardingHost는 독립적인 Xcode 프로젝트입니다. `-project` 경로를 명시적으로 지정해야 합니다.

## 테스트

### 테스트 실행

```bash
# 모든 테스트 실행(개발)
xcodebuild test -project Voyager.xcodeproj -scheme Voyager-Dev

# 단위 테스트 실행
xcodebuild test -project Voyager.xcodeproj -scheme Voyager-Dev -only-testing:VoyagerTests

# UI 테스트 실행
xcodebuild test -project Voyager.xcodeproj -scheme Voyager-Dev -only-testing:VoyagerUITests

# 헬퍼 앱 테스트 실행
xcodebuild test -project Voyager.xcodeproj -scheme VoyagerHelper-Dev
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
