# 빠른 참조 — 핵심 파일 및 진입점

- macOS Main Entry: `apps/macos/Voyager/Voyager/App/VoyagerApp.swift`
- macOS App Delegate: `apps/macos/Voyager/Voyager/App/AppDelegate.swift`
- macOS Window Controller: `apps/macos/Voyager/Voyager/App/FileManagerWindowController.swift`
- macOS Feature (File Manager): `apps/macos/Voyager/Voyager/Features/FileManager/*`
- Key Commands Hook: `apps/macos/Voyager/Voyager/Features/FileManager/KeyCommandView.swift`
- Backend Process Management: `apps/macos/Voyager/VoyagerHelper/BackendManager*.swift`
- Backend Binary Build: `scripts/build/build-backend-binary.sh` (Release 빌드용 Nuitka 바이너리 빌드)
- Backend Server Entry: `apps/backend/src/app/server.py` (Nuitka 빌드용 엔트리포인트)
- Backend Main (FastAPI): `apps/backend/src/app/main.py`
- Backend CLI (uv entry): `apps/backend/src/app/cli.py`
- Backend Config: `apps/backend/src/conf/config.yaml`, `.env.example`
- DB Engine & Bootstrap: `apps/backend/src/infra/db/{engine.py,bootstrap/*,migrations/*}`
- File Schema/Repo: `apps/backend/src/infra/schemas/file_entry_schema.py`, `apps/backend/src/infra/repositories/file_entries.py`
- File Metadata/Chunking: `apps/backend/src/core/{file_crawler,chunker}/`

PRD 연계 — 영향 영역

- macOS: Command Dock UI 및 키보드 처리
- Backend: 메타데이터 인덱싱 + 메타데이터 기반 검색 엔드포인트
- Backend: 컬렉션 영속화/조회 API
