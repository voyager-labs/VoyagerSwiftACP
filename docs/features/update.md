# 업데이트

## 개요

Voyager의 업데이트 기능은 Sparkle(2.x)를 사용해 "업데이트 확인 → 다운로드 → 설치(재시작)" 흐름을 처리합니다.

이 문서에서 다루는 범위

- 업데이트 체크가 언제/어떻게 수행되는지
- 자동 다운로드 설정이 어디에 저장되고 어떻게 적용되는지
- 업데이트 설치를 위한 relaunch 시, Helper를 안전하게 종료하는 이유/흐름

관련 코드

- `apps/macos/Voyager/Voyager/04_Features/UpdateVersion/Reducer/UpdaterFeature.swift`
- `apps/macos/Voyager/Voyager/04_Features/UpdateVersion/Api/UpdaterClient.swift`

---

## 1) Sparkle 설정(앱캐스트/주기)

Sparkle의 기본 설정은 앱의 Info.plist에 들어있습니다.

- 파일: `apps/macos/Voyager/Voyager/01_App/Config/Info.plist`

현재 설정(요약)

- `SUEnableAutomaticChecks = true`
- `SUScheduledCheckInterval = 21600` (초 단위, 6시간)
- `SUFeedURL = https://downloads.voyager.fm/releases/appcast.xml`
- `SUPublicEDKey = ...` (서명 검증용 공개키)

주의

- `SUFeedURL` 변경은 배포 정책과 직결되므로, 코드 변경 전 운영/보안 정책을 먼저 확인합니다.

---

## 2) TCA Feature 관점(UpdaterFeature)

Updater는 전역적인 사이드이펙트(백그라운드 체크, 업데이트 UI 표시)를 갖기 때문에,
TCA에서는 "작은 상태 + 명령형 실행" 형태로 구현되어 있습니다.

상태

- `didConfigure`: Sparkle 컨트롤러 1회 생성 보장
- `didStartAtLaunch`: 런치 시 백그라운드 체크 1회 수행 보장

액션

- `configureAtLaunch`: 앱 런치에서 호출(중복 방지)
- `startAtLaunch`: UI 준비 후 백그라운드 체크 트리거
- `checkForUpdates`: 사용자가 수동으로 업데이트 확인
- `setAutomaticUpdate(Bool)`: 자동 다운로드 토글

관련 코드

- `apps/macos/Voyager/Voyager/04_Features/UpdateVersion/Reducer/UpdaterFeature.swift`

---

## 3) UpdaterCoordinator 동작(구현 상세)

### 3.1 컨트롤러 생성(configureIfNeeded)

Updater는 `SPUStandardUpdaterController`를 내부에 들고 있으며,
`configureIfNeeded()`에서 최초 1회만 생성합니다.

- 생성: `SPUStandardUpdaterController(startingUpdater: true, ...)`
- 자동 다운로드 설정: `UserDefaults`에서 `SettingsKeys.automaticUpdate`를 읽어
  - `controller.updater.automaticallyDownloadsUpdates`에 주입

관련 코드

- `apps/macos/Voyager/Voyager/04_Features/UpdateVersion/Api/UpdaterClient.swift`

### 3.2 런치 시 백그라운드 업데이트 체크(startAtLaunch)

업데이트 체크는 "앱이 완전히 준비되기 전"에 수행되면 UX/안정성 측면에서 이슈가 생길 수 있습니다.
그래서 `NSWindow.didBecomeMainNotification`을 기준으로 "메인 윈도우가 준비된 이후"에 체크합니다.

- 이미 `NSApp.keyWindow != nil`이면 즉시 `checkForUpdatesInBackground()`
- 아니면 main window notification을 1회 기다린 후 실행

관련 코드

- `apps/macos/Voyager/Voyager/04_Features/UpdateVersion/Api/UpdaterClient.swift`

### 3.3 수동 업데이트 확인(checkForUpdates)

사용자가 "업데이트 확인"을 트리거하면 Sparkle UI를 통해 확인을 수행합니다.

- 내부적으로 `controller.checkForUpdates(nil)` 호출

### 3.4 자동 업데이트 토글(setAutomaticUpdate)

- `automaticallyDownloadsUpdates` 값만 갱신합니다.
- 실제 저장(`UserDefaults`)은 Settings에서 수행되며, Updater는 그 값을 읽어 적용합니다.

---

## 4) 업데이트 설치(relaunch)와 Helper 종료

Sparkle은 업데이트 설치를 위해 앱 재시작(relaunch)을 요청할 수 있습니다.
Voyager는 재시작 직전에 Helper를 정상 종료시키는 경로를 포함합니다.

### 4.1 왜 Helper를 먼저 종료하는가

- Helper는 백엔드 프로세스/DB/인덱싱을 들고 있을 수 있습니다.
- 업데이트 설치 과정에서 앱 번들이 교체되거나, 프로세스가 재시작되면
  "기존 Helper가 남아있는 상태"는 포트/파일 핸들/상태 브로드캐스트 측면에서 불안정합니다.

따라서 relaunch 직전, Helper를 종료하여 "깨끗한 재시작"을 보장합니다.

### 4.2 Sparkle delegate: relaunch postpone

Sparkle delegate에서 relaunch를 잠시 연기(postpone)하고, install handler를 "딱 1번"만 호출합니다.

흐름

1) Sparkle이 relaunch를 요청 → `shouldPostponeRelaunchForUpdate(... untilInvokingBlock:)`
2) `VoyagerTerminationCoordinator.shared.begin(.sparkleRelaunch)`로 종료 사유 마킹
3) `HelperAppClient.liveValue.stop()` 호출
4) `installHandler()` 호출 → Sparkle이 relaunch 진행

안전장치

- 어떤 이유로든 stop이 지연되어도 relaunch가 영원히 막히지 않게,
  5초 후 `installHandler()`를 한 번 더 시도하는 fail-safe가 존재합니다(중복 호출 방지 로직 포함).

관련 코드

- `apps/macos/Voyager/Voyager/04_Features/UpdateVersion/Api/UpdaterClient.swift`
- `apps/macos/Voyager/Voyager/01_App/Reducer/AppLifecycleFeature.swift` (TerminationCoordinator)

---

## QA 체크리스트

- 앱 실행 시 업데이트 모듈이 중복으로 configure/start 되지 않는가(`didConfigure`, `didStartAtLaunch`)
- 앱 창이 뜨기 전에도 startAtLaunch가 안전하게 동작하는가(NSWindow main notification 대기)
- 수동 업데이트 확인이 UI를 통해 정상 동작하는가
- 자동 다운로드 토글이 다음 실행에도 유지되는가(UserDefaults)
- 업데이트 설치(relaunch) 시 Helper가 정상 종료되는가

## 트러블슈팅

- 업데이트 확인이 전혀 동작하지 않음
  - `SUFeedURL` 설정이 존재하는지 확인합니다: `apps/macos/Voyager/Voyager/01_App/Config/Info.plist`
- relaunch가 지연되거나 멈춘 것처럼 보임
  - Helper 종료가 지연되고 있을 수 있습니다. fail-safe(5s)가 동작하는지 로그를 확인합니다.
