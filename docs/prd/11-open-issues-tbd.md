# 11. 오픈 이슈(확인 필요)

1) Command Dock 단축키 최종 확정(시스템/앱 충돌 점검)
2) 임베딩 프로바이더(로컬 vs 외부) 1차 선택 및 키 관리 정책
3) 컬렉션 재질의 vs 스냅샷 기본값
4) macOS 최소 지원 버전 확정: 13.5 (Ventura)
5) 민감 경로/파일 유형 인덱싱 제외 규칙

---

부록: 참고 경로

- macOS Entry: `apps/macos/Voyager/Voyager/App/VoyagerApp.swift`
- Key Commands: `apps/macos/Voyager/Voyager/Features/FileManager/KeyCommandView.swift`
- Backend Entry: `apps/backend/src/app/main.py`
- Repositories: `apps/backend/src/infra/repositories/file_entries.py`
- Chunker/Crawler: `apps/backend/src/core/{chunker,file_crawler}`
