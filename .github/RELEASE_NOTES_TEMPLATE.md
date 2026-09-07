<!--
GitHub Release 본문 전용 template.

이 템플릿은 과거 Voyager 릴리즈 본문에서 반복적으로 사용한
사용자 변경사항·내부 변경사항·제외 범위·검증·게시 기록·롤백 구조를 통합한 것입니다.

사용 방법:
1. 이 파일을 복사해 이번 릴리즈의 실제 값으로 채웁니다.
2. placeholder, 템플릿 설명, 미완료 checkbox, "검증 중" 상태를 모두 제거합니다.
3. `gh release edit vX.Y.Z --notes-file <완성된-본문-파일>`로 반영합니다.

작성 규칙:
- GitHub Release 본문의 설명과 섹션 제목은 한국어로 작성합니다.
- 코드, 명령어, 식별자, 버전, URL, 공식 제품명은 원문을 유지합니다.
- 포함·제외 범위와 검증 결과는 release tag/source SHA 기준으로 작성합니다.
- 사용자에게 보이는 변경사항과 내부 구현·리팩터링·QA·도구·문서 변경을 구분합니다.
- 공개 Sanity changelog는 별도의 고객-facing 문서이며, 이 템플릿과 언어·게시 절차가 다릅니다.
-->

# Voyager v{x.y.z}

## 릴리즈 개요

- 릴리즈 source: `{origin/develop 또는 origin/main}`
- source SHA: `{릴리즈 범위의 기준 SHA}`
- release candidate SHA: `{최종 release candidate SHA}`
- 릴리즈 대상: `{macOS 또는 대상 플랫폼}`
- 릴리즈 일자: `{YYYY-MM-DD}`
- 변경 규모: `{선택 사항: 커밋 수, 변경 파일 수, additions/deletions}`

## 핵심 변경사항

### 기능 및 개선

- [#{PR 번호}]({PR URL}) / [{VOY 이슈}]({Linear URL}) — {사용자 관점의 기능 또는 개선 요약}

### 버그 수정 및 안정성

- [#{PR 번호}]({PR URL}) / [{VOY 이슈}]({Linear URL}) — {사용자가 경험하는 문제와 수정 결과}

## 내부 구현·리팩터링·QA

### 내부 구현 및 리팩터링

- [#{PR 번호}]({PR URL}) / {VOY 이슈} — {사용자-facing 변경이 아닌 내부 구조 변경 요약}

### 테스트·QA 및 릴리즈 게이트

- [#{PR 번호}]({PR URL}) / {VOY 이슈} — {테스트, fixture, host gate 또는 release gate 변경 요약}

### 도구·문서·릴리즈 계보

- [#{PR 번호}]({PR URL}) — {개발 도구, canonical documentation, submodule, main → develop 동기화 등}

## 명시적 제외

- [#{PR 번호}]({PR URL}) / {VOY 이슈} — {release source에 포함되지 않은 이유}
- {로컬 전용 변경, 다른 플랫폼 릴리즈, 아직 병합되지 않은 작업 등}

## 호환성 및 마이그레이션

- {사용자 데이터·파일 포맷·database·entitlement·network API migration 또는 "없음"}
- {기존 버전과의 호환성, deployment target, persistence 또는 인증 계약 변경}
- {이번 릴리즈의 알려진 호환성 제한}

## 릴리즈 후보 검증

- 통과 — `{검증 명령 또는 workflow}`: {실제 결과, 테스트 수, exit status}
- 미실행 — `{검증 명령}`: {실행하지 않은 이유와 남은 영향}
- 실패 — `{검증 명령}`: {실패 원인, 영향 범위, 완화 또는 후속 조치}
- {정확한 release candidate SHA, runner 상태, package/host/build/test 범위}

## 알려진 공백 / 수동 QA

- {자동화되지 않은 수동 시나리오 또는 환경 의존 검증}
- {사용자 설치, entitlement, VoiceOver, IME 등 미실행 항목}
- {없으면 "없음"}

## 공개 고객 변경 로그

- Sanity 문서: `{document ID, revision, 제목, version/date}`
- 공개 changelog: `{URL 및 read-back 결과}`
- Sparkle release-notes endpoint: `{URL, HTTP 상태, content type, non-empty/safe HTML 결과}`
- {고객-facing 문서에서 제외한 내부 정보가 있으면 기록}

## 프로덕션 게시 기록

- Release PR 및 tag: `{PR URL, merge commit, tag SHA}`
- Production workflow: `{workflow URL, signing/notarization/package/R2 결과}`
- 공개 artifact metadata: `{latest.json, DMG/ZIP, appcast, manifest URL·version·build·checksum 또는 HTTP 결과}`
- 후속 동기화: `{main → develop PR 또는 해당 없음}`
- {아직 게시 전이면 각 항목을 "미실행"으로 기록하고 게시 전 상태를 명시}

## 롤백 방침

- {이전 버전의 signed/notarized artifact 및 public metadata/appcast를 rollback baseline으로 기록}
- {게시 전·게시 후·artifact 게시 후의 대응 절차}
- {이미 공개된 versioned artifact bytes를 in-place로 교체하지 않는 등 필요한 제한}

## 전체 변경 내역

{이전 버전과 현재 버전의 compare URL}
