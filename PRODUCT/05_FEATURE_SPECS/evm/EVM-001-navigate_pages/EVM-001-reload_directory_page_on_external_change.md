# Reload Directory Page on External Change

## Metadata

| Field            | Value                                                                                              |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| Interaction ID   | EVM-001-reload_directory_page_on_external_change                                                   |
| Interaction Type | background                                                                                         |
| Feature          | Navigate Pages                                                                                     |
| Category Key     | EVM                                                                                                |
| Feature ID       | EVM-001                                                                                            |
| Status           | 기획 완료                                                                                          |
| Summary          | 외부 파일시스템 변경이 발생했을 때 현재 디렉토리 페이지를 다시 불러와 최신 엔트리 목록 상태를 반영 |
| Related Region   | file_manager_window.content_pane.page_container.page_mode_directory                                |
| Menu             | -                                                                                                  |
| Shortcut         | -                                                                                                  |

## Preconditions

- 현재 Content Pane이 일반 디렉토리 페이지를 표시 중인 상태
- 외부 파일시스템 변경 신호가 현재 디렉토리 자체 또는 그 하위 경로 범위와 관련된 상태

## Edge Cases

- 변경 신호가 매우 짧은 시간 안에 연속으로 발생해 reload가 중복 예약되는 경우
- 디렉토리 페이지가 reload 직전에 다른 페이지로 전환되는 경우
- 현재 페이지가 collection route라 이 reload 경로를 사용하면 안 되는 경우
- reload 시점에 대상 경로 접근 권한이 사라지거나 스토리지가 분리된 경우
- 디렉토리 내부 일부 항목만 바뀌었지만 전체 페이지를 다시 불러와야 하는 경우

## Acceptance Criteria

- [ ] 현재 일반 디렉토리 페이지가 표시 중일 때, 외부 파일시스템 변경 신호가 현재 디렉토리 자체 또는
      그 하위 경로 범위와 관련되어 수신되면, 시스템은 해당 디렉토리 페이지를 다시 불러와 최신 엔트리
      목록 상태를 반영함
- [ ] 외부 변경 신호가 짧은 시간 안에 연속으로 발생하면, helper/app upstream coalescing 결과에 따라
      과도한 중복 신호는 줄어들 수 있으며 관련 변경 수신 시 현재 디렉토리 reload 경로를 실행함
- [ ] reload 도중 사용자가 다른 페이지로 이동했다면, 시스템은 이전 페이지를 잘못 다시 표시하지 않고
      현재 네비게이션 상태를 우선 유지함
- [ ] 현재 페이지가 collection route라면, 시스템은 이 디렉토리 reload 경로를 사용하지 않고
      collection stale 반응 경로를 유지함
- [ ] reload 시점에 권한 또는 스토리지 접근 문제가 발생하면, 시스템은 기존 페이지를 즉시 깨뜨리지
      않고 실패를 처리 가능한 상태로 남김

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `23`
