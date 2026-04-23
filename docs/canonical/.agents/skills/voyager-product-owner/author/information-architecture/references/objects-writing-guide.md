# OBJECTS Writing Guide

Use this guide when editing `PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/data.tsv`.

`OBJECTS` is the canonical noun layer for product-facing object keys that contracts and specs may reference.

## Field Guidance

- `category`: use the settled enum vocabulary only
- `key`: stable canonical object noun; never use `TBD`
- `label_ko`: short Korean display label
- `summary`: Korean one-liner that explains the object as a general product concept

## Summary Style

- Prefer ordinary product language over raw key repetition.
- Do not make the summary sound like a field-name expansion or schema note.
- Prefer describing what the object is for users or the product model, not how the key is composed.
- When another object key is relevant, prefer a natural Korean label or a general phrase over copying raw key names repeatedly.
- Keep the sentence broadly understandable even outside the immediate contract that introduced the object.

Good summary style:

- `여러 턴을 묶어 대화의 연속성과 복원 범위를 유지하는 세션 단위`
- `현재 요청에 반영될 페이지, 선택 항목, 명시적 참조를 묶어 관리하는 컨텍스트 단위`

Avoid:

- key names restated as definitions, such as `request_context를 구성하는 context_entry`
- implementation-tinted phrases, such as `immutable context 표현`, unless that immutability is itself the product-facing concept
- summaries that only make sense when read together with one contract file

## Decision Rule

- If the noun is product-wide and reused across contracts or specs, add it to `OBJECTS`.
- If the term is only a local relational phrase for one contract, keep it out of `OBJECTS` and avoid promoting it unless reuse becomes real.
