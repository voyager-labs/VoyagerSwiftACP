# 워크어라운드와 주의점

- macOS에서 백엔드 기동을 위해 PATH 내 `uv` 필요
- Alembic 마이그레이션은 SQLModel 변경에 맞춰 버전 관리(`infra/db/migrations/versions/`)
- 메타데이터 추출은 macOS 전용(`osxmetadata`), CI/비맥 환경에서는 가드 필요

---

본 문서는 현재 시스템의 현실과 즉시적인 개선 계획을 하나의 문서로 제공합니다. 후속 작업 시 위 파일 경로와 PRD 샤드(`docs/prd/index.md`)의 계약/정책을 참조하세요.
