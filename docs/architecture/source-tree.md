# Source Tree

## 실제 프로젝트 구조

```text
voyager-app/
├── apps/
│   ├── backend/
│   │   ├── src/
│   │   │   ├── app/             # FastAPI app, CLI, config load
│   │   │   ├── core/            # file_crawler, chunker, loader_router
│   │   │   ├── infra/           # db(engine/bootstrap/migrations), schemas, repositories
│   │   │   └── utils/           # paths, helpers
│   │   ├── alembic.ini
│   │   └── pyproject.toml
│   └── macos/Voyager/
│       ├── Voyager/             # SwiftUI app sources
│       ├── VoyagerHelper/       # Backend process/env helpers
│       ├── VoyagerTests         # Unit tests
│       └── VoyagerUITests       # UI tests
├── scripts/
│   ├── prepare-backend-venv.sh  # Release 빌드용 백엔드 venv 준비 스크립트
│   └── load-secrets-from-keychain.sh  # macOS Keychain에서 시크릿 로드
└── docs/                        # PRD, architecture
```

## 핵심 모듈과 역할

- macOS
  - `VoyagerApp.swift`: 앱 엔트리, `AppDelegate` 등록
  - `AppDelegate.swift`, `FileManagerWindowController.swift`: 라이프사이클/윈도우 관리
  - `Features/FileManager/*`: 파일 관리자 UI용 View/State/Reducer(TCA)
  - `KeyCommandView.swift`: 키다운 처리(NSViewRepresentable) — Dock 트리거 후보
  - `VoyagerHelper/BackendManager*.swift`: `uv` 통해 백엔드 프로세스 실행, `.env` 로드
- Backend
  - `app/main.py`: lifespan에서 설정/DB 초기화 및 Alembic 리비전 로그 출력
  - `infra/db/engine.py`, `infra/db/bootstrap/*`: DB 엔진/마이그레이션 부트스트랩
  - `infra/schemas/file_entry_schema.py`: 파일 엔트리용 SQLModel 스키마
  - `infra/repositories/file_entries.py`: upsert/batch_upsert 제공 리포지토리
  - `app/file/file_services.py`: `VoyagerOSXMetaData` → 스키마 변환 유틸
  - `core/file_crawler/*`: macOS 속성 기반 메타데이터 추출(`osxmetadata`)
  - `core/chunker/*`: 텍스트 분할/토큰화 유틸(옵션)

## 저장소 구조(현실)

- 형태: 단일 저장소(monorepo) — 백엔드와 macOS 앱 포함
- 빌드/패키징:
  - 백엔드: `uv` + `pyproject.toml`
  - macOS: `apps/macos/Voyager`의 Xcode project/workspace
- 특이사항:
  - `apps/backend`에 로컬 SQLite DB 아티팩트(예: `voyager.dev.db`) 존재
  - macOS의 백엔드 매니저가 3종(`BackendManager*`)으로 중복된 책임 소지가 있음
