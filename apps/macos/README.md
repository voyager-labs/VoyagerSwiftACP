# Voyager macOS

## 개발 환경 설정

### 필수 요구사항

-   **macOS**: 12.4 (Monterey) 이상
-   **Swift**: 5.0 이상
-   **SwiftLint**: 코드 스타일 검사 도구
-   **SwiftFormat**: 코드 포맷팅 도구

### 1. 프로젝트 클론 및 설정

```bash
# 저장소 클론
git clone https://github.com/voyager-labs/voyager-app.git
cd voyager-app/apps/macos/Voyager

# Xcode 프로젝트 열기
open Voyager.xcworkspace
```

### 2. SwiftLint 설치

```bash
brew install swiftlint
```

### 3. SwiftFormat 설치

```bash
brew install swiftformat
```

## 개발 도구 설정

### Xcode 설정

1. **Build Settings**에서 다음을 확인:

    - Deployment Target: macOS 12.4
    - Swift Language Version: Swift 5.0

2. **Scheme 설정**:

    - Run scheme: Voyager
    - Test scheme: VoyagerTests

## 빌드 및 실행

### CLI 빌드

```bash
# 프로젝트 빌드
xcodebuild -workspace Voyager.xcworkspace -scheme Voyager -configuration Debug build

# 테스트 실행
xcodebuild -workspace Voyager.xcworkspace -scheme Voyager test
```

## 테스트

### 테스트 실행

```bash
# 모든 테스트 실행
xcodebuild test -workspace Voyager.xcworkspace -scheme Voyager

# 특정 테스트 타겟 실행
xcodebuild test -workspace Voyager.xcworkspace -scheme VoyagerTests
```

### 로그 확인

```bash
log stream --predicate 'subsystem == "com.voyager.app"'
```

## 의존성 관리

### Swift Package Manager

프로젝트에서 사용하는 외부 라이브러리:

-   **SwiftDotenv** : 환경변수 관리
-   **Inject** : SwiftUI 핫 리로딩
-   **SwiftLint** : 코드 스타일 검사 도구
-   **SwiftFormat** : 코드 포맷팅 도구
-   **InjectionNext** : 고급 코드 인젝션

### InjectionNext 사용법

#### 필요한 설정 - 완료

-   **Other Linker Flags**: `-Xlinker -interposable` (Debug 빌드에만 적용)
-   **Swift Package**: InjectionNext 의존성
-   **Scheme Environment Variables**: `INJECTION_PROJECT_ROOT = $(SRCROOT)`

#### 사용 방법

1. **InjectionNext 앱 다운로드 및 설치**:

    ```bash
    # https://github.com/johnno1962/InjectionNext/releases 에서 다운로드
    # Applications 폴더로 이동
    ```

2. **InjectionNext 앱에서 "Launch Xcode" 실행**

3. **코드 변경 후 저장하면 자동으로 함수 레벨 인젝션 적용**

#### 제한사항

-   함수 본문만 변경 가능
-   프로퍼티 추가/삭제 불가
-   메서드 시그니처 변경 불가
