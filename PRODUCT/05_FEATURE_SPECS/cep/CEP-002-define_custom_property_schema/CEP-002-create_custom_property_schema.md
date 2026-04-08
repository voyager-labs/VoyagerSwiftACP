# Create Custom Property Schema

## Metadata

| Field            | Value                                                                                             |
| ---------------- | ------------------------------------------------------------------------------------------------- |
| Interaction ID   | CEP-002-create_custom_property_schema                                                             |
| Interaction Type | command                                                                                           |
| Feature          | Define Custom Property Schema                                                                     |
| Category Key     | CEP                                                                                               |
| Feature ID       | CEP-002                                                                                           |
| Status           | 아이디어                                                                                          |
| Summary          | <<AI>> 새 사용자 정의 프로퍼티 스키마를 생성하고 이름, 키, 타입, 기본값, 표시 옵션 등을 설정한다. |
| Related Region   | file_manager_window.inspector_pane.inspector_mode_property                                        |
| Menu             | <<AI>> Edit                                                                                       |
| Shortcut         | -                                                                                                 |

## Preconditions

- <<AI>> 프로퍼티 스키마 생성 플로우를 시작할 수 있는 화면이 열린 상태
- <<AI>> 프로퍼티 스키마를 생성할 권한을 보유한 상태

## Edge Cases

- <<AI>> 입력한 스키마 키가 기존 스키마와 중복되는 경우
- <<AI>> 입력한 키·이름이 비어있거나 허용되지 않은 문자·형식을 포함하는 경우
- <<AI>> 선택한 타입과 기본값·옵션 값이 호환되지 않는 경우
- <<AI>> 필수 여부·옵션 제약 설정이 기존 데이터와 충돌하는 경우
- <<AI>> 저장 과정에서 스키마 저장이 실패하는 경우
- <<AI>> 인젝션이 의심되는 입력이 포함된 경우

## Acceptance Criteria

- [ ] <<AI>> 스키마 생성 화면이 열린 상태일 때, 사용자가 유효한 이름·키·타입·기본값·표시 옵션을
      입력하고 저장하면, 새 스키마를 생성하고 스키마 목록에 표시함.
- [ ] <<AI>> 키 또는 옵션·기본값 입력이 유효하지 않은 상태일 때, 사용자가 저장하면, 저장을 차단하고
      유효성 오류를 표시함.
- [ ] <<AI>> 스키마 키가 중복인 상태일 때, 사용자가 저장하면, 저장을 차단하고 충돌하는 스키마를
      표시함.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `179`
