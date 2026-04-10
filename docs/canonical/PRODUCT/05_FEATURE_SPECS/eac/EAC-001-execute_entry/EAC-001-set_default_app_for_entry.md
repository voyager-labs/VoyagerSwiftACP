---
interaction_id: "EAC-001-set_default_app_for_entry"
interaction_type: "command"
feature: "Execute Entry"
category_key: "EAC"
feature_id: "EAC-001"
status: "배포 완료"
summary: "선택한 Entry의 파일 유형에 대해 기본 실행 앱을 설정"
related_region: "file_manager_window.content_pane.page_container.page_mode_directory"
menu: "File"
shortcut: "-"
---

# Set Default App for Entry

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- <<AI>> 하나 이상의 Entry가 선택된 상태
- <<AI>> 기본 실행 앱으로 설정할 앱이 지정된 상태

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- <<AI>> 선택된 Entry가 폴더이거나 파일 유형(UTType)을 확정할 수 없는 경우
- <<AI>> 선택된 Entry가 여러 파일 유형으로 섞여 단일 기본 앱 설정이 모호한 경우
- <<AI>> 시스템 정책/권한 문제로 기본 앱 변경을 적용할 수 없는 경우

## Acceptance Criteria

- [ ] <<AI>> 기본 앱을 설정 가능한 파일이 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면,
      선택된 Entry의 파일 유형에 대해 지정한 앱을 기본 실행 앱으로 설정함.
- [ ] <<AI>> 여러 파일 유형이 섞여 있는 상태일 때, 사용자가 해당 인터랙션을 호출하면, 기본 앱 변경을
      수행하지 않고 적용 불가 사유를 사용자에게 안내함.
- [ ] <<AI>> 기본 앱 변경이 완료된 상태일 때, 사용자가 Open Entry with Default App을 호출하면,
      변경된 기본 앱으로 실행되도록 함.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `41`
