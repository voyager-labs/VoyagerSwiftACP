# Voyager 문서

이 문서는 AI 에이전트용(PRD/아키텍처/스펙) 문서 인덱스입니다. 사람도 읽기 좋게 유지합니다.

## 문서 원칙

- `docs/`는 설계/아키텍처/기능 설명(why/how, 다이어그램 포함)을 위한 문서 공간입니다.
- 강제 규칙(Do/Don't, 컨벤션, globs 기반 적용)은 `.agents/rules/`를 SSOT로 유지합니다.
- 절차/워크플로우(스크립트 포함)는 `.agents/skills/`를 사용합니다.

## 아키텍처

- [시스템 개요](architecture/overview.md)
- [macOS 앱 구조](architecture/macos-app.md)
- [환경 설정 (ENV)](architecture/environment.md)
- [Registry JSON (스펙/운영)](architecture/registries.md)
- [기술 스택](architecture/tech-stack.md)
- [소스 트리](architecture/source-tree.md)
- [코딩/작업 규칙 요약](architecture/coding-standards.md)

## 주요 기능

- [검색 (LLM → 조건 변환)](features/search.md)
- [인덱싱 (초기/증분)](features/indexing.md)
- [조건 컴포저](features/composer.md)
- [엔트리/컬렉션](features/entries-collections.md)
- [설정](features/settings.md)
- [업데이트](features/update.md)
- [온보딩](features/onboarding.md)

## 통합/연동

- [Helper ↔ Backend 부트스트랩](integration/backend-bootstrap.md)

## macOS

- [macOS 빌드/실행](macos/build-and-run.md)
- [VoyagerHelper 상세 문서](macos/voyager-helper.md)

## 개발/테스트/배포

- [개발 환경](development.md)
- [테스트](testing.md)
- [배포/번들링](deployment.md)
- [트러블슈팅](troubleshooting.md)

## Product (Drive)

- [Google Drive PRD 연동](product/google-drive.md)
