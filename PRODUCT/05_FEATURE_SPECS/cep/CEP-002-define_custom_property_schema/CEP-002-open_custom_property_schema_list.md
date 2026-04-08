# Open Custom Property Schema List

## Metadata

| Field            | Value                                                                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------------------ |
| Interaction ID   | CEP-002-open_custom_property_schema_list                                                                           |
| Interaction Type | command                                                                                                            |
| Feature          | Define Custom Property Schema                                                                                      |
| Category Key     | CEP                                                                                                                |
| Feature ID       | CEP-002                                                                                                            |
| Status           | 아이디어                                                                                                           |
| Summary          | <<AI>> 워크스페이스에 정의된 모든 사용자 프로퍼티 스키마를 리스트로 불러와 조회·검색·필터링할 수 있는 화면을 연다. |
| Related Region   | file_manager_window.inspector_pane.inspector_mode_property                                                         |
| Menu             | <<AI>> View                                                                                                        |
| Shortcut         | -                                                                                                                  |

## Preconditions

- <<AI>> 워크스페이스가 로드된 상태
- <<AI>> 프로퍼티 스키마를 조회할 권한을 보유한 상태

## Edge Cases

- <<AI>> 워크스페이스에 스키마가 하나도 존재하지 않는 경우
- <<AI>> 스키마 목록 로딩에 실패하는 경우
- <<AI>> 검색·필터 조건으로 결과가 0건인 경우

## Acceptance Criteria

- [ ] <<AI>> 사용자가 해당 인터랙션을 호출할 때, 시스템이 스키마 목록을 로드하면, 스키마 리스트
      화면을 열고 검색·필터링이 가능한 상태로 전환함.
- [ ] <<AI>> 스키마가 없는 상태일 때, 화면을 열면, 빈 상태와 스키마 생성 CTA를 표시함.
- [ ] <<AI>> 스키마 로딩이 실패한 상태일 때, 화면이 표시되면, 오류 메시지와 재시도 동작을 표시함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `178`
