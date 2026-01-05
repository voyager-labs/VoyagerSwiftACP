# Stories Index

스토리 문서의 루트입니다. 스토리 파일은 이 디렉터리에 추가되며, 파일명은 관례적으로 `{epic}.{story}.md` 형태를 사용합니다.

예시
- `1.1.story.md` — Epic 1의 Story 1

관련 문서
- PRD: `../prd/index.md`
- 아키텍처: `../architecture/index.md`
- 프런트엔드 스펙: `../frontend/index.md`

## Epic 1 — Onboarding (VOY-111)

- 구현 아키텍처: SwiftUI + TCA 기반(`OnboardingFeature` 루트 + Step Feature 조합, `Scope`로 구성)
- `1.1.onboarding-window-skeleton.md` — Launch routing + Onboarding Window 스켈레톤
- `1.2.onboarding-session-persistence.md` — 스텝 상태머신 + 저장/재개 + 종료 확인
- `1.3.beta-access-server-verification.md` — Beta Access 서버 검증 스텝
- `1.4.permissions-fda-launch-at-login.md` — FDA 권한 스텝 + (선택) Launch at Login
- `1.5.obt-preview-and-complete.md` — OBT 프리셋 프리뷰 + 완료 처리 + 파일 관리자 창 오픈
