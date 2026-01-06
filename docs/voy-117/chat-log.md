# VOY-117 Chat Log

## 컨텍스트
- Linear: VOY-117 "VoyagerHelper 프로세스 생명주기 관리 개선"
- 팀: Product
- 목적: Helper/Backend 생명주기 정책 확정과 구현 계획 수립
- 비범위: Linear 상태/라벨/담당자 업데이트 (요청 없음)

## 대화 로그 (chat-mode)
- User: As bmad-orchestrator, *chat-mode, $linear Product 팀의 VOY-117을 구현하고자 해. 관련 계획을 chat-mode를 통해 계획을 세워봐.
- BMad Orchestrator:
  - 이해한 목표: VOY-117 요구사항을 기준으로 Helper/Backend 생명주기 정책을 코드 반영하는 구현 계획 수립
  - 범위 가정: 이번 스텝은 계획 수립과 변경 후보 식별까지만 수행 (코드 변경/Linear 업데이트는 별도)
  - 계획:
    1) 현행 동작 점검
       - `apps/macos/Voyager/Voyager/App/Features/AppLifecycleFeature.swift`에서 Helper 시작/종료/감시 흐름 확인
       - `apps/macos/Voyager/Voyager/App/Clients/HelperAppClient.swift`에서 Helper 감시 이벤트 스트림 확인
       - `apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperLifecycle.swift`와 `apps/macos/Voyager/VoyagerHelper/Infrastructure/ProcessRunner.swift`에서 backend 종료 감지/재기동 유무 확인
    2) 정책 반영 설계
       - Voyager 종료 시 Helper 종료 로직 제거
       - Helper 종료 감지 시 backoff + 최대 재시도, 초과 시 Voyager 강제 종료
       - backend 종료 감지 시 Helper가 backoff 재기동(현행에 없으면 추가)
    3) 구현 후보 정리
       - `apps/macos/Voyager/Voyager/App/Features/AppLifecycleFeature.swift`
       - `apps/macos/Voyager/Voyager/App/Clients/HelperAppClient.swift`
       - `apps/macos/Voyager/VoyagerHelper/Infrastructure/HelperLifecycle.swift`
       - `apps/macos/Voyager/VoyagerHelper/Infrastructure/ProcessRunner.swift`
       - `apps/macos/Voyager/VoyagerHelper/VoyagerHelperApp.swift`
    4) 엔드포인트 탐지/환경 SSOT 정리
       - UI에서 `pgrep` + `lsof` 기반 포트 탐지 유틸 추가 위치 결정
       - `.env`만 SSOT로 사용하고 runtime config/BackendState 공유 로직 제거 여부 확인
    5) 검증
       - Linear 체크리스트 기반 수동 QA
       - 가능하면 Helper/리트라이 로직 단위 테스트 추가
  - 결정 필요:
    - backoff 간격/최대 재시도 횟수
    - 최대 재시도 초과 시 종료 UX (즉시 종료 vs 알림 후 종료)
    - backend 재기동 실패 시 로그 포맷/레벨

## 검증 체크리스트
- Voyager 실행 → Helper 실행 → backend 실행 → UI 요청 성공
- Voyager 종료 후 Helper/Backend 지속 동작
- Helper 강제 종료 시 backoff 재시작, 최대 재시도 초과 시 Voyager 종료
- backend 강제 종료 시 Helper가 재기동 + UI가 포트 재탐지
- `PUBLIC_BACKEND_PORT=0`에서도 포트 탐지 정상
- Launch at startup 활성화 후 로그인 시 UI 자동 실행, Helper는 Voyager 시작 시 실행
- source/bundled 모두 `Voyager Backend` 프로세스명 탐지 가능
