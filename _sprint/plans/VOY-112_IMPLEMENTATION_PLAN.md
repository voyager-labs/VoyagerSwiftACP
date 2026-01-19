# VOY-112 구현 계획

## 목표/범위
- 이슈: VOY-112 — 시스템 프로퍼티 레지스트리 JSON SSOT 전환 및 shared 배포
- 핵심: `shared/system_property_registry.json`, `shared/property_key_registry.json`을 SSOT로 두고
  백엔드/Swift 앱 번들에 동일 파일 세트를 포함해 참조한다.
- 제외: DB 시드/마이그레이션, 자연어 파서/LLM 변환 로직 변경, 신규 operator 도입

## 전제/의존성
- 레지스트리 구조는 **키 기반 JSON**으로 확정
- 레지스트리 파일명: `shared/system_property_registry.json`, `shared/property_key_registry.json`
- Swift 앱은 **번들 리소스**로 포함하여 로딩
- 백엔드는 **동일 파일 세트**를 로드하도록 전환

## 전체 흐름(고수준)
1) 레지스트리 JSON 정의 확정 및 이관
2) 백엔드 로더 전환 + 경로 해석 처리
3) Swift 번들 리소스 포함 + 로딩 경로 정리
4) 문서/스모크 테스트 갱신

## 고려해야 할 사이드이펙트(전부 반영)
- **백엔드 로딩 경로 변경**: 기존 코드 레지스트리 → JSON 로드
- **경로 해석 문제**: 백엔드 실행 위치에 따라 상대경로가 달라짐
- **번들 누락 위험**: Swift 앱 번들에 파일이 포함되지 않으면 런타임 실패
- **문서/코드 참조 갱신 필요**: 기존 레퍼런스 경로/설명 업데이트 필요
- **변경 영향 범위 확대**: SSOT 전환으로 백엔드/클라이언트 모두 영향

## 세부 태스크 & 커밋 분리(Phase 단위)

아래 문서에 각 Phase의 세부 실행 계획/검증/사이드이펙트를 상세히 정리한다.

- Phase 1: 레지스트리 JSON 도입  
  - 문서: `VOY-112_PHASE_1_REGISTRY_JSON.md`
  - 대표 커밋: `chore(shared): add system_property_registry.json`
  - 대표 커밋: `chore(shared): add property_key_registry.json`

- Phase 2: 백엔드 로더 전환  
  - 문서: `VOY-112_PHASE_2_BACKEND_LOADER.md`
  - 대표 커밋: `feat(backend): load registry from shared JSON`

- Phase 3: Swift 번들 포함 및 로딩 경로 정리  
  - 문서: `VOY-112_PHASE_3_SWIFT_BUNDLE.md`
  - 대표 커밋: `feat(macos): bundle system_property_registry.json`
  - 대표 커밋: `feat(macos): bundle property_key_registry.json`

- Phase 4: 문서/테스트 정리  
  - 문서: `VOY-112_PHASE_4_DOCS_TESTS.md`
  - 대표 커밋: `docs: update registry refactor docs` / `test: add registry load smoke check`

## 검증/체크리스트
- [ ] `shared/system_property_registry.json` 로드 성공
- [ ] `shared/property_key_registry.json` 로드 성공
- [ ] 백엔드에서 레지스트리 키 조회 가능
- [ ] Swift 앱에서 번들 리소스 로드 가능
- [ ] 문서 최신화 완료
- [ ] 포맷/정리 실행(개발 작업 후)

## 롤백 전략
- JSON 로더 전환 이전 상태로 되돌리고 기존 Python 레지스트리 복구
- 번들 리소스 추가 롤백
- 문서/테스트 변경 롤백
