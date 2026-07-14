---
name: tca
description: Voyager macOS TCA state modeling, action design, effects, navigation, performance, testing, and anti-pattern reference. Use when writing TCA reducers, designing state/action, implementing navigation, debugging performance, or writing tests under apps/macos.
compatibility: opencode
metadata:
    parent_skill: voyager-dev
    role: implementer
    shape: tca
---

# TCA Implementation Guide

Voyager macOS TCA 구현 가이드. apps/macos/\*\*에서 TCA reducer, state, action, effect, navigation, test 작업 시 사용.

## When to Use

- 새로운 Feature reducer를 설계할 때
- State 모델링 방식(optional, computed, scope)을 결정해야 할 때
- Action 네이밍과 액션 비용을 고려해야 할 때
- Effect에서 .run/.send/.merge/.cancel을 선택해야 할 때
- Navigation 패턴(tree-based vs stack-based)을 선택할 때
- TCA 성능 이슈(action cost, scope cost, high-frequency)를 디버깅할 때
- TestStore 기반 reducer 테스트를 작성할 때
- 코드 리뷰에서 TCA 안티패턴을 검출할 때

## References

- `references/state-modeling.md` -- State 설계: optional state, scope 성능, computed property, UI state 분리, @ObservableState 모범 사례
- `references/action-design.md` -- Action 네이밍("what happened" 규칙), action cost 인지, delegate 패턴, 고빈도 액션 회피
- `references/effects.md` -- Effect API: .run/.send/.merge/.cancel, 장기 실행 effect, debounce/throttle, cancellation boundary
- `references/navigation.md` -- Navigation 패턴: tree-based(@Presents/ifLet), stack-based(StackState/forEach), deep linking, dismissal 자동 취소
- `references/performance.md` -- TCA 성능: \_printChanges, scope cost, action cost, signpost, store scoping, 고빈도 액션
- `references/testing.md` -- TestStore: exhaustive/non-exhaustive 모드, TestClock, case key paths, feature별 test checklist
- `references/anti-patterns.md` -- TCA 안티패턴: god reducer, AI 생성 코드 오류, 성능 함정, state-action 설계 실수

## 기존 문서와의 관계

이 skill의 reference 파일들은 기존 Voyager TCA 문서를 **대체하지 않고 보완**한다.

| 주제                                          | 담당 문서              | 본 skill의 역할        |
| --------------------------------------------- | ---------------------- | ---------------------- |
| @Reducer/@Dependency 사용법, split model 구조 | tca-contract.md        | 이미 다룸 -> 중복 금지 |
| View boundary, Side-effect, Dependency client | tca-contract.md        | 이미 다룸 -> 중복 금지 |
| Cancellation ownership                        | tca-contract.md        | 이미 다룸 -> 중복 금지 |
| Scope/CombineReducers/ifLet/forEach/ifCaseLet | reducer-composition.md | 이미 다룸 -> 중복 금지 |
| State modeling, Action design                 | **본 스킬**            | gap 채움               |
| Effects, Navigation, Performance              | **본 스킬**            | gap 채움               |
| Testing, Anti-patterns                        | **본 스킬**            | gap 채움               |

## 적용 제외

다음 주제는 전용 skill/rules가 있으므로 본 문서에서 다루지 않는다:

- FSD segmentation -> `../../../reviewer/boundary/`
- Dependency client 설계 -> `../../../rules/30-macos/11-dependency-client-design.md`
- @DependencyClient macro -> Voyager는 struct-of-closures 사용, `../tca/references/effects.md`
- Observation lifecycle -> `../observation/SKILL.md`
- Reducer decomposition -> `../../planner/decompose/`
- Scaffolding -> `../../planner/scaffold/`
