# SET General Settings Flow

## Intent

`SET-002`는 시작 디렉토리, 로그인 시 실행, 자동 업데이트, 종료 전 확인, 수동 업데이트 확인 등 현재 구현된 General settings 흐름을 정의한다.

## Contract References

- 이 흐름은 UserDefaults-backed settings state와 system dependency 결과를 다루며 별도 category contract 없이 `settings_window.settings_body.tab_general` IA region을 기준으로 정렬한다.

## Interaction Coverage

- [SET-002-toggle_launch_at_startup](../SET-002-configure_general_settings/SET-002-toggle_launch_at_startup.md)
- [SET-002-toggle_automatic_update_install](../SET-002-configure_general_settings/SET-002-toggle_automatic_update_install.md)
- [SET-002-show_currnet_version_info](../SET-002-configure_general_settings/SET-002-show_currnet_version_info.md)
- [SET-002-check_for_updates](../SET-002-configure_general_settings/SET-002-check_for_updates.md)
- [SET-002-toggle_alert_before_app_quit](../SET-002-configure_general_settings/SET-002-toggle_alert_before_app_quit.md)
- [SET-002-confiure_initial_page](../SET-002-configure_general_settings/SET-002-confiure_initial_page.md)

## Flow Overview

```mermaid
flowchart LR
  A[Load General tab] --> B[Read UserDefaults and system state]
  B --> C[Change a setting]
  C --> D[Persist setting]
  D --> E[Delegate side effect when needed]
```

## Happy Path

1. General tab load 시 시작 디렉토리와 UserDefaults-backed toggles를 복원한다.
2. Launch at Login은 실제 시스템 등록 상태를 확인해 저장값과 다르면 시스템 상태를 기준으로 보정한다.
3. 시작 디렉토리 변경은 표준 option 또는 directory picker 결과가 유효할 때만 저장한다.
4. Automatic Update와 Alert Before Quit은 변경 즉시 UserDefaults에 저장한다.
5. Check for Updates는 AppRoot/UpdaterFeature로 위임한다.

## Alternate Paths

### Invalid Directory

1. directory picker가 파일이나 존재하지 않는 경로를 반환하면 저장하지 않는다.
2. General tab에 수정 가능한 오류 문구를 남긴다.

### Launch At Login Failure

1. 시스템 등록 변경이 실패하면 토글을 이전 값으로 되돌린다.
2. 사용자가 System Settings에서 직접 조정할 수 있도록 실패 문구를 표시한다.

## Boundary Notes

- Full Disk Access 요청은 현재 구현 기준 Onboarding Permissions step이 소유하며, General tab 구현 완료 범위에 포함하지 않는다.
- Sparkle 업데이트 UI와 relaunch 정책은 UpdateVersion feature가 소유한다.

## Source

- Category: `SET`
- Covered feature: `SET-002 Configure General Settings`
