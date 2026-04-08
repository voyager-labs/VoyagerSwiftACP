# Request Full Disk Access Permission

## Metadata

| Field            | Value                                                                                                                                                     |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Interaction ID   | SET-002-request_full_disk_access_permission                                                                                                               |
| Interaction Type | command                                                                                                                                                   |
| Feature          | Configure General Settings                                                                                                                                |
| Category Key     | SET                                                                                                                                                       |
| Feature ID       | SET-002                                                                                                                                                   |
| Status           | 개발 중                                                                                                                                                   |
| Summary          | <<AI>> 설정(General)에서 Full Disk Access 권한의 현재 상태와 필요 사유를 안내하고, 사용자가 시스템 설정에서 권한을 부여할 수 있도록 이동 경로를 제공한다. |
| Related Region   | settings_window.settings_body.tab_general                                                                                                                 |
| Menu             | -                                                                                                                                                         |
| Shortcut         | -                                                                                                                                                         |

## Preconditions

- <<AI>> 설정 창이 열려 있고 General 탭이 표시된 상태
- <<AI>> Full Disk Access 권한 상태를 조회할 수 있는 상태

## Edge Cases

- <<AI>> 사용자가 시스템 설정 열기를 취소하는 경우
- <<AI>> OS 정책/버전 제약으로 특정 권한 패널로 직접 이동할 수 없는 경우
- <<AI>> 사용자가 권한을 부여하지 않고 앱으로 돌아오는 경우- 권한을 부여했지만 상태 반영이 지연되는
  경우
- <<AI>> 권한을 부여했지만 앱 재시작이 필요한 경우
- <<AI>> MDM/보안 정책 등으로 권한 변경이 제한되는 경우

## Acceptance Criteria

- [ ] <<AI>> 설정 창의 General 탭이 표시된 상태일 때, 사용자가 해당 인터랙션을 호출하면, Full Disk
      Access 필요 사유와 현재 권한 상태가 표시됨.
- [ ] <<AI>> 권한이 미허용인 상태일 때, 사용자가 “시스템 설정 열기”를 선택하면, 시스템 설정의 Full
      Disk Access 설정 화면으로 이동함.
- [ ] <<AI>> 직접 이동이 불가능한 상태일 때, 사용자가 “시스템 설정 열기”를 선택하면, 수동 이동
      경로(Privacy & Security - Full Disk Access)가 안내됨.
- [ ] <<AI>> 사용자가 권한을 허용하고 앱으로 돌아온 상태일 때, 권한 상태를 재검증하면, 설정 화면의
      상태가 “허용됨”으로 갱신됨.
- [ ] <<AI>> 사용자가 권한을 허용하지 않고 돌아온 상태일 때, 권한 상태를 재검증하면, 상태가
      “미허용”으로 유지되고 재시도 안내가 표시됨.
- [ ] <<AI>> 권한 허용 후 재시작이 필요한 상태일 때, 상태를 갱신하면, 재시작 필요 안내가 표시됨.

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `228`
