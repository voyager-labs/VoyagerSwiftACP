# State Modeling

Voyager TCA State 설계는 권위 있는 값의 owner, 유효한 상태 조합, 실행 수명, 표시 비용을 함께 정의한다. 파일 수나 enum 개수를 목표로 삼지 않는다.

## 핵심 원칙

- State는 필요한 최소 도메인으로 시작한다. child reducer를 추출하면 그 관심사의 State/Action/전이/실행 수명도 함께 분리한다.
- State가 존재한다는 이유만으로 effect가 자동 실행되지는 않는다. 화면 표시 여부, State 보존 여부, 작업 수명을 별도로 결정한다.
- Scope는 stored child property를 기본으로 한다. 매 접근마다 정렬·필터·새 child State를 만드는 computed scope는 금지한다.
- 단순 getter, 이미 소유한 child의 optional presentation bridge는 예외가 될 수 있다. 비용과 lifetime을 명시하고 회귀 테스트를 둔다. 이를 이유로 writable child 사본을 하나 더 저장하지 않는다.
- 같은 의미의 canonical 값에 writer가 여러 개 생기는 것을 막는다. draft, baseline, reload candidate, immutable render snapshot은 역할이 다른 값이며 일괄 제거 대상이 아니다.

## State 배치 결정

| 값 | 기본 owner |
| --- | --- |
| domain identity, committed definition | 해당 Entity/aggregate |
| 작업 phase, request/generation, recovery | 해당 workflow/capability reducer |
| 편집 중 text/condition draft, undo history | 편집 Feature |
| selected Entry IDs, focus/range anchor | selection/presentation aggregate |
| row/index map, responder, isApplyingProjection | native adapter |
| hover, drag pixel offset, animation progress | View/Coordinator |
| 이미지·대용량 재사용 캐시 | 명시적 cache boundary; State에는 key/version/수요 |

Selection은 파일 작업·키보드·복원에 영향을 주므로 단지 UI에서 사용된다는 이유로 View에 숨기지 않는다. 반대로 pixel 단위 geometry를 action으로 모두 전달하지 않는다.

## Optional State와 retained State

실제 presentation 또는 child lifetime이 시작·종료될 때 optional State와 `ifLet`/`@Presents`를 사용한다. 비활성 탭, 보존된 편집 초안, 백그라운드 채팅·파일 작업은 화면이 사라져도 수명이 남을 수 있다. 이런 State를 visibility만으로 nil로 만들지 않는다.

```swift
@ObservableState
struct ParentState {
    var session: SessionState
    @Presents var confirmation: ConfirmationState?
}
```

Parent는 child의 생성·제거·이동을 소유할 수 있지만, 유지되는 child의 내부 phase 전이를 대신 구현하지 않는다. 제거 시 취소되는 작업과 별도 owner로 이전되는 작업을 구분한다.

## Phase와 모델 불변식

- 한 작업의 배타적 단계는 enum으로 모델링하여 불가능한 조합을 줄인다. phase에만 필요한 payload는 해당 case/작업 모델과 함께 둔다.
- 병렬로 가능한 검색과 저장은 별도의 상태 머신을 유지한다. 모든 bool을 하나의 거대 enum으로 합치지 않는다.
- request identity, owner identity, generation/revision과 legal phase를 함께 검사해 late result를 수용한다.
- 외부 쓰기 취소는 실제 rollback을 보장하지 않는다. ambiguous/applied-unverified/read-back 상태를 단순 idle로 바꾸지 않는다.
- 새 content snapshot과 정착된 selection처럼 동시에 맞아야 하는 값은 하나의 작은 aggregate에서 원자적으로 commit한다. 후속 setter Action 사슬로 깨진 불변식을 복구하지 않는다.

## Model 구분

Wire DTO, domain value, operation input/result, edit draft, persisted baseline, render projection을 구분한다. 이들을 위해 무조건 별도 target·protocol·wrapper를 만들지는 않는다. 변환이나 보호 책임이 있는 경계에서만 타입을 분리한다.

Operation에는 실행 시점의 immutable target/context를 전달한다. selection이나 전체 FileManagerContentState를 서비스가 계속 복제·동기화하는 방식은 피한다. stable identity와 현재 path, 화면 occurrence와 native row index도 서로 다른 개념이다.

공개 State의 mutation surface는 가능한 한 좁힌다. SwiftPM module 밖 쓰기를 제한할 때 `public internal(set)`이나 opaque Action factory가 유용하지만, composition에 필요한 writable key path와 공개 associated-value 접근 수준을 실제 컴파일로 확인한다. 모든 Action에 동일한 형태를 강요하지 않는다.

## Projection과 관찰 비용

- 일반 계산은 leaf 가까이에 둔다. 무거운 projection은 관련 입력 변경에만 계산하고 selection-only 갱신과 분리한다.
- native adapter는 ID/row map을 재사용한다. 썸네일 완료만으로 전체 content를 정렬하지 않는다.
- 캐시에는 소유자, invalidation 입력, 보존 수명과 revision 의미가 필요하다. canonical writable state와 경쟁하는 캐시는 만들지 않는다.
- debounce/throttle은 비싼 계산 뒤가 아니라 계산 전에 적용한다. 실제 필요한 중간 상태·응답 지연은 측정하여 결정한다.
- `State: Equatable` 구현에서 의미 있는 변경을 임의로 숨기지 않는다. observation 회피를 위해 비교가 항상 true인 wrapper를 늘리지 않는다.

## 기존 optional projection bridge (Guard Overlay)

기존 access gate처럼 canonical child는 보존하면서 특정 phase에서만 overlay를 표시하는 경우, 새로운 writable State를 저장하는 대신 기존 child의 가벼운 optional projection을 유지할 수 있다.

```swift
var presentedAccountAccess: AccountAccessFeature.State? {
    switch accessGatePhase {
    case .recoveryRequired, .signedOut:
        accountAccess
    case .unresolved, .checking, .granted, .terminating:
        nil
    }
}
```

이 예외는 새 child State를 계산·정렬·조립하는 computed scope를 허용하지 않는다. 외부 optional store API와 내부 retained child의 lifetime을 테스트하고, 기존 `IfLetStore` 소비자 계약을 보존한다. State가 존재한다는 것과 overlay가 mount된다는 것을 동일시하지 않는다.

## 검증

소유권 변경 시 stale completion, cancel/replace, close/remount, reload 실패, draft 보존 등 영향을 받는 시나리오를 검증한다. 선택-only path는 projection/sort/diff 호출 수로 검증한다. AST는 일부 문법만 확인할 수 있으며 전역 single-writer나 성능 향상을 증명하지 않는다.

## 관련 문서

- `tca-contract.md` — reducer 합성·실행·cancel 경계
- `action-design.md` — 의미 있는 Action 설계
- `performance.md` — 성능 비용 및 계측
