# Example Feature-Spec PR Context

This note captures the branch context used to draft the example PR body in [example_feature_spec_pr_body.md](example_feature_spec_pr_body.md).

## Snapshot

- Compare target: `main...voy-235`
- Snapshot date: `2026-04-20`
- Diff summary at the time of writing: `129 files changed, 6329 insertions(+), 4184 deletions(-)`

## Why This Example Is Useful

The branch is broader than an ideal feature-spec issue PR, so it shows two things at once:

- how to keep `Intent` prose-first even when the branch touches multiple related lanes
- how to write `Spec Delta` as reviewer-facing decision paragraphs instead of field-by-field bullet dumps

The branch also touched harness and authoring-lane work, but the sample PR body intentionally keeps `Spec Delta` focused on spec-side blocks so that `관련 ids / keys` points to stable artifacts instead of vague meta labels.

## Commit Groups Used To Derive The Narrative

### 1. CBW recategorization and interaction spec bundle

- `fe5fdf5` Contextual chat request 카테고리 contract와 flow 문서 초안 작성
- `43c8662` FEATURE_SPEC contract 문서의 OBJECTS 연계 기준 강화
- `fc2db73` Feature Inventory와 CDA 시나리오 스펙의 카테고리 키를 CBW 체계로 동기화한다
- `a95b167` CBW 체계로 기능 사양 문서를 재배치하고 카탈로그 참조를 정합한다
- `6718ab9` CBW 삭제 대상 기능 스펙을 정리하고 FEATURE/INTERACTIONS 카탈로그를 정합한다
- `c5edc01` CBW-001 채팅 요청 lifecycle 스펙 정합성 보강

### 2. CBW contracts and flows as shared spec-side artifacts

- `fe5fdf5` Contextual chat request 카테고리 contract와 flow 문서 초안 작성
- `43c8662` FEATURE_SPEC contract 문서의 OBJECTS 연계 기준 강화

### 3. CBW catalog alignment around the new bundle

- `fc2db73` Feature Inventory와 CDA 시나리오 스펙의 카테고리 키를 CBW 체계로 동기화한다
- `a95b167` CBW 체계로 기능 사양 문서를 재배치하고 카탈로그 참조를 정합한다
- `6718ab9` CBW 삭제 대상 기능 스펙을 정리하고 FEATURE/INTERACTIONS 카탈로그를 정합한다

## Raw Commit Sequence

The example PR body was written after reviewing the following commit range.

```text
fc2db73 Feature Inventory와 CDA 시나리오 스펙의 카테고리 키를 CBW 체계로 동기화한다
a95b167 CBW 체계로 기능 사양 문서를 재배치하고 카탈로그 참조를 정합한다
6718ab9 CBW 삭제 대상 기능 스펙을 정리하고 FEATURE/INTERACTIONS 카탈로그를 정합한다
7f71273 CBW 채팅 요청 흐름 임시 인터랙션 스펙 초안 추가
e2dab20 FEATURE_SPEC 생성 문서의 내부 지시문 분리 규칙 보강
884504e CBW 채팅 시나리오 스펙의 상태 업데이트 및 프로바이더 확장 정비
fdea1f3 FEATURE_SPEC 생성 스크립트 파일명 규칙을 interaction_id 기반으로 정합
65b3c5c CBW 인터랙션 스펙 파일명 slug 제거 기준 적용과 카탈로그 동기화
c0ba3e2 CBW 채팅 스펙의 Related Interactions 링크 정합성 정비
6991ada find-skills 스킬 추가와 잠금 파일 등록
dc0bcec FEATURE 인벤토리·스펙 작성 스킬의 단축키 표기 규칙 정리
1de64fc FEATURE_SPEC 작성 규칙의 단일 출처를 guide로 통합
c5edc01 CBW-001 채팅 요청 lifecycle 스펙 정합성 보강
bccdaa6 FI·IA·FS contract consistency 검증 도구와 평가 픽스처 추가
230f249 voyager-linear-issue-author 출력 정책과 저장소 안내 정비
0a8abe8 PRODUCT 전용 에이전트 하네스를 추가하고 Codex 서브에이전트 역할을 재정리
7cc67ae skill-creator 평가 루프를 Claude/Codex 호환 구조로 개편
b9665d5 Voyager 문서 스킬을 product-owner 체계로 통합 정리
1a3f431 Codex 에이전트 참조 경로를 product-owner 체계로 동기화
ca78d79 skills-lock에 skill-creator 잠금 정보 추가
013144e product_owner 하네스와 authoring·checking 레일의 역할 정의 정리
b85f0f7 META 디렉토리 정리와 문서 운영 규칙 이관
64f801a product_owner 오케스트레이션의 기본 동작을 위임 중심으로 정비
43c8662 FEATURE_SPEC contract 문서의 OBJECTS 연계 기준 강화
fe5fdf5 Contextual chat request 카테고리 contract와 flow 문서 초안 작성
c44ed9f Merge branch 'main' into voy-235
5d10b64 PRODUCT/06_USE_CASES 레거시 초안 묶음 삭제
dd86364 Taplo 기반 TOML 포맷·검사 환경 구성
b5e18b1 PRODUCT 하네스의 reference-only 기준과 서브에이전트 역할 재정리
e56cc1a .codex/config.toml의 멀티에이전트 실행 설정 보강
5e8c180 linear-cli 스킬 추가와 문서 생성 기반 구축
24ce22a FEATURE_SPEC 정의 이슈와 구현 이슈 작성 경로 분리
```
