# 통합 포인트와 외부 의존

## 외부 서비스

- 고정 의존 없음. 임베딩 프로바이더(OpenAI/로컬 모델 등)는 후속 플러그인 방식으로 도입 예정

## 내부 통합 포인트

- macOS → `/usr/bin/env` + `uv`로 백엔드 프로세스 스폰
- 환경변수 예시: `UV_CMD`, `BACKEND_DIR`, `APP_ENV`, `VOYAGER_LOG_FILE`, `VOYAGER_PATH`

## 외부 의존 & 비밀키 관리(가이드)

- LLM Provider(선택): `OPENAI_API_KEY`, `OPENAI_ORG_ID`, `OPENAI_PROJECT`
  - 키가 비어 있으면(기본값) LLM 기능은 비활성로 간주하고, 메타데이터 검색 경로만 사용
  - 로컬: `.env`에 설정(커밋 금지), 예시는 `.env.example` 참고
  - CI: GitHub Actions `Secrets`에 보관 후 필요 워크플로에서 주입
  - 회수/교체: 노출 의심 시 즉시 회수/교체하고 커밋 기록에서 제거(필요 시 force push 금지, 보안팀 절차 준수)

- 외부 API 장애/제한 대응
  - 타임아웃 기본 적용(구성값 기반) 및 재시도(지수 백오프) 고려
  - 실패 시 사용자 친화적 오류 메시지와 폴백 경로 제공(LLM 미사용 플로우 유지)
  - 레이트 리밋/쿼터 초과 시 지연/알림 처리
