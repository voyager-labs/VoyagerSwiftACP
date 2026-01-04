# VOY-111 Run User Onboarding 계획

## 목표

- 앱 실행 시 온보딩 필요 여부를 판정하고 세션을 생성/재개한다.
- 스텝 기반 온보딩을 표시하고 진행/완료 처리한다.
- 완료 시 파일 관리자 창으로 전환한다.

## 대상 범위 (macOS 앱)

- 대상 앱: `apps/macos/Voyager`

## 예상 변경/추가 경로

- `apps/macos/Voyager/Voyager/App/AppDelegate.swift`
- `apps/macos/Voyager/Voyager/App/OnboardingWindowController.swift` (new)
- `apps/macos/Voyager/Voyager/Onboarding/OnboardingFeature.swift` (new)
- `apps/macos/Voyager/Voyager/Onboarding/Views` (new)
- `apps/macos/Voyager/Voyager/Settings/SettingsKeys.swift`
- `apps/macos/Voyager/VoyagerTests` (필요 시 추가)

## 단계별 계획

1. [ ] 온보딩 윈도우 스켈레톤 추가: NSWindow + SwiftUI root view 연결, AppDelegate에서 온보딩/파일 관리자 분기.
2. [ ] 온보딩 도메인 모델 설계(TCA): `@Reducer`/`@ObservableState` 기반으로 `OnboardingFeature`(root) + Step Feature들을 `Scope`로 합성, 스텝 모델/진행률/앞뒤 이동 규칙 정의.
3. [ ] 세션 저장/재개 로직: UserDefaults 기반 저장(완료 플래그/버전/진행 상태), 재온보딩 우선/버전 불일치 초기화/저장 실패 처리.
4. [ ] 온보딩 UI 구현: 스텝별 안내/입력 UI, 진행률 표시, Next/Back 활성화 조건, 입력 변경 시 상태 저장.
5. [ ] 완료 처리 + 전환: 완료 플래그 저장 후 파일 관리자 창 실행, 전환 실패 시 재시도/안내.
6. [ ] 엣지 케이스 보강: 저장 직전 종료 시 마지막 저장 상태 유지, 재개 실패 시 초기화.
7. [ ] 검증: TCA `TestStore` 유닛 테스트(세션/리듀서), 수동 QA(새 설치/재실행/중단 후 재개/완료 후 전환).

## 검증 커맨드

- `xcodebuild -project apps/macos/Voyager/Voyager.xcodeproj -scheme Voyager-Dev -configuration Debug`
- `xcodebuild test -scheme Voyager-Dev -project apps/macos/Voyager/Voyager.xcodeproj`
