# Gate 3: Contract Alignment

스펙이 contract, flow, 상태 어휘(state vocabulary)와 정렬되어 있는지 검증.

스펙의 의미적 무결성을 보장하는 게이트.

## Input

| Data | Description |
|---|---|
| `status_aligned_specs[]` | Gate 2까지 통과한 스펙 파일 목록 |
| `category_key` | 오디트 대상 카테고리 |
| `verified_contracts[]` | Gate 0.5에서 검증된 contract 파일 목록 |
| `verified_flows[]` | Gate 0.5에서 검증된 flow 파일 목록 |

## Procedure

### 1. Contract consistency 스크립트 실행

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_contract_consistency.py <category>
```

결과를 파싱하여 FAIL/WARN 항목을 분류.

### 2. 상태 어휘(state vocabulary) 검증

각 스펙에서 사용하는 상태 이름이 contract에 정의된 키와 일치하는지 확인.

검증 방법:
1. contract TOML에서 `[state]` 섹션의 키를 추출
2. 스펙 본문에서 상태를 참조하는 부분을 추출
3. 스펙이 참조하는 상태가 contract에 정의되어 있는지 교차 확인

예시:
```toml
# contract
[state]
initial = "idle"
transitions = [
  { from = "idle", to = "loading" },
  { from = "loading", to = "complete" },
]
```

스펙에서 `loading`, `complete`, `idle` 외의 상태를 참조하면 vocab drift.

### 3. 소유권 경계(ownership boundary) 검증

contract의 `[ownership]` 섹션과 스펙의 실제 동작 기술을 비교.

검증 항목:
- **display interaction**: `writes = []`인데 스펙이 쓰기 동작을 기술하면 FAIL
- **action interaction**: `writes` 배열에 없는 상태를 변경한다고 기술하면 FAIL
- **reads 누락**: 스펙이 읽는 상태가 `reads` 배열에 없으면 WARN

```
[ownership."ONB-002-show_access_unlock_status"]
reads = ["pending", "complete", "blocked", "error"]
writes = []
```

이 contract에서 `writes = []`인데 스펙이 "progress_snapshot에 반영" 같은 쓰기 동작을
기술하면 소유권 경계 위반.

### 4. CTA 레이블 정합성

스펙에 등장하는 CTA(Call To Action) 버튼/액션의 레이블이 contract에 정의된
이벤트/액션 이름과 일치하는지 확인.

### 5. Flow 단계 정합성

flow 문서에 정의된 단계 순서와 스펙에 기술된 동작의 순서가 일치하는지 확인.

큰 순서가 맞아야 함. 세부 단계의 미세한 차이는 WARN 처리.

## P/NP Criteria

### PASS

- `check_contract_consistency.py` 결과: FAIL = 0
- 상태 어휘: 스펙이 참조하는 모든 상태가 contract에 정의되어 있음
- 소유권 경계: 위반 없음 (display가 writes 불가, writes 배열 내 상태만 변경)
- CTA 레이블: contract의 액션 이름과 일치
- Flow 순서: 큰 흐름이 일치

### NOT PASS

- contract consistency FAIL 항목이 1개 이상
- 정의되지 않은 상태를 스펙에서 참조
- display interaction이 쓰기 동작을 기술
- writes 배열에 없는 상태를 변경한다고 기술
- CTA 레이블이 contract와 불일치

## Fix Protocol

### 상태 어휘 drift

1. contract에 없는 상태를 스펙에서 사용하는 경우:
   - contract에 상태를 추가해야 하면 추가
   - 스펙의 참조가 잘못되었으면 올바른 상태 이름으로 수정
2. 사용하지 않는 상태가 contract에만 있는 경우:
   - WARN으로 기록 (제거 검토 권장)

### 소유권 경계 위반

1. display interaction이 쓰기를 기술하는 경우:
   - 스펙에서 쓰기 동작 제거
   - 쓰기가 필요하면 올바른 action interaction으로 이동
2. writes 배열 밖의 상태를 변경하는 경우:
   - contract의 writes 배열에 상태 추가, 또는
   - 스펙의 동작 기술을 writes 범위 내로 수정

### CTA 레이블 불일치

1. contract의 액션/이벤트 이름을 우선으로 함
2. 스펙의 CTA 레이블을 contract에 맞춤

### Flow 순서 불일치

1. flow 문서의 순서를 기준으로 함
2. 스펙의 동작 기술 순서를 flow에 맞춤
3. flow 자체가 잘못되어 있으면 flow도 수정

### 수정 후 재실행

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_contract_consistency.py <category>
```

FAIL이 0이 될 때까지 반복.

## Commit Format

```
audit(<CATEGORY>): Gate 3 — contract/flow 정렬
```

## Output

1. **Contract consistency report**: 스크립트 결과 + 수동 검증 결과
2. **Vocabulary alignment matrix**: contract 상태 vs 스펙 참조 비교
3. **Ownership audit**: 소유권 경계 검증 결과
4. **Fixes applied**: 어휘 수정, 소유권 경계 수정 내역
5. **Gate 3 result**: P or NP
6. **Audit matrix**: Gate 3 컬럼 업데이트

다음 게이트로 전달하는 데이터:
- `contract_aligned_specs[]`: contract/flow와 정렬된 스펙 목록
- `contract_fixes{}`: 수정한 내역
