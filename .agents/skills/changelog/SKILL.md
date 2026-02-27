---
name: changelog
description: 변경사항을 사용자/릴리즈 관점의 changelog 또는 release notes로 정리합니다.
compatibility: opencode
metadata:
  workflow: release
  output: notes
---

이 스킬은 코드 변경을 "배포 노트"로 전환하는 워크플로우입니다.

## 목표

- 사용자 관점의 변경점(Added/Changed/Fixed 등)으로 정리
- Breaking change/마이그레이션/리스크를 명확히
- 구현 디테일 과다 노출 없이도 의미가 전달되게

## 워크플로우

1) changelog 시스템 확인

- 우선순위
  - `CHANGELOG.md`/`CHANGELOG.md` 변형
  - `.changeset/` (Changesets)
  - `releases/`, `docs/release-notes*`
- 없다면: PR description에 넣을 "Release notes" 섹션을 작성한다.

2) 변경점 분류

- Added: 새 기능
- Changed: 동작/UX 변경
- Fixed: 버그 수정
- Removed/Deprecated: 제거/중단
- Security: 보안 관련

3) 독자 대상 정리

- 개발자/사용자/운영자 중 누구에게 영향인지 표시
- 필요한 경우 설정 변경/마이그레이션 단계 포함

4) 검증/리스크 포함

- 어떤 테스트/수동 QA를 했는지 한 줄
- 롤백 포인트가 있으면 적는다.

## 출력 형식(권장)

```markdown
## Release notes

### Added
- ...

### Changed
- ...

### Fixed
- ...

### Notes
- Validation: ...
- Risk: ...
```
