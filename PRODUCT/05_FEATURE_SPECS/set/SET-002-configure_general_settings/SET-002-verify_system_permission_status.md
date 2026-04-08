# Verify System Permission Status

## Metadata

| Field            | Value                                                                                                                                     |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Interaction ID   | SET-002-verify_system_permission_status                                                                                                   |
| Interaction Type | background                                                                                                                                |
| Feature          | Configure General Settings                                                                                                                |
| Category Key     | SET                                                                                                                                       |
| Feature ID       | SET-002                                                                                                                                   |
| Status           | 개발 중                                                                                                                                   |
| Summary          | <<AI>> 설정(General)에서 Full Disk Access 및 Notifications 권한 상태를 재조회해 최신 상태로 갱신하고, 상태 배지/안내 문구를 업데이트한다. |
| Related Region   | settings_window.settings_body.tab_general                                                                                                 |
| Menu             | -                                                                                                                                         |
| Shortcut         | -                                                                                                                                         |

## Preconditions

- <<AI>> 설정 창이 열려 있고 General 탭이 표시된 상태
- <<AI>> 권한 상태 재조회 트리거(설정 화면 진입, 앱 재활성화 등)가 발생한 상태

## Edge Cases

- <<AI>> OS 반영 지연으로 권한 상태가 즉시 갱신되지 않는 경우
- <<AI>> OS 버전에 따라 상태 조회 방식이 달라 일시적으로 조회가 실패하는 경우
- <<AI>> 권한 상태 조회 API가 오류를 반환하는 경우

## Acceptance Criteria

- [ ] <<AI>> 설정 창의 General 탭이 표시된 상태일 때, 상태 점검을 실행하면, Full Disk Access 및
      Notifications의 권한 상태가 최신 값으로 갱신됨.
- [ ] <<AI>> 사용자가 시스템 설정에서 권한을 변경하고 앱으로 돌아온 상태일 때, 상태 점검을 실행하면,
      변경된 권한 상태가 설정 화면에 반영됨.
- [ ] <<AI>> 상태 조회가 실패한 상태일 때, 상태 점검을 실행하면, 기존 표시를 유지하고 재시도 안내가
      표시됨.
- [ ] <<AI>> 상태 반영이 지연되는 상태일 때, 상태 점검을 실행하면, 지연 안내가 표시되고 재점검
      트리거가 유지됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `230`
