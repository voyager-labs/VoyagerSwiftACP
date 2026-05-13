---
interaction_id: "EOP-004-rename_entry"
interaction_type: "command"
feature: "Edit Entry Metadata"
category_key: "EOP"
feature_id: "EOP-004"
status: "배포 완료"
summary: "선택한 Entry의 이름을 편집해 변경"
related_region: "file_manager_window.content_pane.page_container.page_mode_directory"
menu: "file_menu"
shortcut: "Enter"
---

# Rename Entry

## Intent

- 선택한 Entry의 이름, 태그, 권한, 정보 같은 시스템 프로퍼티를 다룬다.

## Trigger / Entry Points

- `file_menu` 메뉴의 Rename Entry 항목
- `Enter` 단축키
- file_manager_window.content_pane.page_container.page_mode_directory 영역에서 관련 컨트롤 또는 명령을 실행한 경우

## Preconditions

- 대상 Entry이 현재 File Manager Window에서 접근 가능한 상태다.

## Expected Outcome

- 선택한 Entry의 이름을 편집해 변경.
- 사용자에게 보이는 결과는 `rename_entry_applied` 상태로 정리된다.

## State Changes

- Entry의 표시 또는 실행 상태를 갱신한다.
- 이 인터랙션은 [eop_contract.toml](../contracts/eop_contract.toml)의 `rename_entry_applied` 상태 어휘를 따른다.

## User-visible Feedback

- 성공 시 현재 화면의 표시, 선택, 정렬, 실행 결과가 즉시 갱신된다.
- 실패 시 기존 상태를 보존하고 실패 사유를 사용자에게 표시한다.

## Edge Cases / Failure Handling

- 대상 Entry이 사라졌거나 권한이 없으면 작업을 중단한다.
- 동일 요청이 반복되면 마지막으로 확정된 상태를 기준으로 중복 반영을 피한다.

## Acceptance Criteria

- [ ] 대상 Entry이 현재 File Manager Window에서 접근 가능한 상태다. 사용자가 Rename Entry을 실행하면, 선택한 Entry의 이름을 편집해 변경 결과가 `rename_entry_applied` 상태로 반영되어야 한다.
- [ ] 작업을 완료할 수 없는 조건이면, 앱은 기존 상태를 보존하고 실패 피드백을 표시해야 한다.
- [ ] 같은 interaction이 반복 호출되어도 중복되거나 모순된 상태가 남지 않아야 한다.

## Permissions / Dependencies

- 현재 Page, selection, 파일 시스템 접근 권한, File Manager Window layout 상태에 의존한다.

## Observability / Analytics

- `eop.rename_entry` 이벤트에 성공 여부와 대상 수, 실패 사유를 기록한다.

## Related Interactions

- [EOP-004-batch_rename_entries](EOP-004-batch_rename_entries.md)
- [EOP-004-change_entry_permission_s](EOP-004-change_entry_permission_s.md)
- [EOP-004-edit_entry_ies_tags](EOP-004-edit_entry_ies_tags.md)
- [EOP-004-get_entry_info](EOP-004-get_entry_info.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:59`
- Flows: [eop_flow.md](../flows/eop_flow.md)
- Contract: [eop_contract.toml](../contracts/eop_contract.toml)
