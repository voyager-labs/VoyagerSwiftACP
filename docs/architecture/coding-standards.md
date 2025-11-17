# Coding Standards

본 문서는 프로젝트의 핵심 코딩 규칙을 빠르게 참조하기 위한 요약입니다. 상세 배경은 각 샤드 문서와 팀 규칙을 따릅니다.

## Python

- Formatter/Lint: Ruff 기준(라인 길이 100, space indent, double quotes 기본)
- Typing: Pyright `strict` 가정, 주요 모듈에 명시적 타입 힌트 유지
- Imports/Style: isort 규칙 정렬(가능 시), 네이밍은 PEP8 준수
- Hooks: `uv run pre-commit install` 후 훅에 의해 자동 포맷/검사

## Swift

- 스타일: Xcode 기본(4-space indent, `UpperCamelCase` 타입, `lowerCamelCase` 멤버)
- 네임스페이스: 공용 확장은 `VoyagerHelper` 하위로 구성
- 문서/주석: 한국어 설명, 코드/식별자는 영어 유지

## 참고

- 실행/빌드/테스트 등은 `docs/architecture/development-and-deployment.md`를 참고하세요.
- 기술 스택과 상위 구조는 `docs/architecture/tech-stack.md`를 참고하세요.
