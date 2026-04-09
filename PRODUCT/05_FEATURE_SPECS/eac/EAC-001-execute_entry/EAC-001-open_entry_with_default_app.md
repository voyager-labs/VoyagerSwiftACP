---
interaction_id: "EAC-001-open_entry_with_default_app"
interaction_type: "command"
feature: "Execute Entry"
category_key: "EAC"
feature_id: "EAC-001"
status: "배포 완료"
summary: "해당 Entry를 기본 앱으로 실행"
related_region: "file_manager_window.content_pane.page_container.page_mode_directory"
menu: "File"
shortcut: "⌘▼"
---

# Open Entry with Default App

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
- <<AI>> 선택한 Entry에 대해 현재 사용자에게 최소 읽기 권한이 있는 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 선택된 Entry가 파일 시스템 상에서 더 이상 존재하지 않는 경우
- <<AI>> 선택된 Entry에 기본 앱 매핑이 없거나 시스템이 해석할 수 없는 경우
- <<AI>> 클라우드/네트워크 스토리지 지연으로 Entry가 로컬에 아직 준비되지 않은 경우
- <<AI>> 선택된 Entry 수가 많아 일괄 실행 전에 사용자 확인이 필요한 경우

## Acceptance Criteria

- [ ] <<AI>> 하나 이상의 Entry가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 선택한
      Entry들을 시스템 기본 앱으로 실행함.
- [ ] <<AI>> 일부 Entry가 실행 불가한 상태일 때, 사용자가 해당 인터랙션을 호출하면, 실행 가능한
      Entry만 실행하고 실패 대상과 사유를 사용자에게 안내함.
- [ ] <<AI>> Entry가 선택되지 않은 상태일 때, 사용자가 해당 인터랙션을 호출하면, 아무 변화도
      발생하지 않도록 함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `39`
