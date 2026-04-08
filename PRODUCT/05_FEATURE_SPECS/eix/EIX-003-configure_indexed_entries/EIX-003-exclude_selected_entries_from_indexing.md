# Exclude Selected Entries from Indexing

## Metadata

| Field            | Value                                                                                                                         |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Interaction ID   | EIX-003-exclude_selected_entries_from_indexing                                                                                |
| Interaction Type | command                                                                                                                       |
| Feature          | Configure Indexed Entries                                                                                                     |
| Category Key     | EIX                                                                                                                           |
| Feature ID       | EIX-003                                                                                                                       |
| Status           | 기획 완료                                                                                                                     |
| Summary          | 선택한 엔트리의 경로를 인덱싱 제외 규칙으로 추가할 수 있도록 제외 규칙 편집 화면을 열고, 선택 항목 기반 규칙 초안을 미리 채움 |
| Related Region   | -                                                                                                                             |
| Menu             | -                                                                                                                             |
| Shortcut         | -                                                                                                                             |

## Preconditions

- <<TEMP>>
- 하나 이상의 인덱싱된 엔트리가 선택된 상태

## Edge Cases

- 선택한 대상이 인덱싱 큐에 대기 중이거나 인덱싱 진행 중인 경우
- 선택한 대상의 경로를 제외 규칙 초안으로 생성할 수 없는 경우

## Acceptance Criteria

- [ ] 하나 이상의 인덱싱된 엔트리가 선택된 상태일 때, 사용자가 해당 인터랙션을 호출하면, 시스템이
      제외 규칙 편집 화면을 표시하고 선택 항목 기반 제외 규칙 초안을 미리 채움
- [ ] 선택한 대상이 인덱싱 큐에 대기 중이거나 인덱싱 진행 중인 경우일 때, 시스템이 제외 규칙 초안을
      생성해 표시하면, 진행 중인 인덱싱은 즉시 중단하지 않고 제외 규칙 저장 이후부터 적용되도록
      처리함
- [ ] 선택한 대상의 경로를 제외 규칙 초안으로 생성할 수 없는 경우일 때, 시스템이 편집 화면을
      표시하면, 규칙을 수동 입력할 수 있도록 상태로 표시함

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `84`
