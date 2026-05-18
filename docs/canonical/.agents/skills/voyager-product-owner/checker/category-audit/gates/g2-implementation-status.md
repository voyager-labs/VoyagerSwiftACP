# Gate 2: Implementation Status

스펙에 기록된 `status`, `phase`, `[now]`/`[next]` 마커가 실제 앱 코드와 일치하는지 검증.

문서와 코드의 드리프트(drift)를 잡는 게이트.

## Input

| Data | Description |
|---|---|
| `lint_clean_specs[]` | Gate 1을 통과한 스펙 파일 목록 |
| `category_key` | 오디트 대상 카테고리 |
| App codebase | `/Users/jongmin/Desktop/voyager-fm/voyager-app/` |

## Procedure

### 1. status/phase별 분류

스펙 frontmatter와 FI row에서 status/phase를 수집하여 분류:

| Group | Filter | Action Required |
|---|---|---|
| `shipped` | `status: shipped` | 코드에서 구현 확인 (필수) |
| `implementing` | `status: implementing` | 코드에서 부분 구현 확인 |
| `now` | `phase: now` (any status) | `[now]` 마커 내용이 코드와 일치하는지 |
| `next/later` | `phase: next` or `later` | `[next]` 마커 내용이 미구현 상태인지 |
| `drafted/idea` | `status: drafted` or `idea` | 코드 확인 불필요 (아직 구현 전) |

### 2. shipped / implementing 스펙 코드 검증

각 `shipped`/`implementing` interaction에 대해 앱 코드베이스에서 구현을 확인.

```bash
# 앱 코드베이스에서 관련 Swift 파일 검색
# interaction_id에서 키워드 추출하여 grep
# 예: ONB-001-welcome_screen → welcome, screen
```

검색 전략:
- interaction_id의 snake_case 키워드를 기반으로 Swift 파일명 검색
- feature_id 기반으로 View, ViewModel, Action 파일 검색
- contract에 정의된 state key 이름으로 관련 타입 검색

확인 사항:
- [ ] 관련 Swift 파일이 존재하는가?
- [ ] 주요 액션/상태가 코드에 반영되어 있는가?
- [ ] UI 요소(버튼, 화면)가 구현되어 있는가?

### 3. [now] 마커 내용 검증

`[now]` 인라인 마커가 붙은 내용은 **현재 구현된 동작**을 설명해야 한다.

확인:
- 스펙에서 `[now]`로 표시된 동작이 코드에 실제로 구현되어 있는가?
- 코드에 있는 동작이 스펙에 누락되어 있지 않은가?

### 4. [next] 마커 내용 검증

`[next]` 인라인 마커가 붙은 내용은 **아직 구현되지 않은 계획**이어야 한다.

확인:
- `[next]`로 표시된 동작이 코드에 이미 구현되어 있지 않은가?
- 이미 구현된 동작에 `[next]` 마커가 붙어 있으면 → FAIL

### 5. [later] 마커 확인

`[later]` 마커는 장기 계획. 코드 검증은 불필요하지만, 마커가 올바르게 사용되었는지 확인.

## P/NP Criteria

### PASS

- `shipped` status인 모든 interaction에 코드가 존재
- `implementing` status인 interaction에 부분 구현이 존재
- `[now]` 마커 내용이 실제 코드와 일치
- `[next]` 마커 내용이 실제로 미구현 상태
- `drafted`/`idea` 상태의 스펙에 `[now]` 마커가 없음 (모순)

### NOT PASS

- `shipped`인데 코드에 구현이 없음
- `[now]` 내용이 코드와 다름 (드리프트)
- `[next]`인데 이미 코드에 구현되어 있음
- `status: shipped` + `phase: later` 조합 (모순)
- `status: idea`인데 `[now]` 마커가 있음

## Fix Protocol

### shipped인데 코드가 없음

1. 코드를 다시 검색. 다른 파일명, 모듈 위치에서 구현되어 있을 수 있음
2. 여전히 없으면: status를 `planned` 또는 `drafted`로 다운그레이드
3. FI row와 스펙 frontmatter 모두 업데이트
4. 관련 `phase`도 재검토

### [now] 내용이 코드와 다름

1. 코드의 실제 동작을 파악
2. 스펙의 `[now]` 섹션을 코드에 맞게 업데이트
3. 코드에 있는 동작이 스펙에 빠져 있으면 추가

### [next]가 이미 구현되어 있음

1. 해당 내용의 `[next]` 마커를 `[now]`로 변경
2. 관련 interaction의 status/phase 재검토
3. `next` → `now`로 phase 변경이 필요하면 FI도 업데이트

### status/phase 모순

일관성 규칙:

| status | 허용 phase |
|---|---|
| `idea` | `later` |
| `drafted` | `next`, `later` |
| `planned` | `now`, `next` |
| `implementing` | `now` |
| `shipped` | `now` |
| `deprecated` | `-` |

모순이 있으면 status 기준으로 phase를 맞춤.

## Commit Format

```
audit(<CATEGORY>): Gate 2 — status/phase를 코드 기반으로 정렬
```

## Output

1. **Status verification report**: 각 interaction의 status vs 코드 존재 여부
2. **Marker audit**: [now]/[next]/[later] 마커 정합성 결과
3. **Fixes applied**: status 변경, 마커 조정 내역
4. **Gate 2 result**: P or NP
5. **Audit matrix**: Gate 2 컬럼 업데이트

다음 게이트로 전달하는 데이터:
- `status_aligned_specs[]`: status/phase가 코드와 정렬된 스펙 목록
- `status_changes{}`: 변경된 status/phase 내역 (오디트 보고서용)
