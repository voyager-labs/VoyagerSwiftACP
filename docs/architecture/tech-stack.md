# Tech Stack

프로젝트 전반의 실제 기술 스택과 로컬 툴체인 기준을 한곳에 모았습니다. 상위 수준 아키텍처 요약도 본 문서에 포함합니다.

## 기술 요약

- 클라이언트: SwiftUI + The Composable Architecture(TCA) 기반 macOS 앱. 키 입력/윈도우 제어에 AppKit 브리지가 일부 사용됨.
- 헬퍼: `VoyagerHelper`가 `.env` 값으로 `uv run dev|prod`를 호출하여 백엔드 프로세스를 실행.
- 서버: FastAPI 서비스가 lifespan에서 설정/SQLite DB(SQLModel + Alembic)를 초기화. 현재는 루트 엔드포인트만 제공.
- 데이터: Alembic 마이그레이션이 준비된 SQLite. 파일 메타데이터 스키마/리포지토리 존재. 로컬 개발 DB 아티팩트가 커밋됨.
- 처리: 파일 메타 수집(`osxmetadata`)을 포함한 크롤러와 텍스트 분할 유틸(Chunker) 보유.

## 실제 기술 스택

| 범주    | 기술                        | 버전/비고                               |
| ------- | --------------------------- | --------------------------------------- |
| 런타임  | Python (uv toolchain)       | Python >= 3.13 (via `pyproject.toml`) |
| Web API | FastAPI                     | 0.116.1                                 |
| ORM/DB  | SQLModel + SQLite + Alembic | SQLModel 0.0.24; Alembic 구성 완료      |
| Mac App | SwiftUI + TCA + AppKit      | Xcode 기본 스타일                       |
| 유틸    | osxmetadata, pandas, numpy  | 메타데이터/전처리 목적                  |
| 패키징  | uv + uvicorn                | CLI 스크립트: `dev`, `prod`             |

### Toolchain Baseline (Local)
- macOS: 최소 13.5 (Ventura)
- Xcode: 15+
- Python: 3.13+
- uv: 최신(stable) 버전이 PATH에 노출되어야 함

### Compatibility Status (as of 2025-11-03)
- FastAPI 0.116.1 / SQLModel 0.0.24 / Alembic 구성 조합은 로컬 환경에서 마이그레이션 적용 및 기동 검증 완료

## 참고

- 데이터 모델/API 초안: `docs/architecture/data-model-and-api.md`
