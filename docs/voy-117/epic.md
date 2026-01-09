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
- Integration points: `AppLifecycleFeature`, `HelperAppClient`, `HelperLifecycle`, `ProcessRunner`, `BackendEndpointClient`, `DistributedNotificationCenter`.

**Enhancement Details:**

- What's being added/changed: Helper 재시작 정책(backoff/최대 재시도/초과 시 앱 종료) 확정 및 구현.
- How it integrates: 앱은 Helper 종료 이벤트를 감시해 재실행하고, Helper는 backend 실행/종료/재기동을 책임진다.
- Success criteria: 검증 체크리스트 전 항목을 수동 QA로 통과.

#### Stories

1. [x] **Story 1:** VOYAGER_PROJECT_ROOT 전달 및 source 모드 경로 탐지 안정화. (Status: Done) (`docs/voy-117/stories/117.1.voyager-project-root.md`)
2. [x] **Story 6:** SwiftLog 도입 및 로그 교체. (Status: Done, 실행 순서: 1.5, Story 2 이전) (`docs/voy-117/stories/117.6.swift-log-logging.md`)
3. [-] **Story 4 (Superseded):** UI 엔드포인트 탐지 로직 정리(`pgrep` + `lsof`) 및 runtime config 제거. (Status: Superseded) (`docs/voy-117/stories/117.4.ui-endpoint-discovery.md`)
4. [x] **Story 5:** BACKEND_MODE 기반 DB 경로 분리 및 관계 문서 정리. (Status: Done) (`docs/voy-117/stories/117.5.backend-mode-db-path.md`)
5. [x] **Story 7:** Python 백엔드 실행 프로세스 정리. (Status: Done) (`docs/voy-117/stories/117.7.python-backend-execution-process.md`)
6. [x] **Story 9:** Helper ProcessRunner async 전환 및 동시성 정리. (Status: Done) (`docs/voy-117/stories/117.9.helper-async-processrunner.md`)
7. [ ] **Story 8:** Helper 포트 선점 및 endpoint 전달. (Status: Draft, Story 4 대체) (`docs/voy-117/stories/117.8.helper-port-reservation-endpoint-delivery.md`)
8. [ ] **Story 3:** Helper에서 backend 생명주기 관리 강화(실행/종료/재기동/포트 확보). (Status: Review, 선행: Story 9) (`docs/voy-117/stories/117.3.backend-restart-management.md`)
9. [ ] **Story 2:** 앱에서 Helper 생명주기 정책 구현(시작/감시/재시도/강제 종료 처리). (Status: Review, 보류: Story 9 완료 후 재개) (`docs/voy-117/stories/117.2.helper-restart-policy.md`)

#### 우선순위 변경 사유

- Helper가 endpoint를 직접 전달하는 방식으로 전환했으므로 Story 8을 선행한다.
- ProcessRunner async 전환(Story 9)을 선행해 포트 검증/재시도 흐름을 안정화한다.
- Story 3/2는 Story 9 완료 후 재개해 검증 흐름을 단순화한다.
- Story 4는 Story 8으로 대체되어 Superseded 처리한다.

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
- backend 강제 종료 시 Helper 재기동 + endpoint 재전달(필요 시 fallback 탐지)
- `PUBLIC_BACKEND_PORT=0`에서도 포트 탐지 정상
- Launch at startup 활성화 후 로그인 시 UI 자동 실행, Helper는 Voyager 시작 시 실행
- source/bundled 모두 `Voyager Backend` 프로세스명 탐지 가능
