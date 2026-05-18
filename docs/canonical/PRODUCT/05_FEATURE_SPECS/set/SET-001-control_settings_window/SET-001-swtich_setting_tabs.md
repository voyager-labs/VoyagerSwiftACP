---
interaction_id: "SET-001-swtich_setting_tabs"
interaction_type: "command"
feature: "Control Settings Window"
category_key: "SET"
feature_id: "SET-001"
status: "배포 완료"
summary: "세팅 탭 전환"
related_region: "settings_window.toolbar.tabs_area"
menu: "-"
shortcut: "-"
---

# Switch Setting Tabs

## Intent

- 세팅 탭 전환.
- `SET-001`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- 사용자가 Voyager menu 또는 단축키로 Settings window를 열거나 닫을 때 호출된다.
- Settings sidebar/toolbar에서 General 또는 Appearance section을 선택할 때 호출된다.

## Preconditions

- SettingsFeature state가 준비되어 있고 Settings window를 열거나 닫을 수 있어야 한다.

## Expected Outcome

- 세팅 탭 전환.
- Settings onAppear 시 General settings와 Appearance settings를 함께 로드해야 한다.
- section 전환은 selectedSection만 갱신하고 각 section의 저장된 값을 임의로 초기화하지 않아야 한다.
- 닫기 명령은 현재 key window를 닫는 창 제어로 처리된다.

## State Changes

- selectedSection을 General 또는 Appearance로 갱신한다.
- onAppear는 GeneralSettingsFeature.loadSettings와 AppearanceSettingsFeature.loadSettings를 dispatch한다.
- closeWindow는 앱 전역 상태를 변경하지 않고 window close side effect만 수행한다.

## User-visible Feedback

- 선택된 section의 title과 form content가 즉시 바뀐다.
- 창 닫기는 별도 확인 없이 현재 Settings window를 닫는다.

## Edge Cases / Failure Handling

- Settings 창이 이미 열려 있으면 새 상태를 중복 생성하지 않고 기존 창 surface에서 focus/표시를 유지한다.
- section 전환 중 child settings 로드가 끝나지 않아도 기존 저장값은 유지되어야 한다.
- 명령 실행 중 실패하면 대상 상태를 부분 적용된 것처럼 표시하지 않는다.

## Acceptance Criteria

- [ ] Settings를 열면 General과 Appearance 설정값 로드가 시작되어야 한다.
- [ ] Appearance section을 선택하면 selectedSection이 appearance로 바뀌고 Appearance form이 표시되어야 한다.
- [ ] 닫기 명령을 실행하면 현재 Settings window가 닫혀야 한다.

## Permissions / Dependencies

- SettingsFeature state가 준비되어 있고 Settings window를 열거나 닫을 수 있어야 한다.
- 관련 UI region: `settings_window.toolbar.tabs_area`

## Observability / Analytics

- setting load/save 이벤트
- UserDefaults key 변경
- 시스템 dependency 실패 reason

## Related Interactions

- [SET-001-open_settings_window](SET-001-open_settings_window.md)
- [SET-001-close_settings_window](SET-001-close_settings_window.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:229`
- Flows: [settings_window_flow.md](../flows/settings_window_flow.md)
- Implementation references: `../voyager-app/apps/macos/Packages/02_Pages/Settings/Sources/VoyagerPagesSettings/Reducer/SettingsFeature.swift`, `../voyager-app/apps/macos/Packages/02_Pages/Settings/Sources/VoyagerPagesSettings/Reducer/GeneralSettingsFeature.swift`, `../voyager-app/apps/macos/Packages/02_Pages/Settings/Sources/VoyagerPagesSettings/Reducer/AppearanceSettingsFeature.swift`
