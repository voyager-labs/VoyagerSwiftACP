---
interaction_id: "SET-002-toggle_launch_at_startup"
interaction_type: "input"
feature: "Configure General Settings"
category_key: "SET"
feature_id: "SET-002"
status: "배포 완료"
summary: "앱을 OS 로그인 시 자동 실행하도록 켜거나 끕니다."
related_region: "settings_window.settings_body.tab_general"
menu: "-"
shortcut: "-"
---

# Toggle Launch At Startup

## Intent

- 앱을 OS 로그인 시 자동 실행하도록 켜거나 끕니다.
- `SET-002`의 구현 surface에서 이 동작의 입력, 상태 변경, 사용자 피드백 경계를 명확히 한다.

## Trigger / Entry Points

- General tab이 로드되거나 사용자가 시작 디렉토리, 로그인 시 실행, 자동 업데이트, 종료 전 확인을 변경할 때 호출된다.
- 사용자가 Check for Updates action을 실행할 때 호출된다.

## Preconditions

- General settings state가 로드되어 UserDefaults와 시스템 dependency를 읽고 쓸 수 있어야 한다.

## Expected Outcome

- 앱을 OS 로그인 시 자동 실행하도록 켜거나 끕니다.
- 시작 디렉토리는 저장된 `defaultTabPath`가 없으면 home path로 초기화되어야 한다.
- Launch at Login은 실제 시스템 등록 상태와 저장값이 다르면 시스템 상태를 우선해 저장값을 보정해야 한다.
- Automatic Update와 Alert Before Quit은 UserDefaults에 즉시 저장되어야 한다.
- Check for Updates는 AppRoot를 통해 UpdaterFeature.checkForUpdates로 위임되어야 한다.

## State Changes

- startingDirectory, selectedDirectoryOption, launchAtStartup, automaticUpdate, alertBeforeQuit 값을 갱신한다.
- Other... 선택 시 directory picker를 열고, 선택 결과가 유효한 directory일 때만 저장한다.
- launchAtLoginClient 실패 시 이전 값으로 복구하고 오류 문구를 남긴다.

## User-visible Feedback

- 선택한 시작 디렉토리, 토글 상태, 유효하지 않은 디렉토리 오류, launch-at-login 실패 오류를 General tab 안에 표시한다.
- 업데이트 확인은 Sparkle UI 또는 updater feedback이 이어받는다.

## Edge Cases / Failure Handling

- 선택한 경로가 존재하지 않으면 `Invalid directory path`를 표시하고 저장하지 않는다.
- 선택한 경로가 directory가 아니면 `Selected path is not a directory`를 표시하고 저장하지 않는다.
- Launch at Login 설정 실패 시 토글 상태를 이전 값으로 되돌린다.
- 입력이 유효하지 않으면 저장/적용을 실행하지 않고 수정 가능한 오류 상태를 유지한다.

## Acceptance Criteria

- [ ] 저장된 시작 디렉토리가 없으면 General tab 로드 시 home directory가 선택되어야 한다.
- [ ] Other...에서 유효한 directory를 선택하면 `defaultTabPath`에 저장되어야 한다.
- [ ] Launch at Startup을 켰다가 시스템 설정이 실패하면 토글이 이전 값으로 복구되어야 한다.
- [ ] Automatic Update를 변경하면 `SettingsKeys.automaticUpdate`가 갱신되어야 한다.
- [ ] Check for Updates를 실행하면 UpdaterFeature의 수동 업데이트 확인으로 위임되어야 한다.

## Permissions / Dependencies

- General settings state가 로드되어 UserDefaults와 시스템 dependency를 읽고 쓸 수 있어야 한다.
- 관련 UI region: `settings_window.settings_body.tab_general`

## Observability / Analytics

- setting load/save 이벤트
- UserDefaults key 변경
- 시스템 dependency 실패 reason

## Related Interactions

- [SET-002-toggle_automatic_update_install](SET-002-toggle_automatic_update_install.md)
- [SET-002-show_currnet_version_info](SET-002-show_currnet_version_info.md)
- [SET-002-check_for_updates](SET-002-check_for_updates.md)
- [SET-002-toggle_alert_before_app_quit](SET-002-toggle_alert_before_app_quit.md)
- [SET-002-confiure_initial_page](SET-002-confiure_initial_page.md)

## Source

- Inventory row: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv:230`
- Flows: [settings_general_flow.md](../flows/settings_general_flow.md)
- Implementation references: `../voyager-app/apps/macos/Packages/02_Pages/Settings/Sources/VoyagerPagesSettings/Reducer/SettingsFeature.swift`, `../voyager-app/apps/macos/Packages/02_Pages/Settings/Sources/VoyagerPagesSettings/Reducer/GeneralSettingsFeature.swift`, `../voyager-app/apps/macos/Packages/02_Pages/Settings/Sources/VoyagerPagesSettings/Reducer/AppearanceSettingsFeature.swift`
