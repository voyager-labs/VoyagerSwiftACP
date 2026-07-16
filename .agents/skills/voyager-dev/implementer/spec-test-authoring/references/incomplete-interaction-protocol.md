# Incomplete Interaction Protocol

## Goal

인터랙션 스펙 문서의 `status` 필드와 테스트 스위트 간의 대응 관계를 명확히 한다.
미구현/계획/보류 상태의 인터랙션을 테스트 스위트에서 추적 가능하게 유지하면서,
구현 이슈와 무관하게 독립적으로 관리한다.

## Decision matrix: doc status → test action

| Doc status                     | Test action                          | XCTSkip 사용 |
| ------------------------------ | ------------------------------------ | ------------ |
| `"shipped"`                    | AC-backed 실제 테스트 작성           | ❌           |
| `"planned"`                    | XCTSkip placeholder 작성             | ✅           |
| `"drafted"` + `phase: "later"` | 테스트 작성 안 함 (MARK 섹션만 가능) | ❌           |
| `"deprecated"`                 | 테스트 작성 안 함                    | ❌           |
| `[DECISION NEEDED]`            | 테스트 작성 안 함, 증거 파일에 기록  | ❌           |

## XCTSkip placeholder 규칙

### 언제 작성하나

인터랙션 스펙 문서가 `status: "planned"`이고, 해당 인터랙션이 소속 스펙의 정식 AC 목록에 포함되어 있을 때 작성한다.

`"drafted"` + `phase: "later"` 인터랙션은 아직 AC가 확정되지 않았으므로 placeholder도 작성하지 않는다.
추후 AC가 확정되어 `"planned"` 또는 `"shipped"`로 승격되면 그때 작성한다.

### 작성 위치

해당 인터랙션의 `// MARK: - <SPEC-ID>-<interaction_id>` 섹션 내에, 다른 실제 테스트들과 같은 위치에 둔다.

### 네이밍 컨벤션

```
func test<PascalCaseInteractionName>_pendingImplementation() throws
```

- 접미사: `_pendingImplementation` (고정)
- 접두사: 인터랙션 의미를 나타내는 PascalCase 이름

예시:

```swift
// MARK: - EOP-004-edit_entry_tags

/// EOP-004-edit_entry_tags: 태그 편집 AC 구현 대기
/// - 검증 내용: 태그 편집 인터랙션의 AC가 아직 구현되지 않았다.
/// - 사전 조건: 해당 인터랙션의 status가 "planned"이다.
/// - 기대 결과: 구현 시 이 XCTSkip을 실제 테스트로 교체한다.
func testEditEntryTags_pendingImplementation() throws {
    throw XCTSkip("AC not yet implemented: edit_entry_tags (status: planned)")
}
```

### XCTSkip 메시지 포맷

```
"AC not yet implemented: <interaction_id> (status: <status_value>)"
```

**핵심 원칙:**

- **이슈 번호를 포함하지 않는다.** 특정 Linear/GitHub 이슈에 종속되면, 해당 이슈가 닫히거나 범위가 변경될 때 메시지가 부정확해진다. 또한 구현 이슈가 아직 없을 수도 있다.
- **인터랙션 ID와 status만 명시한다.** 이것만으로 어떤 인터랙션이 미구현인지 충분히 식별 가능하다.

예시:

```
✅ "AC not yet implemented: edit_entry_tags (status: planned)"
✅ "AC not yet implemented: batch_rename_entries (status: planned)"
✅ "AC not yet implemented: change_entry_permissions (status: planned)"

❌ "VOY-343 follow-up: edit entry tags AC not yet implemented"
❌ "Follow-up: implement tags (see VOY-123)"
❌ "TODO: write tests for tags"
```

### Doc comment 형태

XCTSkip placeholder 테스트에도 일반 테스트와 동일한 traceability doc comment를 작성한다:

```swift
/// <SPEC-ID>-<interaction_id>: <인터랙션 요약>
/// - 검증 내용: 해당 인터랙션의 AC가 아직 구현되지 않았다.
/// - 사전 조건: 인터랙션 스펙 문서 status가 "planned"이다.
/// - 기대 결과: 구현 시 이 XCTSkip을 실제 테스트로 교체한다.
```

## Lifecycle: placeholder → 실제 테스트

1. 인터랙션 스펙 문서의 status가 `"planned"` → `"shipped"`로 변경
2. XCTSkip placeholder 메서드를 실제 AC-backed 테스트로 교체
3. 메서드 이름 변경: `testXxx_pendingImplementation` → `testXxx_<scenario>`
4. Doc comment를 실제 시나리오에 맞게 업데이트
5. `// MARK:` 섹션은 동일하게 유지

## `"drafted"` 인터랙션 처리

`status: "drafted"` + `phase: "later"` 인터랙션은:

- 테스트 placeholder를 작성하지 않는다 (XCTSkip도 안 함)
- 필요시 빈 `// MARK:` 섹션만 둔다
- 추후 AC가 확정되면 status를 `"planned"`로 변경하고 그때 XCTSkip placeholder를 작성한다

## `[DECISION NEEDED]` 항목 처리

제품 결정이 필요한 항목은:

- 테스트를 작성하지 않는다
- 증거 파일(evidence)이나 deferred decision register에 기록한다
- 결정이 내려지면 status를 변경하고 그에 맞는 테스트를 작성한다

## Audit: 전체 placeholder 찾기

```bash
# 모든 XCTSkip placeholder 찾기
grep -rn 'XCTSkip.*AC not yet implemented' Specs/

# 특정 스펙의 placeholder 찾기
grep -n 'XCTSkip.*AC not yet implemented' Specs/EOP004EditEntryMetadataTests.swift

# placeholder 메서드 이름으로 찾기
grep -rn 'func.*_pendingImplementation' Specs/
```

## Evidence

이 프로토콜은 EOP AC Gap Closure 작업에서 확립되었다:

- EOP-004 tags/permissions/batch rename: `status: "planned"` → XCTSkip placeholder 3개
- EOP-007 show_quick_action_menu: `status: "drafted"`, `phase: "later"` → placeholder 없음
- EOP-006 relative paths: `status: "deprecated"` → 테스트 없음
- EOP-003 thumbnail cache: `[DECISION NEEDED]` → 테스트 없음, deferred register에 기록
