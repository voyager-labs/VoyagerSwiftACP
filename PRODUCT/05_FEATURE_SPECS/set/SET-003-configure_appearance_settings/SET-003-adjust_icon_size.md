---
interaction_id: "SET-003-adjust_icon_size"
interaction_type: "input"
feature: "Configure Appearance Settings"
category_key: "SET"
feature_id: "SET-003"
status: "배포 완료"
summary: "Entries View의 list/grid 아이콘 크기 설정을 변경하고 UserDefaults에 저장한다."
related_region: "settings_window.settings_body.tab_appearance"
menu: "-"
shortcut: "-"
---

# Adjust Icon Size

## Intent

- Entries View의 아이콘 크기 설정을 변경하고, 열려 있는 창의 뷰에 즉시 반영.
- `SET-003`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- Appearance tab이 로드되거나 사용자가 theme, icon size, text size, hidden-files 표시를 변경할 때 호출된다.

## Preconditions

- Appearance settings state가 로드되어 테마와 Entries View 표시 설정을 읽고 쓸 수 있어야 한다.

## Expected Outcome

- Entries View의 list/grid 아이콘 크기 설정을 변경하고 UserDefaults에 저장한다.
- theme은 AppearanceSettingsClient에서 로드하고 변경 시 즉시 applyTheme으로 적용해야 한다.
- list/grid icon size와 text size는 각각 UserDefaults key에 저장되어 다음 실행과 열린 Entries View에서 재사용되어야 한다.
- showHiddenFiles 값은 UserDefaults에 저장되어 Entry View 표시 정책에 반영되어야 한다.

## State Changes

- theme, listIconSize, gridIconSize, listTextSize, gridTextSize, showHiddenFiles 값을 갱신한다.
- theme 변경은 저장과 동시에 시스템 appearance 적용 side effect를 실행한다.
- size 변경은 설정 state와 UserDefaults를 동기화한다.

## User-visible Feedback

- Appearance form의 segmented control, slider, toggle 값이 즉시 변경된다.
- theme 변경은 앱 appearance에 즉시 반영된다.
- Entry View 표시 크기 변경은 관련 view state가 preferences를 다시 읽을 때 반영된다.

## Edge Cases / Failure Handling

- 저장된 size 값이 없으면 AppearanceSettingsDefaults 값을 유지한다.
- theme raw value가 유효하지 않으면 기본 theme으로 복구되어야 한다.
- size 값은 UI control이 허용하는 범위 안에서만 저장되어야 한다.
- 입력이 유효하지 않으면 저장/적용을 실행하지 않고 수정 가능한 오류 상태를 유지한다.

## Acceptance Criteria

- [ ] Appearance tab을 열면 저장된 theme과 size 값이 form에 복원되어야 한다.
- [ ] theme을 변경하면 UserDefaults 저장과 applyTheme 호출이 함께 일어나야 한다.
- [ ] list text size를 변경하면 `SettingsKeys.listTextSize`에 새 값이 저장되어야 한다.
- [ ] hidden files 토글을 변경하면 `SettingsKeys.showHiddenFiles`가 갱신되어야 한다.

## Permissions / Dependencies

- Appearance settings state가 로드되어 테마와 Entries View 표시 설정을 읽고 쓸 수 있어야 한다.
- 관련 UI region: `settings_window.settings_body.tab_appearance`

## Observability / Analytics

- setting load/save 이벤트
- UserDefaults key 변경
- 시스템 dependency 실패 reason

## Related Interactions

- [SET-003-swtich_theme_mode](SET-003-swtich_theme_mode.md)
- [SET-003-adjust_text_size](SET-003-adjust_text_size.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:245`
- Flows: [settings_appearance_flow.md](../flows/settings_appearance_flow.md)
- Implementation references: `../voyager-app/apps/macos/Packages/02_Pages/Settings/Sources/VoyagerPagesSettings/Reducer/SettingsFeature.swift`, `../voyager-app/apps/macos/Packages/02_Pages/Settings/Sources/VoyagerPagesSettings/Reducer/GeneralSettingsFeature.swift`, `../voyager-app/apps/macos/Packages/02_Pages/Settings/Sources/VoyagerPagesSettings/Reducer/AppearanceSettingsFeature.swift`
