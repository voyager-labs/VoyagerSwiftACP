---
interaction_id: "EVM-001-reload_directory_page_on_external_change"
interaction_type: "background"
feature: "Navigate Pages"
category_key: "EVM"
feature_id: "EVM-001"
status: "기획 완료"
summary: "외부 파일시스템 변경이 발생했을 때 현재 디렉토리 페이지를 다시 불러와 최신 엔트리 목록 상태를 반영"
related_region: "file_manager_window.content_pane.page_container.page_mode_directory"
menu: "-"
shortcut: "-"
---

# Reload Directory Page on External Change

## Intent

- 현재 Content Tab의 Page 이동과 history 표시를 안정적으로 제어한다.

## Trigger / Entry Points

- file_manager_window.content_pane.page_container.page_mode_directory 영역에서 관련 컨트롤 또는 명령을 실행한 경우

## Preconditions

- 외부 변경 또는 시스템 이벤트가 Page 갱신을 요구하는 상태다.

## Expected Outcome

- 외부 파일시스템 변경이 발생했을 때 현재 디렉토리 페이지를 다시 불러와 최신 엔트리 목록 상태를 반영.
- 사용자에게 보이는 결과는 `reload_directory_page_on_external_change_applied` 상태로 정리된다.

## State Changes

- Page의 표시 또는 실행 상태를 갱신한다.
- 이 인터랙션은 [evm_contract.toml](../contracts/evm_contract.toml)의 `reload_directory_page_on_external_change_applied` 상태 어휘를 따른다.

## User-visible Feedback

- 성공 시 현재 화면의 표시, 선택, 정렬, 실행 결과가 즉시 갱신된다.
- 실패 시 기존 상태를 보존하고 실패 사유를 사용자에게 표시한다.

## Edge Cases / Failure Handling

- 대상 Page이 사라졌거나 권한이 없으면 작업을 중단한다.
- 동일 요청이 반복되면 마지막으로 확정된 상태를 기준으로 중복 반영을 피한다.

## Acceptance Criteria

- [ ] 외부 변경 또는 시스템 이벤트가 Page 갱신을 요구하는 상태다. 사용자가 Reload Directory Page on External Change을 실행하면, 외부 파일시스템 변경이 발생했을 때 현재 디렉토리 페이지를 다시 불러와 최신 엔트리 목록 상태를 반영 결과가 `reload_directory_page_on_external_change_applied` 상태로 반영되어야 한다.
- [ ] 작업을 완료할 수 없는 조건이면, 앱은 기존 상태를 보존하고 실패 피드백을 표시해야 한다.
- [ ] 같은 interaction이 반복 호출되어도 중복되거나 모순된 상태가 남지 않아야 한다.

## Permissions / Dependencies

- 현재 Page, selection, 파일 시스템 접근 권한, File Manager Window layout 상태에 의존한다.

## Observability / Analytics

- `evm.reload_directory_page_on_external_change` 이벤트에 성공 여부와 대상 수, 실패 사유를 기록한다.

## Related Interactions

- [EVM-001-forward_page_history](EVM-001-forward_page_history.md)
- [EVM-001-go_page_history_back](EVM-001-go_page_history_back.md)
- [EVM-001-go_to_enclosing_directory](EVM-001-go_to_enclosing_directory.md)
- [EVM-001-navigate_pages](EVM-001-navigate_pages.md)
- [EVM-001-show_page_history](EVM-001-show_page_history.md)
- [EVM-001-view_current_page_title](EVM-001-view_current_page_title.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:23`
- Flows: [evm_flow.md](../flows/evm_flow.md)
- Contract: [evm_contract.toml](../contracts/evm_contract.toml)
