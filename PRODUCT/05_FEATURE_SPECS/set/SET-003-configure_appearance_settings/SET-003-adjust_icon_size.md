---
interaction_id: "SET-003-adjust_icon_size"
interaction_type: "input"
feature: "Configure Appearance Settings"
category_key: "SET"
feature_id: "SET-003"
status: "배포 완료"
summary: "Entries View(리스트/그리드)의 아이콘 크기 설정을 변경하고, 열려 있는 창의 뷰에 즉시 반영"
related_region: "settings_window.settings_body.tab_appearance"
menu: "-"
shortcut: "-"
---

# Adjust Icon Size

## Intent

- 사용자가 Entries View의 정보 밀도와 시각적 선호에 맞게 아이콘(썸네일) 크기를 조절할 수 있어야 한다.
- 설정 변경이 열려 있는 File Manager 창의 List View와 Icon View에 즉시 전파되어 재렌더링되어야 한다.

## Trigger / Entry Points

- Settings의 Appearance 탭에서 Icon Size 컨트롤을 조절

## Preconditions

- Settings Window의 Appearance 탭이 열려 있는 상태

## Expected Outcome

- 사용자가 Icon Size 값을 변경하면, Entries View의 아이콘(썸네일) 크기가 즉시 갱신된다.
- List View와 Icon View는 각 뷰의 아이콘 크기 설정값을 독립적으로 사용한다.
- 열려 있는 File Manager 창에 표시 중인 List View와 Icon View가 즉시 다시 렌더링되어 변경된 아이콘 크기를 반영한다.

## State Changes

- AppPreferences에 아이콘 크기 설정값이 저장된다.
- 설정 변경은 AppPreferences에서 WindowManager로 전파되고, FileManagerWindowPreferencesReducer를 통해 각 창의 EntryViewLayout에 반영되어 뷰가 다시 렌더링된다.

## User-visible Feedback

- Settings에서 컨트롤을 조절하는 즉시, 열려 있는 File Manager 창의 Entries View 아이콘 크기가 실시간으로 변한다.

## Edge Cases / Failure Handling

- 열려 있는 File Manager 창이 없는 경우에도, 설정값은 저장되고 이후 열리는 창에 적용된다.
- 값이 허용 범위를 벗어난 경우, 시스템이 유효 범위로 보정해 적용한다.

## Acceptance Criteria

- [ ] Settings의 Appearance 탭이 열려 있는 상황에서, 사용자가 Icon Size 값을 변경하면, AppPreferences의 설정값이 갱신되어야 한다.
- [ ] File Manager 창에 List View 또는 Icon View가 열려 있는 상황에서, 사용자가 Icon Size 값을 변경하면, 열려 있는 뷰가 즉시 다시 렌더링되어 변경된 아이콘 크기를 반영해야 한다.
- [ ] List View와 Icon View가 모두 존재하는 상황에서, 각 뷰는 자신의 아이콘 크기 설정값을 사용해 렌더링되어야 한다.

## Permissions / Dependencies

- AppPreferences에 설정을 저장할 수 있어야 한다.
- 열려 있는 File Manager 창이 설정 변경 전파를 수신할 수 있어야 한다.

## Observability / Analytics

- Appearance 설정 변경(Icon Size)
- 열린 창에 대한 재렌더링 발생 여부

## Related Interactions

- `SET-003-adjust_text_size`
- `EVM-002-set_entries_view_as_list_table`
- `EVM-002-set_entries_view_as_icon_grid`

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `251`
