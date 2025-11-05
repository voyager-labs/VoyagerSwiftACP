# Developer Handoff (요약)

## 구현 맵(Backend)
- 라우팅 파일: `apps/backend/src/app/routes/{search.py,index.py,collections.py}` 생성 후 `app/main.py`에서 `include_router`로 연결
- 계약: 본 문서(API Contracts) 및 PRD 샤드의 계약/정책(`docs/prd/6-architecture-and-integration.md`, `docs/prd/9-acceptance-criteria-and-success-metrics.md`) 준수
- 에러 매핑: 유효성 오류→`400/422`, 내부 오류→`500`(표준 에러 페이로드), 타임아웃 로그 표시
- 마이그레이션: Alembic `versions/`에 증분 리비전 생성(auto‑gen 검토) → Expand–Migrate–Contract 전략 준수

## 구현 맵(macOS)
- DockView(신규)와 FileManagerView 결합: 입력/로딩/결과/빈/오류 상태 반영(PRD 5.4)
- 접근성: 라벨/Hint/Role/포커스(PRD 5.2), 다크모드 자동 대응(시스템 기본)
- 결과 파서: 스텁/실응답 모두 수용(Feature Sequencing 가이드)

## 실행/검증 커맨드
- Backend 실행: `cd apps/backend && uv sync && uv run dev`
- 헬스체크: `curl -s http://127.0.0.1:8000/`
- 스모크 테스트: `uv run pytest -q`

## 패턴/컨벤션(요약)
- 응답 JSON: `items` + `meta`(총계/소요시간) 형태 권장
- 로깅: uvicorn 기본 + 오류 경로는 구조화 로그(레벨/경로/지연)
- Brownfield: additive 변경/feature flag/우아한 폴백 준수
