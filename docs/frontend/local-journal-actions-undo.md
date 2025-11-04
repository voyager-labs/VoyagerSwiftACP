# Local Journal (Actions/Undo)

목적
- 파일 액션(Rename/Move 등)의 Apply/Undo를 안전하게 수행하기 위한 최소 메타데이터를 로컬에만 저장합니다. 서버로 전송하지 않습니다.

저장소
- 경로(예): `~/Library/Application Support/Voyager/journal.db` (SQLite 권장; 대안: `.jsonl`)
- 보존: TTL 24시간 또는 1회 Undo 처리 후 삭제, 최대 크기(예: 100MB) 도달 시 순환(rotating) 삭제

저널 스키마(예시)
```txt
tables:
  plans(plan_id TEXT PK, created_at DATETIME, undo_token TEXT, expires_at DATETIME,
        will_change INT, conflicts INT, skipped INT)
  ops(plan_id TEXT, op_id TEXT, op_type TEXT, ts DATETIME,
      before_path TEXT, before_inode INT, before_dev INT, before_mtime INT,
      after_path  TEXT, after_inode  INT, after_dev  INT, after_mtime  INT,
      status TEXT, reason TEXT)
indexes:
  idx_ops_plan_id(plan_id)
```

동작 흐름
- Plan: 미리보기(메모리만, 디스크 기록 없음)
- Apply: 실제 Rename/Move 수행 → 항목별 `ops` 레코드 기록 → `undo_token` 발급
- Undo: `undo_token`으로 역연산 수행(idempotent). 충돌/누락은 보고하고 안전 복원 규칙 적용

안전 복원 규칙
- 대상 경로에 다른 파일이 존재하면 안전 접미사로 복원: `name (restored).ext`, 필요 시 `(restored 2)`
- 상위 폴더 미존재 시 자동 생성(사용자 홈/작업 루트 범위 내)
- 크로스 볼륨 Move는 copy+delete 역방향 처리
- 심볼릭 링크는 링크 자체만 다룸(타깃은 변경하지 않음)

보안/프라이버시
- 파일 내용은 저장하지 않음. 경로/속성 최소 수집
- 시스템 보호 경로를 가드(루트/라이브러리 등). 허용 목록 기반으로 동작
- 외부 업로드 없음(100% 로컬)

테스트 포인트
- rename/move → undo로 원위치 복원
- 크로스 볼륨 undo 복원
- 원래 위치 충돌 시 접미사 복원 + 충돌 리포트
- 동일 `undo_token` 재호출은 무해(no‑op)
