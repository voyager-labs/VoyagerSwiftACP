<!--
릴리즈 PR 전용 template.
일반 코드 변경 PR은 default.md를 사용하세요.
GitHub Release 본문은 이 PR template과 별도로 `.github/RELEASE_NOTES_TEMPLATE.md`를 사용하세요.
PR 본문과 Release 본문을 그대로 복사하지 말고, Release 게시 시 실제 검증 결과와 최종 artifact 상태로 갱신하세요.
-->

## 릴리즈 개요

- 버전: {x.y.z}
- 릴리즈 대상: macOS
- 일정: {릴리즈 예정일}

---

## 포함된 변경사항

<!-- 이 릴리즈에 포함된 PR/커밋 목록 -->

### macOS

- {PR/#123} {변경 요약}
- {PR/#124} {변경 요약}

---

## 마이그레이션 / 호환성

- {설정 또는 사용자 데이터 호환성 변경이 있으면 기록}
- {없으면 "없음"}

---

## 사전 검증

- [ ] Dev 빌드 성공
- [ ] Prod 빌드 성공
- [ ] Smoke test 완료

---

## 릴리즈 후 모니터링

- {모니터링 항목}
- {롤백 조건}
