# FEATURE_SPEC Template

이 문서는 `PRODUCT/05_FEATURE_SPECS/` 문서를 새로 만들거나 크게 개편할 때 사용하는 기본 템플릿입니다.
상세 작성 기준은 `../../META/feature_specs_writing.md`를 참고합니다.

## 사용 원칙

- 이 템플릿은 **interaction 단위** 스펙에 사용합니다.
- 아래의 **고정 섹션 구조**를 유지합니다.
- 내용이 없으면 `-`, 아직 미정이면 `TBD`를 사용합니다.
- 기존 문서와의 일관성을 위해 `Metadata` 필드는 가능한 한 유지합니다.

---

# <Interaction Title>

## Metadata

| Field            | Value |
| ---------------- | ----- |
| Interaction ID   | TBD   |
| Interaction Type | TBD   |
| Feature          | TBD   |
| Category Key     | TBD   |
| Feature ID       | TBD   |
| Status           | TBD   |
| Summary          | TBD   |
| Related Region   | TBD   |
| Menu             | TBD   |
| Shortcut         | TBD   |

## Intent

- TBD

## Trigger / Entry Points

- TBD

## Preconditions

- TBD

## Expected Outcome

- TBD

## State Changes

- TBD

## User-visible Feedback

- TBD

## Edge Cases / Failure Handling

- TBD

## Acceptance Criteria

- [ ] `...한 상황에서, ...하면, ...해야 한다.` 형식으로 적습니다.

## Permissions / Dependencies

- TBD

## Observability / Analytics

- TBD

## Related Interactions

- TBD

## Source

- Inventory: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- Source line: `TBD`
- Writing guide: `../../META/feature_specs_writing.md`
- Template: `PRODUCT/05_FEATURE_SPECS/template.md`

---

## Optional Auxiliary Section

필요한 경우에만 아래 보조 섹션을 추가합니다.

### Boundary Notes

- 이 문서가 특히 다루는 범위 / 의도적으로 다루지 않는 범위를 적습니다.

---

## Notes

- `Intent`는 **왜 필요한가**를 적는 섹션입니다.
- `Expected Outcome`은 **무슨 결과가 성립해야 하는가**를 적는 섹션입니다.
- `State Changes`는 **어떤 상태가 어떻게 바뀌는가**를 적는 섹션입니다.
- `Edge Cases / Failure Handling`은 **특수 상황과 그에 대한 시스템 반응**을 함께 적는 섹션입니다.
