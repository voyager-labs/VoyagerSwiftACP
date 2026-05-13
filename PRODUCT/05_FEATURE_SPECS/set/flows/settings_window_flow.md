# SET Settings Window Flow

## Intent

`SET-001`은 Settings window를 열고 닫으며, 현재 구현된 General/Appearance section 사이를 전환하는 설정 창 shell 흐름을 정의한다.

## Contract References

- 이 흐름은 Settings window shell과 section selection state를 다루며 별도 category contract 없이 `settings_window` IA region을 기준으로 정렬한다.

## Interaction Coverage

- [SET-001-open_settings_window](../SET-001-control_settings_window/SET-001-open_settings_window.md)
- [SET-001-close_settings_window](../SET-001-control_settings_window/SET-001-close_settings_window.md)
- [SET-001-swtich_setting_tabs](../SET-001-control_settings_window/SET-001-swtich_setting_tabs.md)

## Flow Overview

```mermaid
flowchart LR
  A[Open Settings] --> B[Load General and Appearance]
  B --> C[Select section]
  C --> D[Show selected settings form]
  D --> E[Close Settings]
```

## Happy Path

1. 사용자가 Settings를 열면 Settings window가 표시되고 `onAppear`에서 General/Appearance 설정 로드를 시작한다.
2. 사용자가 section을 선택하면 `selectedSection`만 갱신되고 child setting state는 유지된다.
3. 닫기 명령은 현재 Settings window를 닫고 저장된 설정값은 UserDefaults에 남긴다.

## Alternate Paths

### Reopen Existing Window

1. Settings window가 이미 열려 있으면 같은 설정 surface를 다시 표시한다.
2. 기존 child state를 불필요하게 초기화하지 않는다.

## Boundary Notes

- 이 흐름은 window shell과 section selection만 소유한다.
- 개별 설정값 변경은 `SET-002`, `SET-003`이 소유한다.

## Source

- Category: `SET`
- Covered feature: `SET-001 Control Settings Window`
