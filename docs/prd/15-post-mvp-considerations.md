# 15. Post‑MVP Considerations

## 15.1 Future Enhancements (Roadmap)
- Phase A: 비동기 인덱싱 전환
  - `/index` 비동기화, 작업 큐 도입(간단 워커), 상태 조회 엔드포인트(`/index/status`)
  - 기본 스케줄러(주기/쿼터) 및 취소/재시도 설계
- Phase B: 임베딩 기반 검색(플러거블)
  - 프로바이더 플러그인(로컬/외부) + 하이브리드 스코어링(메타+임베딩)
  - 캐시/스토리지 전략 및 비용/지연 관리
- Phase C: 고급 필터/패싯/저장 쿼리 빌더
  - UI 필터링/정렬 확장, 쿼리 템플릿 저장/공유(개인 범위)
- Phase D: 컬렉션 UX 강화
  - 핀/정렬/메모, 라우팅 개선, 키보드 액션 확장
- Phase E: 멀티 유저/동기화(장기)
  - 계정/동기화/권한 모델, 충돌 처리
- Phase F: 자동 업데이트(Sparkle)
  - Sparkle 2.x 프레임워크 통합
  - EdDSA 서명 키 생성 및 관리
  - GitHub Releases 기반 앱캐스트 또는 별도 업데이트 서버
  - 업데이트 알림 UI 및 백그라운드 체크

## 15.2 Monitoring & Feedback
- Logging
  - uvicorn 기본 + 구조화 로그(레벨/라우트/메서드/상태/지연_ms/에러코드/trace_id)
  - 민감 데이터/경로는 마스킹(PII/경로 스크러빙)
- Metrics
  - API: 지연 p50/p95, 에러율
  - 인덱싱: 처리량/실패율/대기열 길이
- Error Handling
  - 사용자용 안내문: 재시도/오프라인 가이드, 비식별 오류 코드
  - 기능 플래그와 폴백 경로를 문서화
- Feedback
  - 사용자 Quick Help(14장) 링크 노출
  - 이슈 템플릿 안내(민감 정보 포함 금지)
