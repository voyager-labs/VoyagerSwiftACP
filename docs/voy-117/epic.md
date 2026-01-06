# VOY-117 Epic

## Epic Title

VoyagerHelper 생명주기 관리 개선 - Brownfield Enhancement

## Epic Goal

VoyagerHelper와 Backend의 생명주기 정책을 일관되게 정의하고, 앱 종료/강제 종료 상황에서도 안정적으로 재기동과
엔드포인트 탐지가 가능하도록 보장한다.

## Epic Description

**Existing System Context:**

- Current relevant functionality: macOS Voyager 앱이 Helper를 실행/감시하고, Helper가 backend를 실행한다.
- Technology stack: SwiftUI + TCA 기반 macOS 앱, AppKit 브리지, VoyagerHelper, FastAPI(uv).
- Integration points: `AppLifecycleFeature`, `HelperAppClient`, `HelperLifecycle`, `ProcessRunner`.

**Enhancement Details:**

- What's being added/changed: Helper 재시작 정책(backoff/최대 재시도/초과 시 앱 종료) 확정 및 구현.
- How it integrates: 앱은 Helper 종료 이벤트를 감시해 재실행하고, Helper는 backend 실행/종료/재기동을 책임진다.
- Success criteria: 검증 체크리스트 전 항목을 수동 QA로 통과.

#### Stories

1. **Story 1:** VOYAGER_PROJECT_ROOT 전달 및 source 모드 경로 탐지 안정화. (`docs/voy-117/stories/117.1.voyager-project-root.md`)
2. **Story 2:** 앱에서 Helper 생명주기 정책 구현(시작/감시/재시도/강제 종료 처리). (`docs/voy-117/stories/117.2.helper-restart-policy.md`)
3. **Story 3:** Helper에서 backend 생명주기 관리 강화(실행/종료/재기동/포트 확보). (`docs/voy-117/stories/117.3.backend-restart-management.md`)
4. **Story 4:** UI 엔드포인트 탐지 로직 정리(`pgrep` + `lsof`) 및 runtime config 제거. (`docs/voy-117/stories/117.4.ui-endpoint-discovery.md`)
5. **Story 5:** BACKEND_MODE 기반 DB 경로 분리 및 관계 문서 정리. (`docs/voy-117/stories/117.5.backend-mode-db-path.md`)
6. **Story 6:** SwiftLog 도입 및 로그 교체. (`docs/voy-117/stories/117.6.swift-log-logging.md`)
7. **Story 7:** Python 백엔드 실행 프로세스 정리. (`docs/voy-117/stories/117.7.python-backend-execution-process.md`)

#### Compatibility Requirements

- [ ] Existing APIs remain unchanged
- [ ] Database schema changes are backward compatible
- [ ] UI changes follow existing patterns
- [ ] Performance impact is minimal

#### Risk Mitigation

- **Primary Risk:** Helper/Backend 재기동 루프 또는 잘못된 종료로 사용자 작업 손실.
- **Mitigation:** 재시도 횟수 제한, backoff 적용, 종료 전 로그/알림 처리.
- **Rollback Plan:** Helper/앱 생명주기 변경을 되돌리고 기존 로직으로 복귀.

#### Definition of Done

- [ ] All stories completed with acceptance criteria met
- [ ] Existing functionality verified through testing
- [ ] Integration points working correctly
- [ ] Documentation updated appropriately
- [ ] No regression in existing features

## Story Manager Handoff

Please develop detailed user stories for this brownfield epic. Key considerations:

- This is an enhancement to an existing system running SwiftUI + TCA + AppKit(macOS) and FastAPI(uv).
- Integration points: `AppLifecycleFeature`, `HelperAppClient`, `HelperLifecycle`, `ProcessRunner`.
- Existing patterns to follow: TCA reducer/DependencyKey 패턴과 Helper/Backend 분리 실행 구조.
- Critical compatibility requirements: 기존 API/DB/UX 영향 최소화, 성능 영향 최소.
- Each story must include verification that existing functionality remains intact.

The epic should maintain system integrity while delivering 안정적인 Helper/Backend 생명주기 관리와
UI 엔드포인트 탐지 일관성.

## 검증 체크리스트 (요약)

- Voyager 실행 → Helper 실행 → backend 실행 → UI 요청 성공
- Voyager 종료 후 Helper/Backend 지속 동작
- Helper 강제 종료 시 backoff 재시작, 최대 재시도 초과 시 Voyager 종료
- backend 강제 종료 시 Helper 재기동 + UI 포트 재탐지
- `PUBLIC_BACKEND_PORT=0`에서도 포트 탐지 정상
- Launch at startup 활성화 후 로그인 시 UI 자동 실행, Helper는 Voyager 시작 시 실행
- source/bundled 모두 `Voyager Backend` 프로세스명 탐지 가능
