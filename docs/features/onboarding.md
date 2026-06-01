# 온보딩

## 개요

온보딩은 앱 첫 실행(또는 온보딩 재진입) 시 사용자가 **기능 사용에 필요한 준비 상태**에 도달하도록 안내하는 흐름입니다.
Voyager는 온보딩을 여러 단계로 쪼개고, 진행 상황을 저장하여 앱을 종료했다가 다시 열어도 이어갈 수 있게 설계되어 있습니다.

## 사용자 흐름(단계)

온보딩은 다음 단계를 순서대로 진행합니다.

1. Welcome
2. Beta Access
3. Permissions
4. Complete

현재 단계 이동은 "다음"/"이전" 버튼으로 수행되며, "다음"은 **해당 단계가 완료된 상태일 때만** 활성화됩니다.

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/Onboarding/Reducer/OnboardingFeature.swift`

## 진행 상태 저장(복원)

온보딩은 각 단계의 완료 여부와 현재 단계를 스냅샷으로 저장합니다.

- 앱 시작 시 `onAppear`에서 스냅샷을 로드하고, 저장된 상태가 유효하지 않으면 안전한 단계로 되돌립니다.
- 단계 내부 액션이 발생할 때마다 스냅샷을 저장합니다(중간 이탈/재실행 대비).

핵심 포인트

- `State.progressSnapshot`: 현재 단계 + 각 단계 완료 상태를 스냅샷으로 구성
- `State.lastValidStep(from:)`: 저장된 currentStep이 완료되지 않은 단계라면, 완료된 가장 최근 단계로 되돌림

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/Onboarding/Reducer/OnboardingFeature.swift`

## 단계별 동작 상세

### 1) Welcome

- 안내 화면 역할
- 현재 구현에서는 기본적으로 완료 상태(`isComplete = true`)로 시작합니다.

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/Onboarding/Reducer/WelcomeFeature.swift`

### 2) Beta Access

- 이메일/토큰을 입력받아 베타 접근 권한을 검증합니다.
- 검증 중에는 중복 요청을 막고(`cancelInFlight`), 실패 사유를 상태에 반영합니다.

상태/액션 요약

- 입력: `email`, `token`
- 결과: `status`, `reason`, `isComplete`
- 동작: `checkTapped`/`retryTapped` → `betaAccessClient.verify(email, token)`

관련 코드

- `apps/macos/Voyager/Voyager/04_Features/BetaAccess/Reducer/BetaAccessFeature.swift`

### 3) Permissions

권한 단계는 "다음"으로 넘어가기 위한 필수 조건을 준비합니다.

주요 항목

- Full Disk Access 상태 확인/유도
- (선택) 로그인 시 실행(Launch at Login) 설정 (필수 아님)

완료 조건

- `fullDiskAccessStatus == .granted` 일 때 단계가 완료로 간주됩니다.

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/Onboarding/Reducer/PermissionsFeature.swift`

### 4) Complete

마지막 단계에서는 실제 사용 화면으로 전환합니다.

- "Start Using"(또는 재시도) 버튼을 누르면 파일 매니저 윈도우를 열고
- 성공 시 온보딩 윈도우를 닫습니다.

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/Onboarding/Reducer/CompleteFeature.swift`
- `apps/macos/Voyager/Voyager/02_Pages/Onboarding/Reducer/OnboardingFeature.swift`

## 의존성/통합 포인트

온보딩은 TCA Dependency를 통해 외부 시스템과 통합합니다.

- `onboardingProgressStore`: 온보딩 진행 스냅샷 저장/로드
- `fileManagerWindowClient`: 메인 파일 매니저 윈도우 오픈
- `onboardingWindowClient`: 온보딩 윈도우 닫기
- `betaAccessClient`: 베타 권한 검증
- `fullDiskAccessClient`, `systemSettingsClient`: 권한 확인/요청/설정 열기

## QA 체크리스트

- 앱을 온보딩 중간에 종료했다가 다시 열면, 진행 상황이 정상적으로 복원되는가
- 권한이 이미 부여된 상태에서 온보딩에 진입하면, Permissions 단계가 즉시 완료로 반영되는가
- Full Disk Access 설정 화면을 열지 못했을 때 사용자에게 안내가 표시되는가
- Complete에서 파일 매니저 윈도우 오픈 실패 시 재시도 UX가 동작하는가

## 트러블슈팅

- Permissions 단계에서 "다음"이 비활성화됨
  - Full Disk Access가 `granted`인지 확인합니다(시스템 설정에서 토글 필요).
- 온보딩이 계속 처음으로 돌아감
  - 진행 상태 저장이 reset 되는 케이스인지 확인합니다(`onboardingProgressStore.load()`의 `resetRequired`).
