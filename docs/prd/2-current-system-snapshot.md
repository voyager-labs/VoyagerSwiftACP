# 2. 기존 시스템 스냅샷(현실)

- macOS 앱(workspace): `apps/macos/Voyager`
  - 진입점: `apps/macos/Voyager/Voyager/App/VoyagerApp.swift`
  - AppDelegate/윈도우 관리: `AppDelegate.swift`, `FileManagerWindowController.swift`
  - 파일 관리자 기능 스켈레톤: `Features/FileManager/*` (뷰, 상태, 키입력 훅)
  - 백엔드 프로세스 관리: `VoyagerHelper/BackendManager*.swift` (`uv run dev` 등 호출)
- 백엔드 서비스: `apps/backend`
  - 진입점: `src/app/main.py` (FastAPI, lifespan에서 설정/DB 초기화)
  - DB 및 마이그레이션: SQLModel + Alembic (`infra/db/**`, `alembic.ini`)
  - 파일 엔트리 스키마/저장소: `infra/schemas/file_entry_schema.py`, `infra/repositories/file_entries.py`
  - 파일 메타/크롤러/청크: `core/file_crawler/**`, `core/chunker/**`

관측 정리:

- macOS 쪽에 키 커맨드 훅(`KeyCommandView`)이 존재하므로 Command Dock 호출/포커스 제어에 활용 가능.
- 백엔드는 SQLite 개발 DB와 Alembic 마이그레이션이 이미 연동되어 초기 인덱싱/검색(메타데이터) 기능 추가에 적합.
