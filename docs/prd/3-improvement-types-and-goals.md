# 3. 개선 유형 및 목표

- 개선 유형(체크):
  - [X] New Feature Addition (Command Dock, AI 컬렉션)
  - [X] Integration with New Systems (임베딩/검색 파이프라인)
  - [X] UI/UX Overhaul (부분 적용: Dock UI 추가 및 단위 UX 개선)
  - [ ] Performance/Scalability Improvements (후속)

## 목표(Goals)

- 기본 파일 관리자 UX 제공(사이드바/목록/내용 영역) 기반 상단 또는 적절 위치의 Command Dock 통합
- 자연어 질의 → 메타데이터 기반 검색(초기) → 검색 결과를 화면에 표시하고, 사용자가 이를 컬렉션으로 저장/관리
- macOS 클라이언트와 FastAPI 백엔드를 안정적으로 연동하고, 로컬 개발자 경험(시동/로그/설정)을 간소화

### MVP Scope Boundary
- In-Scope (MVP)
  - Command Dock UI(토글/포커스/ESC/기본 접근성)
  - 메타데이터 기반 검색(`/search`) — 결과 표준 포맷 + 기본 정렬
  - 인덱싱(`/index`) — 동기 요약(후속 비동기 전환 예정)
  - 결과 표시(UI) — 리스트/그리드, 키보드 내비, Empty/Error/Loading 상태
  - 로컬 SQLite + Alembic(Expand–Migrate–Contract 전략 기반)
  - 로컬 개발 실행/로그/간단 스모크
- Deferrals (Post‑MVP)
  - 임베딩 기반 유사도/랭킹, 외부 LLM 호출(키 설정 시 선택적으로 연계)
  - 고급 필터/패싯/저장 쿼리 빌더
  - 백그라운드 스케줄러/증분 인덱싱 최적화
  - 다중 창 레이아웃/고급 뷰어 통합
  - 팀/멀티 유저/클라우드 동기화

## 비목표(Non-Goals)

- 노트/지식관리/뷰어/에디터 대체 지향 아님(해당 기능의 실행은 특화 앱이 주체)
- 클라우드 스토리지 대체 또는 동기화 엔진/가상 드라이브 제공 목적 아님
- 팀 협업 워크스페이스 범위 아님
- 사용자의 의지에 반하는 백그라운드 자동 정리, 강제 이름 변경·재구조화 없음
- macOS 전용. Windows/Web/모바일은 이후 검토
- 데이터 수집·광고 기반 수익 모델 아님
- 계정 로그인 필수 아님
