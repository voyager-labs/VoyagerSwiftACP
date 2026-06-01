# 설정

## 개요

설정(Settings)은 앱 전반의 "사용자 취향"과 "동작 기본값"을 관리합니다.
Voyager는 설정을 TCA 하위 Feature로 분리해 유지보수성을 높이고,
대부분의 값은 `UserDefaults`에 저장하여 앱 재시작 후에도 유지합니다.

이 문서의 목표

- 어떤 설정이 존재하는지(섹션/항목)
- 값이 어디에 저장되는지(UserDefaults key)
- 설정 변경이 앱에 어떻게 반영되는지(즉시 적용 vs 재시작 필요)

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/Settings/Reducer/SettingsFeature.swift`
- `apps/macos/Voyager/Voyager/02_Pages/Settings/Reducer/GeneralSettingsFeature.swift`
- `apps/macos/Voyager/Voyager/02_Pages/Settings/Reducer/AppearanceSettingsFeature.swift`
- `apps/macos/Voyager/Voyager/05_Entities/Settings/Config/SettingsKeys.swift`

---

## 1) 구조(섹션/하위 Feature)

Settings는 "섹션 선택" + "섹션별 설정 화면" 형태로 구성됩니다.

- `SettingsFeature.State.selectedSection`: 현재 선택된 섹션
- 화면 진입 시 `.onAppear`에서 각 섹션의 `loadSettings`를 호출하여 저장값을 로드

현재 섹션

- General
- Appearance

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/Settings/Reducer/SettingsFeature.swift`

---

## 2) 저장 키(UserDefaults)

설정 키는 `SettingsKeys`에 정의되어 있습니다.

- `defaultTabPath`: 파일 매니저의 기본 시작 경로
- `onboardingCompleted`: 온보딩 완료 여부
- `launchAtStartup`: 로그인 시 실행 토글
- `SUAutomaticallyUpdate`: 자동 업데이트(자동 다운로드) 토글
- `alertBeforeQuit`: 종료 전 확인(alert) 토글
- `theme`: 앱 테마
- `listIconSize`, `gridIconSize`: 아이콘 크기
- `listTextSize`, `gridTextSize`: 텍스트 크기
- `showHiddenFiles`: 숨김 파일 표시
- `lastCollectionSaveDirectory`: 컬렉션 저장 대화상자의 마지막 디렉터리

관련 코드

- `apps/macos/Voyager/Voyager/05_Entities/Settings/Config/SettingsKeys.swift`

---

## 3) General 설정

General 섹션은 앱의 기본 동작을 바꾸는 항목들을 포함합니다.

### 3.1 Starting Directory (defaultTabPath)

파일 매니저 창을 열 때 기본 탭 경로로 사용합니다.

- 저장 키: `SettingsKeys.defaultTabPath`
- 기본값: 홈 디렉터리

UI 동작

- 표준 옵션(Home/Root/Desktop/Documents/Downloads) 제공
- 기타 경로는 디렉터리 선택 패널을 통해 설정
- 유효하지 않은 경로/디렉터리를 선택하면 에러 메시지 표시

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/Settings/Reducer/GeneralSettingsFeature.swift`
- `apps/macos/Voyager/Voyager/02_Pages/Settings/Reducer/SettingsFeature.swift` (getDefaultTabPath)

### 3.2 Launch at Startup

로그인 시 앱을 자동 실행합니다.

- 저장 키: `SettingsKeys.launchAtStartup`
- 구현: `ServiceManagement`의 `SMAppService.mainApp` 사용

중요 포인트

- 저장된 값과 실제 시스템 등록 상태가 다를 수 있습니다.
  - `loadSettings`에서 실제 `SMAppService` 상태를 읽고, 저장값과 다르면 저장값을 교정합니다.

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/Settings/Reducer/GeneralSettingsFeature.swift`

### 3.3 Automatic Update (Sparkle)

자동 업데이트는 "자동으로 다운로드" 여부를 의미합니다.

- 저장 키: `SettingsKeys.automaticUpdate` (`SUAutomaticallyUpdate`)
- 적용 대상: Sparkle `automaticallyDownloadsUpdates`

동작

- Settings에서 토글 변경 → `UpdaterClient.setAutomaticUpdate(enabled)` 호출
- Updater는 configure 시점에도 UserDefaults 값을 읽어 초기화합니다.

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/Settings/Reducer/GeneralSettingsFeature.swift`
- `apps/macos/Voyager/Voyager/04_Features/UpdateVersion/Api/UpdaterClient.swift`

### 3.4 Alert Before Quit

앱 종료 시 확인(alert)을 표시할지 여부입니다.

- 저장 키: `SettingsKeys.alertBeforeQuit`

관련 코드

- `apps/macos/Voyager/Voyager/01_App/Lib/AppDelegate.swift`
- `apps/macos/Voyager/Voyager/02_Pages/Settings/Reducer/GeneralSettingsFeature.swift`

---

## 4) Appearance 설정

Appearance는 "보기" 관련 옵션을 다룹니다.

### 4.1 Theme

- 저장 키: `SettingsKeys.theme`
- 값: `AppTheme` (`light`, `dark`, `system`)

테마 적용

- 저장 후 `AppearanceSettingsClient.applyTheme(...)`로 즉시 반영

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/Settings/Reducer/AppearanceSettingsFeature.swift`
- `apps/macos/Voyager/Voyager/05_Entities/Settings/Api/AppearanceSettingsClient.swift`

### 4.2 List/Grid UI Size

파일 리스트/그리드의 아이콘/텍스트 크기를 조절합니다.

- `listIconSize`, `gridIconSize`
- `listTextSize`, `gridTextSize`

반영 지점

- 파일 매니저 UI가 UserDefaults 값을 읽어 렌더링에 반영합니다.

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/FileManager/Reducer/FileManagerFeature.swift`

### 4.3 Show Hidden Files

숨김 파일 표시 여부입니다.

- 저장 키: `SettingsKeys.showHiddenFiles`
- 반영 지점: FileManager 목록 로딩/필터

관련 코드

- `apps/macos/Voyager/Voyager/02_Pages/Settings/Reducer/AppearanceSettingsFeature.swift`
- `apps/macos/Voyager/Voyager/02_Pages/FileManager/Reducer/FileManagerFeature.swift`

---

## QA 체크리스트

- 설정 창 진입 시 기존 저장값이 UI에 반영되는가
- Starting Directory 변경이 다음 파일 매니저 오픈에 반영되는가
- Launch at Startup 토글이 실제 시스템 상태와 일치하는가(재진입 시 교정 동작)
- 테마 변경이 즉시 적용되는가
- 아이콘/텍스트 크기 변경이 리스트/그리드에 반영되는가
- `showHiddenFiles` 토글이 파일 목록 표시 로직에 반영되는가
- 자동 업데이트 토글이 Sparkle에 반영되는가
