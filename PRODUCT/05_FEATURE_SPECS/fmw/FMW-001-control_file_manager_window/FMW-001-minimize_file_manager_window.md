# Minimize File Manager Window

## Metadata

| Field            | Value                                        |
| ---------------- | -------------------------------------------- |
| Interaction ID   | FMW-001-minimize_file_manager_window         |
| Interaction Type | command                                      |
| Feature          | Control File Manager Window                  |
| Category Key     | FMW                                          |
| Feature ID       | FMW-001                                      |
| Status           | 배포 완료                                    |
| Summary          | 해당 File Manager 창을 macOS Dock으로 최소화 |
| Related Region   | file_manager_window                          |
| Menu             | Window                                       |
| Shortcut         | ⌘M                                           |

## Preconditions

- 대상 창이 최소화되지 않은 상태

## Edge Cases

-   -

## Acceptance Criteria

- [ ] 대상 File Manager Window가 일반 창 상태일 때, 사용자가 해당 인터랙션을 호출하면, 대상 창이
      Dock으로 최소화되며 다른 활성 창으로 전환됨

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `7`
