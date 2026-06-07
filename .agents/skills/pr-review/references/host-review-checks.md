# Host and Fixture Review Checks

> Procedural checks for PRs that modify Host apps, fixture entry points, smoke
> harnesses, or Xcode project configuration. Loaded by pr-review SKILL.md when
> the diff touches `apps/macos/Hosts/**`, host `.xcodeproj`, `*Host*Fixture*`,
> or `*Preview*`.

---

## Host and Fixture Public API Surface

**대상:** PR이 Host 앱, fixture entry point, smoke harness, package-public
test/preview support를 추가하는 경우.

**체크:**

1. 변경된 package 파일에서 새로 `public`이 된 symbol 식별
2. 각 symbol 분류:
    - Stable product API — 다른 패키지에서도 재사용 가능
    - Host-only API — 특정 Host target만을 위한 진입점
    - Preview/test support — 개발/테스트 전용
    - Compatibility wrapper — 임시 래퍼
3. Host-only API가 상위 layer app type을 import/노출하지 않는지 확인
4. 네이밍/배치가 boundary를 명확히 하는지:
    - `*Host*` 접미사가 Host-specific 파일에 적용됨
    - `*Fixture*` 접미사가 fixture 파일에 적용됨
    - `Api/` segment에 공개 entry point가 위치함
5. `public`이 Host target만을 위한 것이라면, package에 기존
   convention이 있는지 확인

**Finding 기준:**

- **P1:** public API가 ownership drift를 숨기거나 app-only assumption을
  노출하거나 temporary wrapper를 안정적으로 보이게 만드는 경우
- **Non-blocking observation:** 그 외, 명시적으로 확인만 기록

```bash
# 새로 public이 된 symbol 찾기
grep -nE 'public\s+(struct|class|enum|protocol|func|var|let)' <changed-file>
# 상위 layer import 확인
grep -nE 'import.*01_App|import.*02_Pages|import.*03_Widgets|import.*04_Features' <changed-file>
```

---

## Xcode Host Project Drift

**대상:** PR이 `apps/macos/Hosts/**.xcodeproj/**`, `*.xcscheme`,
`*.xcworkspace/contents.xcworkspacedata`, `Package.resolved`를 변경하는 경우.

**체크:**

1. Host project build settings을 기존 Host projects와 비교:
    - `MACOSX_DEPLOYMENT_TARGET`
    - `SWIFT_VERSION`
    - `APP_ENV` (Debug vs Release)
    - Code signing entitlements
    - Bundle ID pattern (`fm.voyager.*` convention)
    - `LSApplicationCategoryType`
2. Scheme launch/test/archive 동작을 기존 Host schemes와 비교
3. Workspace references가 의도된 project path를 가리키는지 확인
4. `Package.resolved` pins을 인접 Host projects 또는 main workspace와 비교
5. Resource references가 안정적인 relative paths를 사용하고 target
   resources에 포함되는지 확인

**Finding 기준:**

- **P0/P1:** Secret exposure 또는 release/debug environment mismatch
- **P1:** Dependency pin drift가 runtime/build 동작을 구체적으로 변경할
  수 있는 경우
- **Non-blocking:** 그 외, risk 또는 verification caveat로 기록

```bash
# Build settings 비교
xcodebuild -project <Host.xcodeproj> -showBuildSettings | grep -E 'MACOSX_DEPLOYMENT_TARGET|SWIFT_VERSION|APP_ENV|PRODUCT_BUNDLE_IDENTIFIER'
# Package.resolved 비교
diff <(plutil -convert json -o - HostA/Package.resolved) <(plutil -convert json -o - HostB/Package.resolved)
```

---

## UI Host Runtime Evidence Notes

**대상:** Host/UI smoke harness review.

**가이드:**

1. Structural review는 owner/lifecycle/fixture boundary를 확인
2. Runtime review는 `verification` 스킬, Xcode build/run, 또는 manual
   QA에 위임
3. Runtime evidence를 재실행하지 않은 경우 confidence를 "structural
   only"로 표시
4. AppKit/SwiftUI Host의 경우 명시적으로 확인 여부 기록:
    - Strong window controller retention
    - Launch timing (app lifecycle entry)
    - Last-window termination behavior
    - Smoke env gating (APP_ENV 기반)
    - Resource bundling (assets, localized strings)

**Finding 기준:**

- **P1:** Window controller가 강한 참조로 유지되지 않아 조기
  deallocation 가능성
- **Non-blocking:** 그 외 runtime 동작은 structural review에서 파악
  불가하므로 명시적으로 "runtime evidence needed" 표시

```bash
# Window controller retention 확인
grep -nE 'NSWindowController|NSWindow|\.window' <HostAppDelegate>
# Lifecycle 확인
grep -nE 'applicationDidFinishLaunching|applicationWillTerminate|applicationShouldTerminateAfterLastWindowClosed' <HostAppDelegate>
# APP_ENV 확인
grep -rnE 'APP_ENV' <HostProject>/xcshareddata/ <HostProject>/Configs/
```
