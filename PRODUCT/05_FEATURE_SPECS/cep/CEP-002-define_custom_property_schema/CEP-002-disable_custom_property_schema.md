# Disable Custom Property Schema

## Metadata

| Field            | Value                                                                                                     |
| ---------------- | --------------------------------------------------------------------------------------------------------- |
| Interaction ID   | CEP-002-disable_custom_property_schema                                                                    |
| Interaction Type | command                                                                                                   |
| Feature          | Define Custom Property Schema                                                                             |
| Category Key     | CEP                                                                                                       |
| Feature ID       | CEP-002                                                                                                   |
| Status           | 아이디어                                                                                                  |
| Summary          | <<AI>> 더 이상 사용하지 않을 사용자 프로퍼티 스키마를 비활성화해 신규 편집 UI에서 선택되지 않도록 숨긴다. |
| Related Region   | file_manager_window.inspector_pane.inspector_mode_property                                                |
| Menu             | <<AI>> Edit                                                                                               |
| Shortcut         | -                                                                                                         |

## Preconditions

- <<AI>> 비활성화할 프로퍼티 스키마가 선택된 상태
- <<AI>> 대상 스키마가 활성 상태인 상태
- <<AI>> 프로퍼티 스키마를 편집할 권한을 보유한 상태

## Edge Cases

- <<AI>> 대상 스키마가 다른 스키마·Computed Property의 참조 대상으로 고정되어 있는 경우
- <<AI>> 대상 스키마가 이미 비활성 상태인 경우
- <<AI>> 비활성화 직후에도 신규 추가 UI에 캐시로 노출되는 경우

## Acceptance Criteria

- [ ] <<AI>> 대상 스키마가 활성 상태일 때, 사용자가 비활성화를 실행하면, 스키마 상태를 비활성으로
      변경하고 스키마 목록에 해당 상태를 표시함.
- [ ] <<AI>> 스키마가 비활성 상태일 때, 사용자가 엔트리 프로퍼티 추가 UI를 열면, 해당 스키마를 선택
      옵션에 노출하지 않도록 함.
- [ ] <<AI>> 비활성 스키마를 이미 사용 중인 엔트리를 조회할 때, 시스템이 값을 표시하면, 기존 값은
      유지하며 스키마가 비활성 상태임을 함께 표시함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `181`
